import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class UpdateService {
  static const String _configUrl = 'https://raw.githubusercontent.com/sakib134452/Blood-Donor-App-version-system/main/update_config.json';

  static Future<bool> checkForUpdates(BuildContext context, VoidCallback onNoUpdate) async {
    try {
      final response = await http.get(Uri.parse(_configUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['latest_version'] as String;
        final minRequiredVersion = data['min_required_version'] as String;
        final updateUrl = data['update_url'] as String;
        final releaseNotes = data['release_notes'] as String;
        final forceUpdateMessage = data['force_update_message'] as String;

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        final isMajorMinor = _compareVersions(currentVersion, minRequiredVersion) < 0;
        final isPatch = _compareVersions(currentVersion, latestVersion) < 0 && !isMajorMinor;

        if (isMajorMinor) {
          // Force Update
          _showUpdateDialog(
            context,
            title: 'Update Required',
            message: forceUpdateMessage,
            notes: releaseNotes,
            url: updateUrl,
            isForce: true,
          );
          return true; // Stop splash navigation
        } else if (isPatch) {
          // Flexible Update
          _showUpdateDialog(
            context,
            title: 'Update Available',
            message: 'A new version is available. Would you like to update now?',
            notes: releaseNotes,
            url: updateUrl,
            isForce: false,
            onLater: onNoUpdate,
          );
          return true; // Stop splash navigation, let dialog handle it
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    
    // No update or error
    onNoUpdate();
    return false;
  }

  static int _compareVersions(String v1, String v2) {
    List<int> p1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> p2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    for (int i = 0; i < 3; i++) {
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
        return WillPopScope(
          onWillPop: () async => !isForce,
          child: Dialog(
            backgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isForce ? AppColors.red.withOpacity(0.15) : AppColors.cyan.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.system_update_rounded,
                          color: isForce ? AppColors.red : AppColors.cyan,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Release Notes:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cyan,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            notes,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!isForce) ...[
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            if (onLater != null) onLater();
                          },
                          child: Text(
                            'Later',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      ElevatedButton(
                        onPressed: () => _startDownload(context, url),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          'Update Now',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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

  static void _startDownload(BuildContext context, String url) {
    // Show download progress overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                const CircularProgressIndicator(color: AppColors.cyan),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Downloading update...',
                    style: GoogleFonts.inter(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      OtaUpdate().execute(
        url,
        destinationFilename: 'interguard_update.apk',
      ).listen(
        (OtaEvent event) {
          if (event.status == OtaStatus.DOWNLOADING) {
            // Can update progress here if needed
          } else if (event.status == OtaStatus.INSTALLING) {
            // OS handles the prompt
          } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR ||
              event.status == OtaStatus.INTERNAL_ERROR ||
              event.status == OtaStatus.DOWNLOAD_ERROR) {
            Navigator.pop(context); // Close progress
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update: ${event.status}')),
            );
          }
        },
      );
    } catch (e) {
      Navigator.pop(context); // Close progress
      debugPrint('Failed to make OTA update. Details: $e');
    }
  }
}
