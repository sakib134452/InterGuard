import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Method channel bridge between Flutter UI and Android native VPN service.
class VpnChannelService {
  static const MethodChannel _channel =
      MethodChannel('com.interguard.app/vpn');
  static const EventChannel _statusChannel =
      EventChannel('com.interguard.app/vpn_status');

  static final VpnChannelService _instance = VpnChannelService._internal();
  factory VpnChannelService() => _instance;
  VpnChannelService._internal();

  Stream<bool>? _statusStream;

  Stream<bool> get statusStream {
    if (Platform.isWindows) {
      return const Stream<bool>.empty();
    }
    _statusStream ??= _statusChannel
        .receiveBroadcastStream()
        .map((event) => event as bool);
    return _statusStream!;
  }

  // ─── VPN ──────────────────────────────────────────────────────────────────

  Future<bool> startVpn() async {
    if (Platform.isWindows) return true;
    try {
      return await _channel.invokeMethod<bool>('startVpn') ?? false;
    } on PlatformException catch (e) {
      print('[VpnChannelService] startVpn: ${e.message}');
      return false;
    }
  }

  Future<void> stopVpn() async {
    if (Platform.isWindows) return;
    try {
      await _channel.invokeMethod('stopVpn');
    } on PlatformException catch (e) {
      print('[VpnChannelService] stopVpn: ${e.message}');
    }
  }

  Future<bool> isVpnRunning() async {
    if (Platform.isWindows) return false; // Handled by VpnProvider
    try {
      return await _channel.invokeMethod<bool>('isVpnRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ─── Stats & Logs ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    if (Platform.isWindows) return {}; // Handled by VpnProvider
    try {
      return await _channel.invokeMapMethod<String, dynamic>('getStats') ?? {};
    } on PlatformException {
      return {};
    }
  }

  Future<List<Map<dynamic, dynamic>>> getLogs() async {
    if (Platform.isWindows) return [];
    try {
      final result = await _channel.invokeListMethod<Map>('getLogs');
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } on PlatformException {
      return [];
    }
  }

  Future<void> clearLogs() async {
    if (Platform.isWindows) return;
    try {
      await _channel.invokeMethod('clearLogs');
    } on PlatformException catch (e) {
      print('[VpnChannelService] clearLogs: ${e.message}');
    }
  }

  // ─── DoH URL ──────────────────────────────────────────────────────────────

  Future<void> setDoHUrl(String url) async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doh_url', url);
      return;
    }
    try {
      await _channel.invokeMethod('setDoHUrl', {'url': url});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDoHUrl: ${e.message}');
    }
  }

