import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/vpn_provider.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';
import 'main_shell.dart';

import '../services/update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _sloganFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));

    _fadeAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
        CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)));
    _sloganFade = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn));

    _ctrl.forward();

    // Reduced delay to allow update check to take some time without being too slow
    Future.delayed(const Duration(milliseconds: 2000), _checkUpdateAndNavigate);
  }

  Future<void> _checkUpdateAndNavigate() async {
    if (!mounted) return;
    
    // Check for updates first
    final hasUpdatePopup = await UpdateService.checkForUpdates(context, () {
      if (mounted) _proceedToApp();
    });

    // If no popup was shown (e.g., error or no update), proceed
    if (!hasUpdatePopup) {
      _proceedToApp();
    }
  }

  Future<void> _proceedToApp() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;

    if (!mounted) return;
    
    // First launch setup logic
    final vpn = context.read<VpnProvider>();
    final isFirstLaunchDone = await vpn.isFirstLaunchDone();
    
    if (!isFirstLaunchDone) {
      await vpn.completeFirstLaunch(
        deviceName: '', 
        baseUrl: 'https://dns.sacloudserver.top/dns-query'
      );
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) =>
            onboardingSeen ? const MainShell() : const OnboardingScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF0D2545), AppColors.background],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    children: [
                      // Glow behind logo
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cyan.withOpacity(0.25),
                                  blurRadius: 80,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'InterGuard',
                        style: GoogleFonts.inter(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Slogan
              FadeTransition(
                opacity: _sloganFade,
                child: Text(
                  'Block your ads by DNS',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.cyan,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 64),
              FadeTransition(
                opacity: _sloganFade,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.cyan.withOpacity(0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
