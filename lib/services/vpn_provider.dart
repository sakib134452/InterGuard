import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vpn_models.dart';
import '../services/vpn_channel_service.dart';

class VpnProvider extends ChangeNotifier {
  final VpnChannelService _ch = VpnChannelService();

  VpnStatus _status = VpnStatus.disconnected;
  VpnStats _stats = const VpnStats();
  List<QueryLog> _logs = [];
  String _dohUrl = 'https://dns.sacloudserver.top/dns-query';
  String _fallbackDoHUrl = 'https://cloudflare-dns.com/dns-query';
  bool _startOnBoot = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  // Device identity
  String _deviceName = '';
  String _virtualIp = '';

  // Battery optimization
  bool _batteryOptIgnored = false;

  // Per-app filtering
  List<AppInfo> _installedApps = [];
  List<String> _disallowedApps = [];
  bool _appsLoaded = false;

  Timer? _statsTimer;
  StreamSubscription? _statusSub;

  // ─── Getters ──────────────────────────────────────────────────────────────

  VpnStatus get status => _status;
  VpnStats get stats => _stats;
  List<QueryLog> get logs => List.unmodifiable(_logs);
  String get dohUrl => _dohUrl;
  String get fallbackDoHUrl => _fallbackDoHUrl;
  bool get startOnBoot => _startOnBoot;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == VpnStatus.connected;
  String get deviceName => _deviceName;
  String get virtualIp => _virtualIp;
  bool get batteryOptIgnored => _batteryOptIgnored;
  List<AppInfo> get installedApps => List.unmodifiable(_installedApps);
  List<String> get disallowedApps => List.unmodifiable(_disallowedApps);
  bool get appsLoaded => _appsLoaded;

  VpnProvider() {
    _init();
  }

  Future<void> _init() async {
    _dohUrl = await _ch.getDoHUrl();
    _fallbackDoHUrl = await _ch.getFallbackDoHUrl();
    _startOnBoot = await _ch.getStartOnBoot();
    _deviceName = await _ch.getDeviceName();
    _virtualIp = await _ch.getVirtualIp();
    _batteryOptIgnored = await _ch.isBatteryOptimizationIgnored();
    _disallowedApps = await _ch.getDisallowedApps();

    final running = await _ch.isVpnRunning();
    _status = running ? VpnStatus.connected : VpnStatus.disconnected;
    _stats = _stats.copyWith(status: _status, activeServer: _dohUrl);
    _isInitialized = true;
    notifyListeners();

    if (running) _startPolling();

    _statusSub = _ch.statusStream.listen(
      (isRunning) {
        final newStatus =
            isRunning ? VpnStatus.connected : VpnStatus.disconnected;
        if (_status != newStatus) {
          _status = newStatus;
          _stats = _stats.copyWith(status: _status);
          if (isRunning) {
            _startPolling();
          } else {
            _stopPolling();
          }
          notifyListeners();
        }
      },
      onError: (_) {},
    );
  }

