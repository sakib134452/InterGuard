import 'dart:async';
import 'package:flutter/services.dart';

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
    _statusStream ??= _statusChannel
        .receiveBroadcastStream()
        .map((event) => event as bool);
    return _statusStream!;
  }

  // ─── VPN ──────────────────────────────────────────────────────────────────

  Future<bool> startVpn() async {
    try {
      return await _channel.invokeMethod<bool>('startVpn') ?? false;
    } on PlatformException catch (e) {
      print('[VpnChannelService] startVpn: ${e.message}');
      return false;
    }
  }

  Future<void> stopVpn() async {
    try {
      await _channel.invokeMethod('stopVpn');
    } on PlatformException catch (e) {
      print('[VpnChannelService] stopVpn: ${e.message}');
    }
  }

  Future<bool> isVpnRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isVpnRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ─── Stats & Logs ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('getStats') ?? {};
    } on PlatformException {
      return {};
    }
  }

  Future<List<Map<dynamic, dynamic>>> getLogs() async {
    try {
      final result = await _channel.invokeListMethod<Map>('getLogs');
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } on PlatformException {
      return [];
    }
  }

  Future<void> clearLogs() async {
    try {
      await _channel.invokeMethod('clearLogs');
    } on PlatformException catch (e) {
      print('[VpnChannelService] clearLogs: ${e.message}');
    }
  }

  // ─── DoH URL ──────────────────────────────────────────────────────────────

  Future<void> setDoHUrl(String url) async {
    try {
      await _channel.invokeMethod('setDoHUrl', {'url': url});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDoHUrl: ${e.message}');
    }
  }

  Future<String> getDoHUrl() async {
    try {
      return await _channel.invokeMethod<String>('getDoHUrl') ??
          'https://dns.sacloudserver.top/dns-query';
    } on PlatformException {
      return 'https://dns.sacloudserver.top/dns-query';
    }
  }

  Future<void> setFallbackDoHUrl(String url) async {
    try {
      await _channel.invokeMethod('setFallbackDoHUrl', {'url': url});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setFallbackDoHUrl: ${e.message}');
    }
  }

  Future<String> getFallbackDoHUrl() async {
    try {
      return await _channel.invokeMethod<String>('getFallbackDoHUrl') ??
          'https://cloudflare-dns.com/dns-query';
    } on PlatformException {
      return 'https://cloudflare-dns.com/dns-query';
    }
  }

  // ─── Boot setting ─────────────────────────────────────────────────────────

  Future<void> setStartOnBoot(bool enabled) async {
    try {
      await _channel.invokeMethod('setStartOnBoot', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setStartOnBoot: ${e.message}');
    }
  }

  Future<bool> getStartOnBoot() async {
    try {
      return await _channel.invokeMethod<bool>('getStartOnBoot') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ─── Connection test ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> testConnection(String url) async {
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
    try {
      return await _channel.invokeMethod<String>('getDeviceName') ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> setDeviceName(String name) async {
    try {
      await _channel.invokeMethod('setDeviceName', {'name': name});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDeviceName: ${e.message}');
    }
  }

  Future<String> getVirtualIp() async {
    try {
      return await _channel.invokeMethod<String>('getVirtualIp') ?? '';
    } on PlatformException {
      return '';
    }
  }

  // ─── First Launch ─────────────────────────────────────────────────────────

  Future<bool> isFirstLaunchDone() async {
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
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } on PlatformException catch (e) {
      print('[VpnChannelService] requestBatteryOptimization: ${e.message}');
    }
  }

  // ─── Per-App Filtering ────────────────────────────────────────────────────

  Future<List<Map<dynamic, dynamic>>> getInstalledApps() async {
    try {
      final result = await _channel.invokeListMethod<Map>('getInstalledApps');
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } on PlatformException catch (e) {
      print('[VpnChannelService] getInstalledApps: ${e.message}');
      return [];
    }
  }

  Future<List<String>> getDisallowedApps() async {
    try {
      final result =
          await _channel.invokeListMethod<String>('getDisallowedApps');
      return result ?? [];
    } on PlatformException {
      return [];
    }
  }

  Future<void> setDisallowedApps(List<String> packages) async {
    try {
      await _channel.invokeMethod('setDisallowedApps', {'packages': packages});
    } on PlatformException catch (e) {
      print('[VpnChannelService] setDisallowedApps: ${e.message}');
    }
  }

  // ─── VPN Settings ─────────────────────────────────────────────────────────

  Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod('openVpnSettings');
    } on PlatformException catch (e) {
      print('[VpnChannelService] openVpnSettings: ${e.message}');
    }
  }
}
