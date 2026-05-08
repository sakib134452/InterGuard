import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class UpdateService {
  static const String _configUrl = 'https://raw.githubusercontent.com/sakib134452/Blood-Donor-App-version-system/main/update_config.json';

  static Future<bool> checkForUpdates(BuildContext context, VoidCallback onNoUpdate) async {
    try {
      final response = await http.get(Uri.parse(_configUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['latest_version'] as String;
        final minRequiredVersion = data['min_required_version'] as String;
        final updateUrl = data['update_url'] as String;
        final releaseNotes = data['release_notes'] as String;
        final forceUpdateMessage = data['force_update_message'] as String;

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version.trim();
        final latest = latestVersion.trim();
        final minReq = minRequiredVersion.trim();

        debugPrint('Comparing versions: Current: $currentVersion, Latest: $latest');

        final isMajorMinor = _compareVersions(currentVersion, minReq) < 0;
        final isPatch = _compareVersions(currentVersion, latest) < 0 && !isMajorMinor;

        if (isMajorMinor) {
          _showUpdateDialog(
            context,
            title: 'Update Required',
            message: forceUpdateMessage,
            notes: releaseNotes,
            url: updateUrl,
            isForce: true,
          );
          return true;
        } else if (isPatch) {
          _showUpdateDialog(
            context,
            title: 'Update Available',
            message: 'A new version of InterGuard is available. Would you like to update now?',
            notes: releaseNotes,
            url: updateUrl,
            isForce: false,
            onLater: onNoUpdate,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    
    onNoUpdate();
    return false;
  }

  /// Background update check for Workmanager
  static Future<void> checkUpdateBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final response = await http.get(Uri.parse(_configUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['latest_version'] as String;
        
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        if (_compareVersions(currentVersion, latestVersion) < 0) {
          // Notify once per day (24 hours)
          final lastNotifTime = prefs.getInt('last_update_notif_time_daily') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          if (now - lastNotifTime > 86400000) { // 86400000 ms = 24 hours
            _showLocalNotification(
              'InterGuard Update Available',
              'Version $latestVersion is now available. Tap to update for better protection.',
            );
            await prefs.setInt('last_update_notif_time_daily', now);
          }
        }
      }
    } catch (e) {
      debugPrint('Background update check failed: $e');
    }
  }

  static void _showLocalNotification(String title, String body, {int? progress, bool showProgress = false}) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    AndroidNotificationDetails? androidPlatformChannelSpecifics;
    
    if (showProgress) {
      androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'download_channel',
        'Downloads',
        channelDescription: 'App update download progress',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: progress ?? 0,
        ongoing: true,
        onlyAlertOnce: true,
      );
    } else {
      androidPlatformChannelSpecifics = const AndroidNotificationDetails(
        'update_channel',
        'App Updates',
        channelDescription: 'Notifications for app updates',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );
    }
    
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    
    await flutterLocalNotificationsPlugin.show(
      showProgress ? 888 : 999,
      title,
      body,
      platformChannelSpecifics,
      payload: 'update',
    );
  }

  static void _cancelNotification(int id) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  static int _compareVersions(String v1, String v2) {
    List<int> p1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> p2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    for (int i = 0; i < 4; i++) { // Support up to 4 parts like 1.2.3.4
      int val1 = i < p1.length ? p1[i] : 0;
      int val2 = i < p2.length ? p2[i] : 0;
      if (val1 < val2) return -1;
      if (val1 > val2) return 1;
    }
    return 0;
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String notes,
    required String url,
    required bool isForce,
    VoidCallback? onLater,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) {
        return PopScope(
          canPop: !isForce,
          child: Dialog(
            backgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isForce ? AppColors.red.withOpacity(0.1) : AppColors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: isForce ? AppColors.red : AppColors.cyan,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.new_releases_outlined, size: 14, color: AppColors.cyan),
                              const SizedBox(width: 8),
                              Text(
                                'WHAT\'S NEW',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.cyan,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            notes,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _startDownload(context, url);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            'Update Now',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _launchUrl('https://github.com/sakib134452/InterGuard/releases/latest/download/InterGuard.apk'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: AppColors.cardBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'Install from Web',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (!isForce) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            if (onLater != null) onLater();
                          },
                          child: Text(
                            'Maybe Later',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch URL: $url');
    }
  }

  static void _startDownload(BuildContext context, String url) {
    if (!Platform.isAndroid) {
      _launchUrl(url); // Redirect to browser on non-Android (Windows)
      return;
    }
    
    // Use the provided URL or fallback to the direct APK link
    final String downloadUrl = url.contains('.apk') ? url : 'https://github.com/sakib134452/InterGuard/releases/latest/download/InterGuard.apk';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(url: downloadUrl),
    );
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final String url;
  const _UpdateProgressDialog({required this.url});

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double _progress = 0;
  String _status = 'Connecting...';
  bool _isSuccess = false;
  bool _isDownloading = false;
  StreamSubscription<OtaEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _initDownload();
  }

  void _initDownload() {
    if (_isDownloading) return;
    _isDownloading = true;

    if (Platform.isWindows) {
      setState(() {
        _status = 'Windows update not directly supported yet. Please use "Install from Website".';
        _isDownloading = false;
      });
      return;
    }

    try {
      _subscription = OtaUpdate().execute(
        widget.url,
        destinationFilename: 'interguard_update.apk',
      ).listen(
        (OtaEvent event) {
          if (!mounted) return;
          
          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                _progress = double.tryParse(event.value ?? '0') ?? 0;
                _status = 'Downloading update: ${_progress.toInt()}%';
                UpdateService._showLocalNotification(
                  'Downloading InterGuard',
                  'Progress: ${_progress.toInt()}%',
                  progress: _progress.toInt(),
                  showProgress: true,
                );
                break;
              case OtaStatus.INSTALLING:
                _progress = 100;
                _status = 'Ready to Install';
                _isSuccess = true;
                UpdateService._cancelNotification(888);
                UpdateService._showLocalNotification(
                  'Download Complete',
                  'Tap to install the new version of InterGuard.'
                );
                
                // Do NOT exit the app here. Let the Android installer intent pop up.
                // The system will handle the replacement of the app.
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _status = 'An update is already in progress.';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _status = 'Storage permission required for update.';
                break;
              default:
                if (event.status.toString().contains('ERROR')) {
                  _status = 'Update failed: ${event.status}';
                  _isDownloading = false;
                }
                break;
            }
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _status = 'Error: $e';
            _isDownloading = false;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Failed to start download.';
          _isDownloading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    UpdateService._cancelNotification(888);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isSuccess,
      child: Dialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isSuccess ? Colors.green.withOpacity(0.1) : AppColors.cyan.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isSuccess ? Icons.check_circle_rounded : Icons.file_download_outlined,
                  color: _isSuccess ? Colors.greenAccent : AppColors.cyan,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isSuccess ? 'Download Complete!' : 'Downloading Update',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  backgroundColor: AppColors.background,
                  color: _isSuccess ? Colors.greenAccent : AppColors.cyan,
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_isSuccess) ...[
                const SizedBox(height: 24),
                Text(
                  'Installation starting. The app will close to complete the process.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyan)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

