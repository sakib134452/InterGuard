import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/vpn_models.dart';
import '../services/vpn_channel_service.dart';
import '../services/dns_proxy_service.dart';

class VpnProvider extends ChangeNotifier {
  final VpnChannelService _ch = VpnChannelService();
  late final DnsProxyService _windowsProxy;

  VpnStatus _status = VpnStatus.disconnected;
  VpnStats _stats = const VpnStats();
  List<QueryLog> _logs = [];
  String _dohUrl = 'https://dns.sacloudserver.top/dns-query';
  String _fallbackDoHUrl = 'https://dns.adguard-dns.com/dns-query';
  bool _startOnBoot = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  // Device identity
  String _deviceName = '';
  String _virtualIp = '';
  String _publicIp = 'Detecting...';

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
  String get publicIp => _publicIp;
  bool get batteryOptIgnored => _batteryOptIgnored;
  List<AppInfo> get installedApps => List.unmodifiable(_installedApps);
  List<String> get disallowedApps => List.unmodifiable(_disallowedApps);
  bool get appsLoaded => _appsLoaded;

  VpnProvider() {
    _windowsProxy = DnsProxyService(onQuery: (domain, blocked) {
      // Handle Windows logs manually
      _logs.insert(0, QueryLog(
        domain: domain,
        timestamp: DateTime.now(),
        blocked: blocked,
        type: 'A',
      ));
      if (_logs.length > 200) _logs.removeLast();
      
      _stats = _stats.copyWith(
        totalQueries: _stats.totalQueries + 1,
        blockedQueries: _stats.blockedQueries + (blocked ? 1 : 0),
      );
      notifyListeners();
    });
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
    
    // Fetch public IP for 'About' section
    _refreshPublicIp();

    final running = await _ch.isVpnRunning();
    _status = running ? VpnStatus.connected : VpnStatus.disconnected;
    _stats = _stats.copyWith(status: _status, activeServer: _dohUrl);
    _isInitialized = true;
    notifyListeners();

    if (running) {
      _startPolling();
    }

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
    if (Platform.isWindows) return; // Stats are updated via onQuery callback on Windows
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
    _checkMilestone(blocked);
    notifyListeners();
  }

  void _sendNotification(String title, String body) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'protection_status',
      'Protection Status',
      channelDescription: 'Notifications for protection status and milestones',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    // Darwin details for iOS/macOS
    const DarwinNotificationDetails darwinPlatformChannelSpecifics = DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformChannelSpecifics,
      macOS: darwinPlatformChannelSpecifics,
    );
    
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> _checkMilestone(int blockedCount) async {
    if (blockedCount < 1000) return;
    
    final prefs = await SharedPreferences.getInstance();
    final milestoneReached = prefs.getBool('milestone_1000_reached') ?? false;
    
    if (!milestoneReached) {
      _sendNotification(
        'Security Milestone Reached!',
        'Excellent work, $_deviceName! InterGuard has successfully blocked over 1,000 trackers and ads. Your privacy is now better protected!'
      );
      await prefs.setBool('milestone_1000_reached', true);
    }
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
    if (Platform.isWindows) {
      _status = VpnStatus.connecting;
      _isLoading = true;
      notifyListeners();
      
      final success = await _windowsProxy.start(_dohUrl);
      _isLoading = false;
      
      if (success) {
        _status = VpnStatus.connected;
        _stats = _stats.copyWith(status: VpnStatus.connected, activeServer: _dohUrl);
        _sendNotification('Protection Enabled', 'InterGuard is now protecting your DNS on Windows.');
      } else {
        _status = VpnStatus.disconnected;
        _errorMessage = 'Failed to start DNS protection. Please run as Administrator.';
      }
      notifyListeners();
      return;
    }

    if (!Platform.isAndroid) {
      _errorMessage = 'VPN protection is currently only supported on Android.';
      notifyListeners();
      return;
    }
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
      _sendNotification('Protection Enabled', 'InterGuard is now actively protecting your device.');
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

    if (Platform.isWindows) {
      await _windowsProxy.stop();
    } else {
      await _ch.stopVpn();
      _stopPolling();
    }

    _sendNotification('Protection Disabled', 'Your device is no longer protected by InterGuard.');
    _isLoading = false;
    _status = VpnStatus.disconnected;
    _stats = _stats.copyWith(
        status: VpnStatus.disconnected, uptime: Duration.zero);
    notifyListeners();
  }

  // ─── Logs ─────────────────────────────────────────────────────────────────

  Future<void> refreshLogs() async {
    if (Platform.isWindows) return; // Logs are handled manually on Windows
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
    _refreshPublicIp();
    notifyListeners();
  }

  Future<void> _refreshPublicIp() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _publicIp = response.body.trim();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to fetch public IP: $e');
      if (_publicIp == 'Detecting...') {
        _publicIp = 'Unavailable';
        notifyListeners();
      }
    }
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
