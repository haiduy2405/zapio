import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ac/ac.dart';
import '../devices/device_store.dart';
import '../ir/ir_service.dart';
import '../l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sends an AC state over IR. Returns false (and shows why) on failure.
Future<bool> sendAc(BuildContext context, AcProtocol p, AcState s, {
  required bool wasOn,
  bool wasSwing = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final noIr = tr(context, 'This phone has no IR blaster', 'Máy này không có cổng hồng ngoại');
  try {
    await IrService.instance.transmitFrame(p.encodeChange(s, wasOn: wasOn, wasSwing: wasSwing));
    return true;
  } on PlatformException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.code == 'NO_IR' ? noIr : 'IR: ${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
  return false;
}

String acModeLabel(BuildContext c, AcMode m) => switch (m) {
      AcMode.cool => tr(c, 'Cool', 'Làm mát'),
      AcMode.dry => tr(c, 'Dry', 'Hút ẩm'),
      AcMode.fan => tr(c, 'Fan', 'Quạt'),
      AcMode.auto => tr(c, 'Auto', 'Tự động'),
      AcMode.heat => tr(c, 'Heat', 'Sưởi'),
    };

IconData acModeIcon(AcMode m) => switch (m) {
      AcMode.cool => Icons.ac_unit_rounded,
      AcMode.dry => Icons.water_drop_outlined,
      AcMode.fan => Icons.wind_power_rounded,
      AcMode.auto => Icons.autorenew_rounded,
      AcMode.heat => Icons.wb_sunny_outlined,
    };

String acFanLabel(BuildContext c, AcFan f) => switch (f) {
      AcFan.auto => tr(c, 'Auto', 'Tự động'),
      AcFan.low => tr(c, 'Low', 'Thấp'),
      AcFan.med => tr(c, 'Medium', 'Vừa'),
      AcFan.high => tr(c, 'High', 'Mạnh'),
    };

class AcRemoteScreen extends StatefulWidget {
  const AcRemoteScreen({super.key, required this.device});
  final SavedDevice device;

  @override
  State<AcRemoteScreen> createState() => _AcRemoteScreenState();
}

class _AcRemoteScreenState extends State<AcRemoteScreen> {
  AcProtocol? _proto;
  AcState _s = AcState(power: false);
  bool _lastSentOn = false;
  bool _lastSentSwing = false;
  bool _sending = false;
  bool _sendAgain = false;
  Timer? _debounce;

  String get _prefKey => 'ac_state_${widget.device.id}';

  @override
  void initState() {
    super.initState();
    final id = (widget.device.remoteId ?? '').replaceFirst('ac:', '');
    _proto = AcProtocol.byId(id);
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString(_prefKey);
      if (raw != null && mounted) {
        setState(() {
          _s = AcState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          _lastSentOn = _s.power;
          _lastSentSwing = _s.swing;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _change(void Function(AcState s) f, {bool immediate = true}) {
    setState(() => f(_s));
    _debounce?.cancel();
    if (immediate) {
      _send();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), _send);
    }
  }

  Future<void> _send() async {
    if (_sending) {
      _sendAgain = true;
      return;
    }
    final p = _proto;
    if (p == null || !mounted) return;
    _sending = true;
    try {
      do {
        _sendAgain = false;
        final state = _s.copy();
        final ok = await sendAc(context, p, state, wasOn: _lastSentOn, wasSwing: _lastSentSwing);
        if (ok) {
          _lastSentOn = state.power;
          _lastSentSwing = state.swing;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKey, jsonEncode(state.toJson()));
        }
      } while (_sendAgain && mounted);
    } finally {
      _sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _proto;
    final on = _s.power;
    final minT = p?.minTemp ?? 16, maxT = p?.maxTemp ?? 30;
    final tempEnabled = on && _s.mode != AcMode.fan;
    return LuxScaffold(
      title: widget.device.name,
      body: p == null
          ? Center(child: Text(tr(context, 'Unknown AC protocol', 'Không rõ giao thức điều hòa')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Center(
                  child: _TempDial(
                    temp: _s.temp,
                    min: minT,
                    max: maxT,
                    on: on,
                    subtitle: on
                        ? '${acModeLabel(context, _s.mode)} • ${tr(context, 'Fan', 'Quạt')} ${acFanLabel(context, _s.fan).toLowerCase()}'
                        : tr(context, 'Off', 'Đang tắt'),
                    showTemp: _s.mode != AcMode.fan,
                  ),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  RemoteKey(
                    icon: Icons.remove_rounded,
                    size: 70,
                    onPressed: tempEnabled && _s.temp > minT
                        ? () => _change((s) => s.temp--, immediate: false)
                        : null,
                  ),
                  RemoteKey(
                    icon: Icons.power_settings_new_rounded,
                    size: 84,
                    style: on ? KeyStyle.power : KeyStyle.normal,
                    onPressed: () => _change((s) => s.power = !s.power),
                  ),
                  RemoteKey(
                    icon: Icons.add_rounded,
                    size: 70,
                    onPressed: tempEnabled && _s.temp < maxT
                        ? () => _change((s) => s.temp++, immediate: false)
                        : null,
                  ),
                ]),
                SectionLabel(tr(context, 'Mode', 'Chế độ')),
                _ChipRow<AcMode>(
                  values: AcMode.values,
                  selected: _s.mode,
                  enabled: on,
                  icon: acModeIcon,
                  label: (m) => acModeLabel(context, m),
                  onSelect: (m) => _change((s) => s.mode = m),
                ),
                SectionLabel(tr(context, 'Fan speed', 'Tốc độ quạt')),
                _ChipRow<AcFan>(
                  values: AcFan.values,
                  selected: _s.fan,
                  enabled: on,
                  label: (f) => acFanLabel(context, f),
                  onSelect: (f) => _change((s) => s.fan = f),
                ),
                const SizedBox(height: 18),
                LuxCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Lux.gold,
                    secondary: const Icon(Icons.swap_vert_rounded, color: Lux.gold),
                    title: Text(tr(context, 'Swing', 'Đảo gió')),
                    value: _s.swing,
                    onChanged: on ? (v) => _change((s) => s.swing = v) : null,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${tr(context, 'Protocol', 'Giao thức')}: ${p.label}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Lux.faint, fontSize: 12),
                ),
              ],
            ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onSelect,
    this.icon,
  });

  final List<T> values;
  final T selected;
  final bool enabled;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final void Function(T) onSelect;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        onSelect(v);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: v == selected ? Lux.goldGradient : Lux.keyGradient,
                    border: Border.all(color: v == selected ? Colors.transparent : Lux.line),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[
                      Icon(icon!(v), size: 20, color: v == selected ? const Color(0xFF1A1407) : Lux.text),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      label(v),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: v == selected ? const Color(0xFF1A1407) : Lux.muted,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Large circular gauge with the set temperature.
class _TempDial extends StatelessWidget {
  const _TempDial({
    required this.temp,
    required this.min,
    required this.max,
    required this.on,
    required this.subtitle,
    required this.showTemp,
  });

  final int temp, min, max;
  final bool on;
  final String subtitle;
  final bool showTemp;

  @override
  Widget build(BuildContext context) {
    final frac = ((temp - min) / (max - min)).clamp(0.0, 1.0);
    return SizedBox(
      width: 270,
      height: 270,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: on ? frac : 0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => CustomPaint(size: const Size(270, 270), painter: _DialPainter(v, on)),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          if (showTemp)
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$temp',
                  style: TextStyle(
                    fontSize: 84,
                    fontWeight: FontWeight.w300,
                    height: 1,
                    color: on ? Lux.text : Lux.faint,
                  )),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('°C', style: TextStyle(fontSize: 22, color: on ? Lux.gold : Lux.faint)),
              ),
            ])
          else
            Icon(Icons.wind_power_rounded, size: 72, color: on ? Lux.gold : Lux.faint),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Lux.muted, fontSize: 13)),
        ]),
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.frac, this.on);
  final double frac;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 14;
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1F1F24);
    canvas.drawArc(rect, start, sweep, false, track);
    if (frac > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: math.pi * 0.75,
          endAngle: math.pi * 2.25,
          colors: [Lux.goldDeep, Lux.gold, Lux.goldLight],
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep * frac, false, arc);
      final a = start + sweep * frac;
      final knob = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawCircle(knob, 11, Paint()..color = Lux.goldLight);
      canvas.drawCircle(knob, 5, Paint()..color = Lux.bg);
    }
    // tick marks
    final tick = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1.2;
    for (var i = 0; i <= 28; i++) {
      final a = start + sweep * i / 28;
      final o = Offset(c.dx + (r - 18) * math.cos(a), c.dy + (r - 18) * math.sin(a));
      final ii = Offset(c.dx + (r - 24) * math.cos(a), c.dy + (r - 24) * math.sin(a));
      canvas.drawLine(ii, o, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.frac != frac || old.on != on;
}
