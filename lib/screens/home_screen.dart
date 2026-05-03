import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/vpn_provider.dart';
import '../models/vpn_models.dart';
import '../widgets/stat_card.dart';
import '../widgets/power_button.dart';
import '../services/navigation_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        final isConnected = vpn.status == VpnStatus.connected;
        final isConnecting = vpn.status == VpnStatus.connecting;
        final stats = vpn.stats;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.5),
                radius: 1.0,
                colors: isConnected
                    ? [
                        AppColors.green.withOpacity(0.07),
                        AppColors.background,
                      ]
                    : [
                        AppColors.surface,
                        AppColors.background,
                      ],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // Logo + App name
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'InterGuard',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Power button with glow ring
                    PowerButton(
                      status: vpn.status,
                      onTap: vpn.isLoading ? null : vpn.toggleVpn,
                      pulseCtrl: _pulseCtrl,
                    ),

                    const SizedBox(height: 28),

                    // Status text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: isConnecting
                          ? _buildStatusRow(
                              Icons.sync_rounded,
                              'Connecting...',
                              AppColors.cyan,
                              key: const ValueKey('connecting'),
                            )
                          : isConnected
                              ? _buildStatusRow(
                                  Icons.verified_rounded,
                                  'Protected',
                                  AppColors.green,
                                  key: const ValueKey('protected'),
                                  glow: true,
                                  pulseCtrl: _pulseCtrl,
                                )
                              : _buildStatusRow(
                                  Icons.shield_outlined,
                                  'Not Protected',
                                  AppColors.textMuted,
                                  key: const ValueKey('unprotected'),
                                ),
                    ),

                    const SizedBox(height: 12),

                    // Active server URL
                    AnimatedOpacity(
                      opacity: isConnected ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 400),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.cardBorder, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_rounded,
                                size: 14, color: AppColors.cyan),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                vpn.dohUrl.isEmpty
                                    ? 'No server configured'
                                    : _shortenUrl(vpn.dohUrl),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Error message
                    if (vpn.errorMessage != null)
                      _ErrorBanner(
                        message: vpn.errorMessage!,
                        onDismiss: vpn.clearError,
                      ),

                    if (vpn.errorMessage != null) const SizedBox(height: 16),

                    // Stats grid
                    AnimatedOpacity(
                      opacity: isConnected ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live Statistics',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  icon: Icons.query_stats_rounded,
                                  label: 'Total Queries',
                                  value: stats.totalQueries.toString(),
                                  accent: AppColors.cyan,
                                  onTap: () => context.read<NavigationProvider>().setTab(1, filter: LogFilterType.all),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatCard(
                                  icon: Icons.block_rounded,
                                  label: 'Blocked',
                                  value: stats.blockedQueries.toString(),
                                  accent: AppColors.red,
                                  onTap: () => context.read<NavigationProvider>().setTab(1, filter: LogFilterType.blocked),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatCard(
                            icon: Icons.timer_outlined,
                            label: 'Uptime',
                            value: isConnected
                                ? _formatUptime(stats.uptime)
                                : '—',
                            accent: AppColors.green,
                            wide: true,
                            onTap: () => context.read<NavigationProvider>().setTab(1, filter: LogFilterType.allowed),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(
    IconData icon,
    String text,
    Color color, {
    Key? key,
    bool glow = false,
    AnimationController? pulseCtrl,
  }) {
    Widget iconWidget = Icon(icon, color: color, size: 20);
    if (glow && pulseCtrl != null) {
      iconWidget = AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3 + 0.2 * pulseCtrl.value),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );
    }
    return Row(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host + (uri.path.isNotEmpty ? uri.path : '');
    } catch (_) {
      return url;
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: GoogleFonts.inter(
                    color: AppColors.red, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, color: AppColors.red, size: 18),
          ),
        ],
      ),
    );
  }
}
