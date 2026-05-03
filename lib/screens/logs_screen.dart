import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/vpn_provider.dart';
import '../services/navigation_provider.dart';
import '../models/vpn_models.dart';
import 'package:intl/intl.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}


class _LogsScreenState extends State<LogsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(() {
      setState(() => _filter = _searchCtrl.text.trim().toLowerCase());
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await context.read<VpnProvider>().refreshLogs();
    setState(() => _loading = false);
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear Logs',
            style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('All query logs will be permanently deleted.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear',
                style:
                    GoogleFonts.inter(color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<VpnProvider>().clearLogs();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        final nav = context.watch<NavigationProvider>();
        final statusFilter = nav.logFilter;

        final allLogs = vpn.logs;
        var filtered = allLogs;
        
        if (statusFilter == LogFilterType.allowed) {
          filtered = filtered.where((l) => !l.blocked).toList();
        } else if (statusFilter == LogFilterType.blocked) {
          filtered = filtered.where((l) => l.blocked).toList();
        }

        if (_filter.isNotEmpty) {
          filtered = filtered
              .where((l) => l.domain.toLowerCase().contains(_filter))
              .toList();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Query Logs'),
            actions: [
              if (allLogs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.red,
                  onPressed: _clearLogs,
                  tooltip: 'Clear Logs',
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search domains...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 20),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: AppColors.textMuted, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),

              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: statusFilter == LogFilterType.all,
                      onTap: () => nav.setTab(1, filter: LogFilterType.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Allowed',
                      selected: statusFilter == LogFilterType.allowed,
                      onTap: () => nav.setTab(1, filter: LogFilterType.allowed),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Blocked',
                      selected: statusFilter == LogFilterType.blocked,
                      onTap: () => nav.setTab(1, filter: LogFilterType.blocked),
                    ),
                  ],
                ),
              ),

              // Count banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} entr${filtered.length == 1 ? 'y' : 'ies'}',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppColors.cyan),
                          strokeWidth: 2,
                        ),
                      )
                    : filtered.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: AppColors.cyan,
                            backgroundColor: AppColors.surface,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) =>
                                  _LogTile(log: filtered[i]),
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined,
              size: 64, color: AppColors.textMuted.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            _filter.isNotEmpty ? 'No matching logs' : 'No queries logged yet',
            style: GoogleFonts.inter(
                color: AppColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            _filter.isNotEmpty
                ? 'Try a different search term'
                : 'Start the VPN to see DNS queries',
            style: GoogleFonts.inter(
                color: AppColors.textMuted.withOpacity(0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final QueryLog log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('HH:mm:ss').format(log.timestamp);
    final dateStr = DateFormat('MMM d').format(log.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: log.blocked
              ? AppColors.red.withOpacity(0.25)
              : AppColors.cardBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: log.blocked ? AppColors.red : AppColors.green,
              boxShadow: [
                BoxShadow(
                  color: (log.blocked ? AppColors.red : AppColors.green)
                      .withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Domain
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.domain,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  log.type,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          // Time + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: log.blocked
                      ? AppColors.red.withOpacity(0.12)
                      : AppColors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.blocked ? 'Blocked' : 'Allowed',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: log.blocked ? AppColors.red : AppColors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.cyan : AppColors.cardBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.cyan : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
