import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Press-scale wrapper with haptic tick, used by all remote keys.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child, this.shape = BoxShape.circle});
  final VoidCallback? onTap;
  final Widget child;
  final BoxShape shape;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.32,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}

enum KeyStyle { normal, power, gold }

/// Round remote key: dark bevelled disc, hairline rim, soft drop shadow.
class RemoteKey extends StatelessWidget {
  const RemoteKey({
    super.key,
    this.icon,
    this.label,
    required this.onPressed,
    this.size = 64,
    this.style = KeyStyle.normal,
    this.caption,
  });

  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final double size;
  final KeyStyle style;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final isGold = style == KeyStyle.gold;
    final isPower = style == KeyStyle.power;
    final fg = isGold
        ? const Color(0xFF1A1407)
        : isPower
            ? Lux.ruby
            : Lux.text;
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isGold ? Lux.goldGradient : Lux.keyGradient,
        border: Border.all(
          color: isPower ? const Color(0x88E5484D) : (isGold ? const Color(0x00000000) : Lux.line),
          width: isPower ? 1.4 : 1,
        ),
        boxShadow: [
          const BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8)),
          if (isPower) const BoxShadow(color: Color(0x40E5484D), blurRadius: 22),
          if (isGold) const BoxShadow(color: Color(0x44D9B676), blurRadius: 24),
        ],
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, size: size * 0.40, color: fg)
            : Text(label ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.24,
                  letterSpacing: 0.5,
                  color: fg,
                )),
      ),
    );
    return _Pressable(
      onTap: onPressed,
      child: caption == null
          ? disc
          : Column(mainAxisSize: MainAxisSize.min, children: [
              disc,
              const SizedBox(height: 6),
              Text(caption!, style: const TextStyle(fontSize: 11, color: Lux.muted)),
            ]),
    );
  }
}

/// Vertical pill with + / − (volume, channel, speed, temperature).
class RockerKey extends StatelessWidget {
  const RockerKey({
    super.key,
    required this.label,
    required this.onUp,
    required this.onDown,
    this.upIcon = Icons.add_rounded,
    this.downIcon = Icons.remove_rounded,
    this.height = 164,
  });

  final String label;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final IconData upIcon;
  final IconData downIcon;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget half(IconData i, VoidCallback? f) => Expanded(
          child: _Pressable(
            onTap: f,
            shape: BoxShape.rectangle,
            child: Center(child: Icon(i, color: Lux.text, size: 26)),
          ),
        );
    return Container(
      width: 68,
      height: height,
      decoration: BoxDecoration(
        gradient: Lux.keyGradient,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Lux.line),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(children: [
        half(upIcon, onUp),
        Text(label,
            style: const TextStyle(
              fontSize: 11, letterSpacing: 1.4, color: Lux.gold, fontWeight: FontWeight.w600,
            )),
        half(downIcon, onDown),
      ]),
    );
  }
}

/// Ring D-pad with a champagne OK key.
class DPad extends StatelessWidget {
  const DPad({super.key, this.onUp, this.onDown, this.onLeft, this.onRight, this.onOk});
  final VoidCallback? onUp, onDown, onLeft, onRight, onOk;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData i, VoidCallback? f, Alignment a) => Align(
          alignment: a,
          child: _Pressable(
            onTap: f,
            child: SizedBox(
              width: 70,
              height: 70,
              child: Icon(i, size: 34, color: Lux.text),
            ),
          ),
        );
    return Container(
      width: 236,
      height: 236,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF202026), Color(0xFF131317)],
          stops: [0.55, 1],
        ),
        border: Border.all(color: Lux.line),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: Stack(children: [
        arrow(Icons.keyboard_arrow_up_rounded, onUp, Alignment.topCenter),
        arrow(Icons.keyboard_arrow_down_rounded, onDown, Alignment.bottomCenter),
        arrow(Icons.keyboard_arrow_left_rounded, onLeft, Alignment.centerLeft),
        arrow(Icons.keyboard_arrow_right_rounded, onRight, Alignment.centerRight),
        Center(child: RemoteKey(label: 'OK', size: 92, style: KeyStyle.gold, onPressed: onOk)),
      ]),
    );
  }
}

IconData categoryIcon(String cat) => switch (cat) {
      'TV' => Icons.tv_rounded,
      'Fan' => Icons.wind_power_rounded,
      'Projector' => Icons.videocam_outlined,
      'Box' => Icons.router_outlined,
      'Audio' => Icons.speaker_rounded,
      'AirPurifier' => Icons.air_rounded,
      'AC' => Icons.ac_unit_rounded,
      _ => Icons.devices_other_rounded,
    };