  void _startPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStats();
    });
  }

  void _stopPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _refreshStats() async {
    final map = await _ch.getStats();
    final total = (map['totalQueries'] as int?) ?? 0;
    final blocked = (map['blockedQueries'] as int?) ?? 0;
    final uptimeMs = (map['uptimeMs'] as int?) ?? 0;
    _stats = _stats.copyWith(
      totalQueries: total,
      blockedQueries: blocked,
      uptime: Duration(milliseconds: uptimeMs),
      status: _status,
      activeServer: _dohUrl,
    );
    notifyListeners();
  }

  // ─── VPN Toggle ───────────────────────────────────────────────────────────

  Future<void> toggleVpn() async {
    _errorMessage = null;
    if (_status == VpnStatus.connected) {
      await _stopVpn();
    } else {
      await _startVpn();
    }
  }

  Future<void> _startVpn() async {
    _status = VpnStatus.connecting;
    _isLoading = true;
    notifyListeners();

    final success = await _ch.startVpn();
    _isLoading = false;

    if (success) {
      _status = VpnStatus.connected;
      _stats = _stats.copyWith(
          status: VpnStatus.connected, activeServer: _dohUrl);
      _startPolling();
    } else {
      _status = VpnStatus.disconnected;
      _stats = _stats.copyWith(status: VpnStatus.disconnected);
      _errorMessage = 'Failed to start VPN. Check permissions.';
    }
    notifyListeners();
  }

  Future<void> _stopVpn() async {
    _isLoading = true;
    notifyListeners();
    await _ch.stopVpn();
    _stopPolling();
    _isLoading = false;
    _status = VpnStatus.disconnected;
    _stats = _stats.copyWith(
        status: VpnStatus.disconnected, uptime: Duration.zero);
    notifyListeners();
  }

  // ─── Logs ─────────────────────────────────────────────────────────────────

  Future<void> refreshLogs() async {
    final rawLogs = await _ch.getLogs();
    _logs = rawLogs
        .map((m) => QueryLog.fromMap(m))
        .toList()
        .reversed
        .toList();
    notifyListeners();
  }

  Future<void> clearLogs() async {
    await _ch.clearLogs();
    _logs = [];
    notifyListeners();
  }

  // ─── DoH URL ──────────────────────────────────────────────────────────────

  Future<void> saveDoHUrl(String url) async {
    _dohUrl = url;
    await _ch.setDoHUrl(url);
    _stats = _stats.copyWith(activeServer: url);
    notifyListeners();
  }

  Future<void> saveFallbackDoHUrl(String url) async {
    _fallbackDoHUrl = url;
    await _ch.setFallbackDoHUrl(url);
    notifyListeners();
  }

  // ─── Boot setting ─────────────────────────────────────────────────────────

  Future<void> setStartOnBoot(bool val) async {
    _startOnBoot = val;
    await _ch.setStartOnBoot(val);
    notifyListeners();
  }

  // ─── Device Identity ──────────────────────────────────────────────────────

  Future<void> setDeviceName(String name) async {
    if (name.trim().isEmpty) return;
    _deviceName = name.trim();
    await _ch.setDeviceName(name.trim());
    // Refresh URL after name change
    _dohUrl = await _ch.getDoHUrl();
    notifyListeners();
  }

  Future<void> refreshVirtualIp() async {
    _virtualIp = await _ch.getVirtualIp();
    notifyListeners();
  }

  // ─── First Launch ─────────────────────────────────────────────────────────

  Future<bool> isFirstLaunchDone() => _ch.isFirstLaunchDone();

  Future<String> completeFirstLaunch({
    required String deviceName,
    required String baseUrl,
  }) async {
    final fullUrl = await _ch.completeFirstLaunch(
        deviceName: deviceName, baseUrl: baseUrl);
    _dohUrl = fullUrl;
    _deviceName = deviceName;
    _virtualIp = await _ch.getVirtualIp();
    notifyListeners();
    return fullUrl;
  }

  // ─── Battery Optimization ─────────────────────────────────────────────────

  Future<void> refreshBatteryOpt() async {
    _batteryOptIgnored = await _ch.isBatteryOptimizationIgnored();
    notifyListeners();
  }

  Future<void> requestBatteryOptimization() async {
    await _ch.requestBatteryOptimization();
    await Future.delayed(const Duration(seconds: 1));
    await refreshBatteryOpt();
  }

  // ─── Per-App Filtering ────────────────────────────────────────────────────

  Future<void> loadInstalledApps() async {
    if (_appsLoaded) return;
    final raw = await _ch.getInstalledApps();
    _installedApps = raw.map((m) => AppInfo.fromMap(m)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _appsLoaded = true;
    notifyListeners();
  }

  Future<void> setDisallowedApps(List<String> packages) async {
    _disallowedApps = packages;
    await _ch.setDisallowedApps(packages);
    notifyListeners();
  }

  void toggleDisallowedApp(String pkg) {
    final updated = List<String>.from(_disallowedApps);
    if (updated.contains(pkg)) {
      updated.remove(pkg);
    } else {
      updated.add(pkg);
    }
    setDisallowedApps(updated);
  }

  // ─── Connection test ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> testConnection(String url) =>
      _ch.testConnection(url);

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
