import 'dart:async';
import 'package:flutter/services.dart';

/// Method channel bridge between Flutter UI and Android native VPN service.
/// All DNS interception and DoH forwarding is handled in native Java code.
class VpnChannelService {
  static const MethodChannel _channel =
      MethodChannel('com.interguard.app/vpn');
  static const EventChannel _statusChannel =
      EventChannel('com.interguard.app/vpn_status');

  // Singleton
  static final VpnChannelService _instance = VpnChannelService._internal();
  factory VpnChannelService() => _instance;
  VpnChannelService._internal();

  Stream<bool>? _statusStream;

  Stream<bool> get statusStream {
    _statusStream ??= _statusChannel
        .receiveBroadcastStream()
        .map((event) => event as bool);
    return _statusStream!;
  }

  /// Request VPN permission and start the VPN service.
  /// Returns true if started, false if permission denied or error.
  Future<bool> startVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('startVpn');
      return result ?? false;
    } on PlatformException catch (e) {
      print('[VpnChannelService] startVpn error: ${e.message}');
      return false;
    }
  }

  /// Stop the VPN service.
  Future<void> stopVpn() async {
    try {
      await _channel.invokeMethod('stopVpn');
    } on PlatformException catch (e) {
      print('[VpnChannelService] stopVpn error: ${e.message}');
    }
  }

  /// Returns whether the VPN service is currently running.
  Future<bool> isVpnRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isVpnRunning');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Returns map: {'totalQueries': int, 'blockedQueries': int, 'uptimeMs': int}
  Future<Map<String, dynamic>> getStats() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('getStats');
      return result ?? {};
    } on PlatformException {
      return {};
    }
  }

  /// Returns list of recent DNS query log entries.
  Future<List<Map<dynamic, dynamic>>> getLogs() async {
    try {
      final result =
          await _channel.invokeListMethod<Map>('getLogs');
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } on PlatformException {
      return [];
    }
  }

  /// Clear all stored query logs.
  Future<void> clearLogs() async {
    try {
      await _channel.invokeMethod('clearLogs');
    } on PlatformException catch (e) {
      print('[VpnChannelService] clearLogs error: ${e.message}');
    }
  }

  /// Save the DoH server URL to SharedPreferences.
  Future<void> setDoHUrl(String url) async {
    try {
      await _channel.invokeMethod('setDoHUrl', {'url': url});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDoHUrl error: ${e.message}');
    }
  }

  /// Get the currently configured DoH server URL.
  Future<String> getDoHUrl() async {
    try {
      final result = await _channel.invokeMethod<String>('getDoHUrl');
      return result ?? 'https://dns.sacloudserver.top/dns-query';
    } on PlatformException {
      return 'https://dns.sacloudserver.top/dns-query';
    }
  }

  /// Set whether to start the VPN on device boot.
  Future<void> setStartOnBoot(bool enabled) async {
    try {
      await _channel.invokeMethod('setStartOnBoot', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setStartOnBoot error: ${e.message}');
    }
  }

  /// Get the start-on-boot setting.
  Future<bool> getStartOnBoot() async {
    try {
      final result = await _channel.invokeMethod<bool>('getStartOnBoot');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Send a real test DNS query over DoH and return result.
  Future<Map<String, dynamic>> testConnection(String url) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('testConnection',
              {'url': url});
      return result ?? {'success': false, 'message': 'No response'};
    } on PlatformException catch (e) {
      return {'success': false, 'message': e.message ?? 'Error'};
    }
  }
}
