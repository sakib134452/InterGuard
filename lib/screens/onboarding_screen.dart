import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardSlide> _slides = [
    _OnboardSlide(
      icon: Icons.shield_rounded,
      title: 'What is InterGuard?',
      body:
          'InterGuard protects you by routing DNS queries through a secure encrypted DoH server — blocking ads and trackers before they load.',
      iconColor: AppColors.cyan,
    ),
    _OnboardSlide(
      icon: Icons.devices_rounded,
      title: 'Block Ads System-wide',
      body:
          'Unlike browser extensions, InterGuard works across all apps on your device using Android\'s VPN API. No root required.',
      iconColor: const Color(0xFF7C4DFF),
    ),
    _OnboardSlide(
      icon: Icons.dns_rounded,
      title: 'Use Your Own DNS',
      body:
          'Connect to any DoH server — including your self-hosted AdGuard Home. Paste your DoH URL and you\'re protected instantly.',
      iconColor: AppColors.green,
    ),
  ];

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button top-right
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 20, 0),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _SlidePage(slide: _slides[index]),
              ),
            ),

            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? AppColors.cyan
                        : AppColors.textMuted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Next / Get Started button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.textOnAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _OnboardSlide {
  final IconData icon;
  final String title;
  final String body;
  final Color iconColor;

  const _OnboardSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.iconColor,
  });
}

class _SlidePage extends StatelessWidget {
  final _OnboardSlide slide;
  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with glow
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.iconColor.withOpacity(0.1),
              border: Border.all(
                  color: slide.iconColor.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: slide.iconColor.withOpacity(0.2),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Icon(slide.icon, size: 56, color: slide.iconColor),
          ),
          const SizedBox(height: 48),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
