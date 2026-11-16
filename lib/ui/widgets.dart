import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Round remote button with icon or short label.
class RemoteKey extends StatelessWidget {
  const RemoteKey({
    super.key,
    this.icon,
    this.label,
    required this.onPressed,
    this.size = 64,
    this.color,
  });

  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: onPressed == null
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : (color ?? scheme.surfaceContainerHighest),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                },
          child: Center(
            child: icon != null
                ? Icon(icon, size: size * 0.42)
                : Text(label ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Vertical pill with + / − (volume, channel).
class RockerKey extends StatelessWidget {
  const RockerKey({
    super.key,
    required this.label,
    required this.onUp,
    required this.onDown,
    this.upIcon = Icons.add,
    this.downIcon = Icons.remove,
  });

  final String label;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final IconData upIcon;
  final IconData downIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget half(IconData i, VoidCallback? f) => Expanded(
          child: InkWell(
            onTap: f == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    f();
                  },
            child: Center(child: Icon(i, color: f == null ? Colors.white24 : null)),
          ),
        );
    return Container(
      width: 64,
      height: 150,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(32),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        half(upIcon, onUp),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        half(downIcon, onDown),
      ]),
    );
  }
}

/// D-pad with OK in the middle.
class DPad extends StatelessWidget {
  const DPad({
    super.key,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onOk,
  });

  final VoidCallback? onUp, onDown, onLeft, onRight, onOk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget arrow(IconData i, VoidCallback? f, Alignment a) => Align(
          alignment: a,
          child: IconButton(
            iconSize: 34,
            onPressed: f == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    f();
                  },
            icon: Icon(i),
          ),
        );
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: Stack(children: [
        arrow(Icons.keyboard_arrow_up, onUp, Alignment.topCenter),
        arrow(Icons.keyboard_arrow_down, onDown, Alignment.bottomCenter),
        arrow(Icons.keyboard_arrow_left, onLeft, Alignment.centerLeft),
        arrow(Icons.keyboard_arrow_right, onRight, Alignment.centerRight),
        Center(
          child: RemoteKey(
            label: 'OK',
            size: 84,
            color: scheme.primaryContainer,
            onPressed: onOk,
          ),
        ),
      ]),
    );
  }
}

IconData categoryIcon(String cat) => switch (cat) {
      'TV' => Icons.tv,
      'Fan' => Icons.wind_power,
      'Projector' => Icons.videocam_outlined,
      'Box' => Icons.router_outlined,
      'Audio' => Icons.speaker,
      'AirPurifier' => Icons.air,
      'AC' => Icons.ac_unit,
      _ => Icons.devices_other,
    };