  Future<String> getDoHUrl() async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('doh_url') ?? 'https://dns.sacloudserver.top/dns-query';
    }
    try {
      return await _channel.invokeMethod<String>('getDoHUrl') ??
          'https://dns.sacloudserver.top/dns-query';
    } on PlatformException {
      return 'https://dns.sacloudserver.top/dns-query';
    }
  }

  Future<void> setFallbackDoHUrl(String url) async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fallback_doh_url', url);
      return;
    }
    try {
      await _channel.invokeMethod('setFallbackDoHUrl', {'url': url});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setFallbackDoHUrl: ${e.message}');
    }
  }

  Future<String> getFallbackDoHUrl() async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fallback_doh_url') ?? 'https://dns.adguard-dns.com/dns-query';
    }
    try {
      return await _channel.invokeMethod<String>('getFallbackDoHUrl') ??
          'https://dns.adguard-dns.com/dns-query';
    } on PlatformException {
      return 'https://dns.adguard-dns.com/dns-query';
    }
  }

  // ─── Boot setting ─────────────────────────────────────────────────────────

  Future<void> setStartOnBoot(bool enabled) async {
    if (Platform.isWindows) {
      try {
        final exePath = Platform.resolvedExecutable;
        if (enabled) {
          await Process.run('reg', [
            'add',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            'InterGuard',
            '/t',
            'REG_SZ',
            '/d',
            exePath,
            '/f'
          ]);
        } else {
          await Process.run('reg', [
            'delete',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            'InterGuard',
            '/f'
          ]);
        }
      } catch (e) {
        print('[VpnChannelService] Windows setStartOnBoot error: $e');
      }
      return;
    }
    try {
      await _channel.invokeMethod('setStartOnBoot', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setStartOnBoot: ${e.message}');
    }
  }

  Future<bool> getStartOnBoot() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query',
          'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
          '/v',
          'InterGuard'
        ]);
        return result.exitCode == 0;
      } catch (e) {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>('getStartOnBoot') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ─── Connection test ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> testConnection(String url) async {
    if (Platform.isWindows) {
      try {
        final uri = Uri.parse(url);
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/dns-message',
            'Accept': 'application/dns-message',
          },
          // Send a dummy DNS query (standard A record query for google.com)
          body: Uint8List.fromList([
            0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x06, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x03, 0x63, 0x6f, 0x6d, 0x00,
            0x00, 0x01, 0x00, 0x01
          ]),
        ).timeout(const Duration(seconds: 5));
        
        return {
          'success': response.statusCode == 200,
          'message': response.statusCode == 200 ? 'Connected successfully' : 'HTTP Error ${response.statusCode}'
        };
      } catch (e) {
        return {'success': false, 'message': e.toString()};
      }
    }
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
              'testConnection', {'url': url}) ??
          {'success': false, 'message': 'No response'};
    } on PlatformException catch (e) {
      return {'success': false, 'message': e.message ?? 'Error'};
    }
  }

  // ─── Device Identity ──────────────────────────────────────────────────────

  Future<String> getDeviceName() async {
    if (Platform.isWindows) {
      return Platform.localHostname;
    }
    try {
      return await _channel.invokeMethod<String>('getDeviceName') ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> setDeviceName(String name) async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', name);
      return;
    }
    try {
      await _channel.invokeMethod('setDeviceName', {'name': name});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDeviceName: ${e.message}');
    }
  }

  Future<String> getVirtualIp() async {
    if (Platform.isWindows) {
      // Mock virtual IP for Windows
      return '172.16.10.10';
    }
    try {
      return await _channel.invokeMethod<String>('getVirtualIp') ?? '';
    } on PlatformException {
      return '';
    }
  }

  // ─── First Launch ─────────────────────────────────────────────────────────

  Future<bool> isFirstLaunchDone() async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('first_launch_done') ?? false;
    }
    try {
      return await _channel.invokeMethod<bool>('isFirstLaunchDone') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Sets device name + base URL on first launch; returns the full DoH URL.
  Future<String> completeFirstLaunch({
    required String deviceName,
    required String baseUrl,
  }) async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('first_launch_done', true);
      await prefs.setString('device_name', deviceName);
      
      // Build full DoH URL
      final fullUrl = '$baseUrl/${Uri.encodeComponent(deviceName)}';
      await prefs.setString('doh_url', fullUrl);
      return fullUrl;
    }
    try {
      return await _channel.invokeMethod<String>(
            'completeFirstLaunch',
            {'deviceName': deviceName, 'baseUrl': baseUrl},
          ) ??
          baseUrl;
    } on PlatformException catch (e) {
      print('[VpnChannelService] completeFirstLaunch: ${e.message}');
      return baseUrl;
    }
  }

  // ─── Battery Optimization ─────────────────────────────────────────────────

  Future<bool> isBatteryOptimizationIgnored() async {
    if (Platform.isWindows) return true;
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestBatteryOptimization() async {
    if (Platform.isWindows) return;
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } on PlatformException catch (e) {
      print('[VpnChannelService] requestBatteryOptimization: ${e.message}');
    }
  }

  // ─── Per-App Filtering ────────────────────────────────────────────────────

  Future<List<Map<dynamic, dynamic>>> getInstalledApps() async {
    if (Platform.isWindows) return [];
    try {
      final result = await _channel.invokeListMethod<Map>('getInstalledApps');
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } on PlatformException catch (e) {
      print('[VpnChannelService] getInstalledApps: ${e.message}');
      return [];
    }
  }

  Future<List<String>> getDisallowedApps() async {
    if (Platform.isWindows) return [];
    try {
      final result =
          await _channel.invokeListMethod<String>('getDisallowedApps');
      return result ?? [];
    } on PlatformException {
      return [];
    }
  }

  Future<void> setDisallowedApps(List<String> packages) async {
    if (Platform.isWindows) return;
    try {
      await _channel.invokeMethod('setDisallowedApps', {'packages': packages});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDisallowedApps: ${e.message}');
    }
  }

  // ─── VPN Settings ─────────────────────────────────────────────────────────

  Future<void> openVpnSettings() async {
    if (Platform.isWindows) {
      await Process.run('control', ['ncpa.cpl']);
      return;
    }
    try {
      await _channel.invokeMethod('openVpnSettings');
    } on PlatformException catch (e) {
      print('[VpnChannelService] openVpnSettings: ${e.message}');
    }
  }
}
