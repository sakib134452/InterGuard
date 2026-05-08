import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vpn_models.dart';

class PowerButton extends StatefulWidget {
  final VpnStatus status;
  final VoidCallback? onTap;
  final AnimationController pulseCtrl;
  final double size;

  const PowerButton({
    super.key,
    required this.status,
    required this.onTap,
    required this.pulseCtrl,
    this.size = 200.0,
  });

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _pressAnim =
        Tween<double>(begin: 1.0, end: 0.94).animate(_pressCtrl);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Color get _ringColor {
    switch (widget.status) {
      case VpnStatus.connected:
        return AppColors.green;
      case VpnStatus.connecting:
        return AppColors.cyan;
      case VpnStatus.disconnected:
        return AppColors.textMuted;
    }
  }

  Color get _buttonBg {
    switch (widget.status) {
      case VpnStatus.connected:
        return AppColors.green.withOpacity(0.15);
      case VpnStatus.connecting:
        return AppColors.cyan.withOpacity(0.1);
      case VpnStatus.disconnected:
        return AppColors.surface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.status == VpnStatus.connected;
    final isConnecting = widget.status == VpnStatus.connecting;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _pressAnim,
        child: AnimatedBuilder(
          animation: widget.pulseCtrl,
          builder: (_, child) {
            final pulse = widget.pulseCtrl.value;
            final ringOpacity =
                isConnected ? 0.3 + 0.2 * pulse : 0.15;
            final glowRadius = isConnected ? 40.0 + 20.0 * pulse : 20.0;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _ringColor.withOpacity(ringOpacity * 0.5),
                        blurRadius: glowRadius * 1.5,
                        spreadRadius: isConnected ? 8 : 0,
                      ),
                    ],
                  ),
                ),
                // Animated ring
                Container(
                  width: widget.size * 0.9,
                  height: widget.size * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _ringColor.withOpacity(ringOpacity),
                      width: isConnected ? 2.5 : 1.5,
                    ),
                  ),
                ),
                // Button body
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: widget.size * 0.74,
                  height: widget.size * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _buttonBg,
                    border: Border.all(
                      color: _ringColor.withOpacity(0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _ringColor.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: isConnecting
                      ? _buildSpinner()
                      : _buildPowerIcon(isConnected),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPowerIcon(bool isOn) {
    final iconSize = widget.size * 0.26;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.power_settings_new_rounded,
          size: iconSize,
          color: isOn ? AppColors.green : AppColors.textMuted,
        ),
        const SizedBox(height: 4),
        Text(
          isOn ? 'ON' : 'OFF',
          style: GoogleFonts.inter(
            fontSize: widget.size * 0.065,
            fontWeight: FontWeight.w700,
            color: isOn ? AppColors.green : AppColors.textMuted,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildSpinner() {
    final spinnerSize = widget.size * 0.26;
    return Center(
      child: SizedBox(
        width: spinnerSize,
        height: spinnerSize,
        child: const CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyan),
        ),
      ),
    );
  }
}
