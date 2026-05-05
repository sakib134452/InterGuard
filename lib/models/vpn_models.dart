import 'package:flutter/services.dart';

enum VpnStatus { connected, disconnected, connecting }

class QueryLog {
  final String domain;
  final DateTime timestamp;
  final bool blocked;
  final String type;

  QueryLog({
    required this.domain,
    required this.timestamp,
    required this.blocked,
    this.type = 'A',
  });

  factory QueryLog.fromMap(Map<dynamic, dynamic> map) {
    return QueryLog(
      domain: map['domain'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as int?) ?? 0),
      blocked: (map['blocked'] as bool?) ?? false,
      type: map['type'] ?? 'A',
    );
  }
}

class VpnStats {
  final int totalQueries;
  final int blockedQueries;
  final Duration uptime;
  final VpnStatus status;
  final String activeServer;

  const VpnStats({
    this.totalQueries = 0,
    this.blockedQueries = 0,
    this.uptime = Duration.zero,
    this.status = VpnStatus.disconnected,
    this.activeServer = '',
  });

  VpnStats copyWith({
    int? totalQueries,
    int? blockedQueries,
    Duration? uptime,
    VpnStatus? status,
    String? activeServer,
  }) {
    return VpnStats(
      totalQueries: totalQueries ?? this.totalQueries,
      blockedQueries: blockedQueries ?? this.blockedQueries,
      uptime: uptime ?? this.uptime,
      status: status ?? this.status,
      activeServer: activeServer ?? this.activeServer,
    );
  }
}

/// Represents an installed app for per-app VPN filtering.
class AppInfo {
  final String packageName;
  final String name;
  final bool isSystem;

  const AppInfo({
    required this.packageName,
    required this.name,
    required this.isSystem,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['package'] as String? ?? '',
      name: map['name'] as String? ?? '',
      isSystem: map['isSystem'] as bool? ?? false,
    );
  }
}
