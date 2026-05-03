import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vpn_models.dart';
import '../services/vpn_channel_service.dart';

class VpnProvider extends ChangeNotifier {
  final VpnChannelService _channelService = VpnChannelService();

  VpnStatus _status = VpnStatus.disconnected;
  VpnStats _stats = const VpnStats();
  List<QueryLog> _logs = [];
  String _dohUrl = 'https://dns.sacloudserver.top/dns-query';
  bool _startOnBoot = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  Timer? _statsTimer;
  StreamSubscription? _statusSub;

  VpnStatus get status => _status;
  VpnStats get stats => _stats;
  List<QueryLog> get logs => List.unmodifiable(_logs);
  String get dohUrl => _dohUrl;
  bool get startOnBoot => _startOnBoot;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == VpnStatus.connected;

  VpnProvider() {
    _init();
  }

  Future<void> _init() async {
    _dohUrl = await _channelService.getDoHUrl();
    _startOnBoot = await _channelService.getStartOnBoot();
    final running = await _channelService.isVpnRunning();
    _status = running ? VpnStatus.connected : VpnStatus.disconnected;
    _stats = _stats.copyWith(
      status: _status,
      activeServer: _dohUrl,
    );
    _isInitialized = true;
    notifyListeners();

    if (running) {
      _startPolling();
    }

    // Listen for native status events
    _statusSub = _channelService.statusStream.listen(
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
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshStats();
    });
  }

  void _stopPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _refreshStats() async {
    final map = await _channelService.getStats();
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

    final success = await _channelService.startVpn();
    _isLoading = false;

    if (success) {
      _status = VpnStatus.connected;
      _stats = _stats.copyWith(status: VpnStatus.connected, activeServer: _dohUrl);
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
    await _channelService.stopVpn();
    _stopPolling();
    _isLoading = false;
    _status = VpnStatus.disconnected;
    _stats = _stats.copyWith(
      status: VpnStatus.disconnected,
      uptime: Duration.zero,
    );
    notifyListeners();
  }

  Future<void> refreshLogs() async {
    final rawLogs = await _channelService.getLogs();
    _logs = rawLogs
        .map((m) => QueryLog.fromMap(m))
        .toList()
        .reversed
        .toList();
    notifyListeners();
  }

  Future<void> clearLogs() async {
    await _channelService.clearLogs();
    _logs = [];
    notifyListeners();
  }

  Future<void> saveDoHUrl(String url) async {
    _dohUrl = url;
    await _channelService.setDoHUrl(url);
    _stats = _stats.copyWith(activeServer: url);
    notifyListeners();
  }

  Future<void> setStartOnBoot(bool val) async {
    _startOnBoot = val;
    await _channelService.setStartOnBoot(val);
    notifyListeners();
  }

  Future<Map<String, dynamic>> testConnection(String url) async {
    return _channelService.testConnection(url);
  }

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
