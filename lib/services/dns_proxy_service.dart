import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class DnsProxyService {
  RawDatagramSocket? _socket;
  bool _isRunning = false;
  
  final Function(String domain, bool blocked) onQuery;
  
  DnsProxyService({required this.onQuery});

  bool get isRunning => _isRunning;

  Future<bool> start(String dohUrl) async {
    try {
      // Try to bind to port 53 (requires Admin on Windows usually)
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 53);
      _isRunning = true;
      
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _socket!.receive();
          if (dg != null) {
            _handleQuery(dg, dohUrl);
          }
        }
      });

      // Set Windows System DNS to 127.0.0.1
      await _setWindowsDns('127.0.0.1');
      
      return true;
    } catch (e) {
      debugPrint('DNS Proxy Error: $e');
      // If port 53 fails, try a high port and inform user? 
      // No, for "perfect" work we need 53 or a system setting change.
      return false;
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _socket?.close();
    _socket = null;
    await _setWindowsDns('auto'); // Restore to automatic
  }

  void _handleQuery(Datagram dg, String dohUrl) async {
    try {
      final domain = _extractDomain(dg.data);
      
      final response = await http.post(
        Uri.parse(dohUrl),
        headers: {
          'Content-Type': 'application/dns-message',
          'Accept': 'application/dns-message',
        },
        body: dg.data,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _socket?.send(response.bodyBytes, dg.address, dg.port);
        onQuery(domain, false); // Simplified: check if blocked in real app
      }
    } catch (e) {
      debugPrint('Forwarding error: $e');
    }
  }

  String _extractDomain(Uint8List data) {
    try {
      if (data.length < 13) return 'unknown';
      int pos = 12;
      List<String> parts = [];
      while (pos < data.length) {
        int len = data[pos];
        if (len == 0) break;
        pos++;
        if (pos + len > data.length) break;
        parts.add(String.fromCharCodes(data.sublist(pos, pos + len)));
        pos += len;
      }
      return parts.join('.');
    } catch (_) {
      return 'parse_error';
    }
  }

  Future<void> _setWindowsDns(String dns) async {
    if (!Platform.isWindows) return;
    
    try {
      // Get all interface names using netsh
      final result = await Process.run('netsh', ['interface', 'show', 'interface']);
      final output = result.stdout.toString();
      
      // Parse interface names (usually the last column)
      final lines = output.split('\n');
      final interfaceNames = <String>[];
      
      for (var line in lines) {
        if (line.contains('Connected') || line.contains('Disconnected')) {
          // This is a rough way to get the name, but usually it works
          // Better way: find where "Interface Name" starts in the header
          final parts = line.trim().split(RegExp(r'\s{2,}'));
          if (parts.length >= 4) {
            interfaceNames.add(parts.last.trim());
          }
        }
      }

      if (interfaceNames.isEmpty) {
        // Fallback to common names if parsing fails
        interfaceNames.addAll(['Wi-Fi', 'Ethernet', 'Local Area Connection', 'vEthernet']);
      }
      
      for (var iface in interfaceNames) {
        if (dns == 'auto') {
          await Process.run('netsh', ['interface', 'ip', 'set', 'dns', "name=\"$iface\"", 'source=dhcp']);
          // Also for IPv6
          await Process.run('netsh', ['interface', 'ipv6', 'set', 'dns', "name=\"$iface\"", 'source=dhcp']);
        } else {
          await Process.run('netsh', ['interface', 'ip', 'set', 'dns', "name=\"$iface\"", 'static', dns]);
          // For IPv6, we might want to disable it or set to a local resolver, but 127.0.0.1 is IPv4.
          // Setting IPv4 is usually enough if IPv4 is prioritized.
        }
      }
    } catch (e) {
      debugPrint('Failed to set Windows DNS: $e');
    }
  }
}
