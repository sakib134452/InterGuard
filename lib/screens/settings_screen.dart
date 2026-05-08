import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/vpn_provider.dart';
import '../models/vpn_models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _fallbackUrlCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  bool _testLoading = false;
  Map<String, dynamic>? _testResult;

  bool _initialized = false;

  final List<Map<String, String>> _suggestions = [
    {
      'name': 'InterGuard Default',
      'url': 'https://dns.sacloudserver.top/dns-query'
    },
    {'name': 'Google', 'url': 'https://dns.google/dns-query'},
    {'name': 'Cloudflare', 'url': 'https://cloudflare-dns.com/dns-query'},
    {'name': 'Quad9', 'url': 'https://dns.quad9.net/dns-query'},
    {'name': 'AdGuard', 'url': 'https://dns.adguard-dns.com/dns-query'},
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _fallbackUrlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final vpn = context.read<VpnProvider>();
    final url = _urlCtrl.text.trim();
    final fallbackUrl = _fallbackUrlCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    bool isInterGuardDefault = url.startsWith('https://dns.sacloudserver.top/dns-query');

    if (isInterGuardDefault) {
      final parts = url.split('dns.sacloudserver.top/dns-query');
      if (parts.length > 1 && parts[1].isNotEmpty) {
        final nameParts = parts[1].split('/').where((s) => s.isNotEmpty).toList();
        if (nameParts.length > 1) {
          _showSnack('Error: There will be no more than one name after the URL.', isError: true);
          return;
        }
      }
    }

    if (url.isEmpty) {
      _showSnack('Please enter a DoH URL', isError: true);
      return;
    }
    if (isInterGuardDefault && name.isEmpty) {
      _showSnack('Device Name is mandatory for InterGuard Default', isError: true);
      return;
    }
    if (!url.startsWith('https://')) {
      _showSnack('Invalid format: URL must start with https://', isError: true);
      return;
    }
    if (fallbackUrl.isNotEmpty && !fallbackUrl.startsWith('https://')) {
      _showSnack('Invalid format: Fallback URL must start with https://', isError: true);
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty || !uri.host.contains('.')) {
        _showSnack('Invalid format: Missing valid domain', isError: true);
        return;
      }
    } catch (e) {
      _showSnack('Invalid URL format', isError: true);
      return;
    }

    // Strip out the existing name if it's there
    String baseUrl = url;
    if (isInterGuardDefault) {
       final baseMatch = RegExp(r'^(https://dns\.sacloudserver\.top/dns-query)').firstMatch(url);
       if (baseMatch != null) {
           baseUrl = baseMatch.group(1)!;
       }
    } else {
       if (name.isNotEmpty && url.endsWith('/$name')) {
         baseUrl = url.substring(0, url.length - name.length - 1);
       } else {
         final oldName = vpn.deviceName;
         if (oldName.isNotEmpty && url.endsWith('/$oldName')) {
           baseUrl = url.substring(0, url.length - oldName.length - 1);
         }
       }
    }

    // Strip trailing slash
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    String fullUrl = baseUrl;
    if (isInterGuardDefault && name.isNotEmpty) {
      fullUrl = '$baseUrl/$name';
    }

    await vpn.setDeviceName(name);
    await vpn.saveDoHUrl(fullUrl);
    if (fallbackUrl.isNotEmpty) {
      await vpn.saveFallbackDoHUrl(fallbackUrl);
    }

    setState(() {
      _urlCtrl.text = fullUrl;
    });

    _showSnack('Settings saved and applied!');
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnack('Enter a server URL first', isError: true);
      return;
    }
    
    bool isInterGuardDefault = url.startsWith('https://dns.sacloudserver.top/dns-query');
    if (isInterGuardDefault) {
      final parts = url.split('dns.sacloudserver.top/dns-query');
      if (parts.length > 1 && parts[1].isNotEmpty) {
        final nameParts = parts[1].split('/').where((s) => s.isNotEmpty).toList();
        if (nameParts.length > 1) {
          _showSnack('Error: There will be no more than one name after the URL.', isError: true);
          return;
        }
      }
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

  void _showPerAppDialog() {
    final vpn = context.read<VpnProvider>();
    vpn.loadInstalledApps();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _PerAppSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        if (!_initialized && vpn.isInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _urlCtrl.text = vpn.dohUrl;
                _fallbackUrlCtrl.text = vpn.fallbackDoHUrl;
                _nameCtrl.text = vpn.deviceName;
                _initialized = true;
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // ─── IDENTITY & SERVER ──────────────────────────────────────────
              _SectionHeader(label: 'IDENTITY & SERVER'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device Name
                    Text('Device Name',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      style: GoogleFonts.inter(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. MyPhone',
                        prefixIcon: const Icon(Icons.badge_rounded,
                            color: AppColors.cyan, size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      onChanged: (val) {
                          // Real-time update preview
                          final name = val.trim();
                          String url = _urlCtrl.text;
                          bool isInterGuardDefault = url.startsWith('https://dns.sacloudserver.top/dns-query');
                          if (isInterGuardDefault) {
                            final baseMatch = RegExp(r'^(https://dns\.sacloudserver\.top/dns-query)').firstMatch(url);
                            if (baseMatch != null) {
                              String base = baseMatch.group(1)!;
                              if (name.isNotEmpty) {
                                _urlCtrl.text = '$base/$name';
                              } else {
                                _urlCtrl.text = base;
                              }
                            }
                          }
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your name is appended to the server URL to identify your device.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),

                    // DoH URL
                    Text('Primary DoH Server URL',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 16),

                    // Fallback DoH URL
                    Text('Fallback Server URL',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _fallbackUrlCtrl,
                      style: GoogleFonts.jetBrainsMono(
                          color: AppColors.textPrimary, fontSize: 13),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'https://cloudflare-dns.com/dns-query',
                        prefixIcon: const Icon(Icons.security_rounded,
                            color: AppColors.cyan, size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: _OutlineBtn(
                            label: 'Save Settings',
                            icon: Icons.save_rounded,
                            onTap: _saveSettings,
                            accent: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OutlineBtn(
                            label: _testLoading ? 'Testing...' : 'Test URL',
                            icon: Icons.network_check_rounded,
                            onTap: _testLoading ? null : _testConnection,
                            accent: AppColors.green,
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      _TestResultBanner(result: _testResult!),
                    ],
                    const SizedBox(height: 16),

                    // Suggestions
                    Text('Suggestions:',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _suggestions.map((s) {
                        return InkWell(
                          onTap: () {
                            setState(() {
                              String base = s['url']!;
                              bool isInterGuardDefault = base.startsWith('https://dns.sacloudserver.top/dns-query');
                              String name = _nameCtrl.text.trim();
                              if (name.isEmpty) name = vpn.deviceName;
                              if (isInterGuardDefault && name.isNotEmpty) {
                                _urlCtrl.text = '$base/$name';
                              } else {
                                _urlCtrl.text = base;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: s['name'] == 'InterGuard Default'
                                  ? AppColors.cyan.withOpacity(0.15)
                                  : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: s['name'] == 'InterGuard Default'
                                      ? AppColors.cyan.withOpacity(0.5)
                                      : AppColors.cardBorder,
                                  width: 1),
                            ),
                            child: Text(
                              s['name']!,
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: s['name'] == 'InterGuard Default'
                                      ? AppColors.cyan
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── PROTECTION ───────────────────────────────────────────────
              _SectionHeader(label: 'PROTECTION & OPTIMIZATION'),
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
                    if (!Platform.isWindows) ...[
                      const Divider(height: 1),
                      _TapRow(
                        icon: Icons.apps_rounded,
                        label: 'Per-App Protection',
                        subtitle: '${vpn.disallowedApps.length} apps bypassing VPN',
                        onTap: _showPerAppDialog,
                        trailing: const Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.textMuted),
                      ),
                      const Divider(height: 1),
                      _TapRow(
                        icon: Icons.battery_charging_full_rounded,
                        label: 'Battery Optimization',
                        subtitle: vpn.batteryOptIgnored
                            ? 'Unrestricted (Recommended)'
                            : 'Optimized (May stop VPN)',
                        onTap: () {
                          if (!vpn.batteryOptIgnored) {
                            vpn.requestBatteryOptimization();
                          } else {
                            _showSnack('Battery optimization is already unrestricted.');
                          }
                        },
                        trailing: Icon(
                          vpn.batteryOptIgnored
                              ? Icons.check_circle_rounded
                              : Icons.warning_rounded,
                          size: 18,
                          color: vpn.batteryOptIgnored
                              ? AppColors.green
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── ABOUT ────────────────────────────────────────────────────
              _SectionHeader(label: 'ABOUT & SYSTEM'),
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
                              'Version 1.2.6',
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
                    _InfoRow(label: 'Public IP (Original)', value: vpn.publicIp),
                    const Divider(height: 1),
                    _InfoRow(label: 'Virtual Client IP', value: vpn.virtualIp.isNotEmpty ? vpn.virtualIp : '---'),
                    const Divider(height: 1),
                    _InfoRow(label: 'VPN Tunnel IP', value: vpn.isConnected ? '10.111.222.1' : '---'),
                    const Divider(height: 1),
                    _InfoRow(label: 'Status', value: vpn.isConnected ? 'Active' : 'Inactive'),
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

// ─── Per-App Sheet ────────────────────────────────────────────────────────────

class _PerAppSheet extends StatefulWidget {
  const _PerAppSheet();

  @override
  State<_PerAppSheet> createState() => _PerAppSheetState();
}

class _PerAppSheetState extends State<_PerAppSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Consumer<VpnProvider>(
        builder: (context, vpn, _) {
          List<AppInfo> apps = vpn.installedApps;
          if (_search.isNotEmpty) {
            final s = _search.toLowerCase();
            apps = apps.where((a) => a.name.toLowerCase().contains(s)).toList();
          }

          return Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Per-App Protection',
                        style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Done', style: GoogleFonts.inter(color: AppColors.cyan)),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Apps toggled OFF will bypass the VPN entirely and use the standard unencrypted network.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: TextField(
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search apps...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: !vpn.appsLoaded
                    ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                    : ListView.builder(
                        itemCount: apps.length,
                        itemBuilder: (context, index) {
                          final app = apps[index];
                          final isDisallowed = vpn.disallowedApps.contains(app.packageName);
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            title: Text(
                              app.name,
                              style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14),
                            ),
                            subtitle: Text(
                              app.isSystem ? 'System App' : 'User App',
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted, fontSize: 11),
                            ),
                            trailing: Switch(
                              value: !isDisallowed, // ON = Protected (default), OFF = Disallowed
                              activeColor: AppColors.cyan,
                              onChanged: (val) {
                                vpn.toggleDisallowedApp(app.packageName);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
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
            activeColor: AppColors.cyan,
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
