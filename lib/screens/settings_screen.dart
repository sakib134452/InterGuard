import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/vpn_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlCtrl = TextEditingController();
  bool _testLoading = false;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vpn = context.read<VpnProvider>();
      _urlCtrl.text = vpn.dohUrl;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('https://')) {
      _showSnack('URL must start with https://', isError: true);
      return;
    }
    await context.read<VpnProvider>().saveDoHUrl(url);
    _showSnack('Server URL saved!');
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnack('Enter a server URL first', isError: true);
      return;
    }
    setState(() {
      _testLoading = true;
      _testResult = null;
    });
    final result = await context.read<VpnProvider>().testConnection(url);
    setState(() {
      _testLoading = false;
      _testResult = result;
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontSize: 13)),
        backgroundColor:
            isError ? AppColors.red.withOpacity(0.85) : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _openVpnSettings() {
    const MethodChannel channel = MethodChannel('com.interguard.app/vpn');
    channel.invokeMethod('openVpnSettings');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // ─── DoH Server ───────────────────────────────────────────────
              _SectionHeader(label: 'DNS SERVER'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DoH Server URL',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _urlCtrl,
                      style: GoogleFonts.jetBrainsMono(
                          color: AppColors.textPrimary, fontSize: 13),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'https://dns.example.com/dns-query',
                        prefixIcon: const Icon(Icons.dns_rounded,
                            color: AppColors.cyan, size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _OutlineBtn(
                            label: 'Save',
                            icon: Icons.save_rounded,
                            onTap: _saveUrl,
                            accent: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OutlineBtn(
                            label: _testLoading ? 'Testing...' : 'Test',
                            icon: Icons.network_check_rounded,
                            onTap: _testLoading ? null : _testConnection,
                            accent: AppColors.green,
                          ),
                        ),
                      ],
                    ),
                    // Test result
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      _TestResultBanner(result: _testResult!),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── Protection ───────────────────────────────────────────────
              _SectionHeader(label: 'PROTECTION'),
              _Card(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.restart_alt_rounded,
                      label: 'Start on Boot',
                      subtitle: 'Automatically protect device after reboot',
                      value: vpn.startOnBoot,
                      onChanged: vpn.setStartOnBoot,
                    ),
                    const Divider(height: 1),
                    _TapRow(
                      icon: Icons.lock_outline_rounded,
                      label: 'Always-On VPN',
                      subtitle: 'Configure in Android VPN settings',
                      onTap: _openVpnSettings,
                      trailing: const Icon(Icons.open_in_new_rounded,
                          size: 16, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── About ────────────────────────────────────────────────────
              _SectionHeader(label: 'ABOUT'),
              _Card(
                child: Column(
                  children: [
                    // Logo + branding
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 72,
                              height: 72,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'InterGuard',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Block your ads by DNS',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.cyanFaint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.cyanDim.withOpacity(0.3)),
                            ),
                            child: Text(
                              'Version 1.0.0',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  color: AppColors.cyan,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _InfoRow(
                        label: 'Package',
                        value: 'com.interguard.app'),
                    const Divider(height: 1),
                    _InfoRow(label: 'Protocol', value: 'DNS-over-HTTPS (RFC 8484)'),
                    const Divider(height: 1),
                    _InfoRow(label: 'Default Server', value: 'sacloudserver.top'),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ─── Helper Widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.cyan,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      child: child,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppColors.cyan, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _TapRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: AppColors.cyan, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textMuted)),
          const Spacer(),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;

  const _OutlineBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: accent),
      label: Text(label,
          style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: accent.withOpacity(0.4), width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: accent.withOpacity(0.06),
      ),
    );
  }
}

class _TestResultBanner extends StatelessWidget {
  final Map<String, dynamic> result;
  const _TestResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final success = result['success'] == true;
    final msg = result['message'] as String? ?? '';
    final latency = result['latencyMs'] as int?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: success
            ? AppColors.green.withOpacity(0.1)
            : AppColors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: success
              ? AppColors.green.withOpacity(0.3)
              : AppColors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: success ? AppColors.green : AppColors.red,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  success ? 'Connection successful' : 'Connection failed',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: success ? AppColors.green : AppColors.red,
                  ),
                ),
                if (msg.isNotEmpty)
                  Text(msg,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                if (latency != null && success)
                  Text('Latency: ${latency}ms',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
