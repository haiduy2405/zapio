import 'package:flutter/material.dart';

import '../devices/device_store.dart';
import '../ir/ir_file.dart';
import '../ir/irdb.dart';
import '../l10n.dart';
import 'add_device.dart';
import 'theme.dart';
import 'widgets.dart';

/// Remote for a saved IR device: standard layout from the mapped keys,
/// plus every button of the remote under "All buttons".
class IrRemoteScreen extends StatefulWidget {
  const IrRemoteScreen({super.key, required this.device});
  final SavedDevice device;

  @override
  State<IrRemoteScreen> createState() => _IrRemoteScreenState();
}

class _IrRemoteScreenState extends State<IrRemoteScreen> {
  IrRemote? _remote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    IrDb.byId(widget.device.category, widget.device.remoteId ?? '').then((r) {
      if (mounted) {
        setState(() {
          _remote = r;
          _loading = false;
        });
      }
    });
  }

  VoidCallback? _k(String std) {
    final s = _remote?.key(std);
    return s == null ? null : () => sendIr(context, s);
  }

  VoidCallback? _any(List<String> stds) {
    for (final k in stds) {
      final f = _k(k);
      if (f != null) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = _remote;
    return LuxScaffold(
      title: widget.device.name,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
              ? Center(child: Text(tr(context, 'Remote data not found', 'Không tìm thấy dữ liệu remote')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    _layout(context, r),
                    const SizedBox(height: 28),
                    _AllButtons(signals: r.signals),
                    const SizedBox(height: 16),
                    Text(
                      '${r.brand} • ${r.model}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Lux.faint, fontSize: 12),
                    ),
                  ],
                ),
    );
  }

  Widget _layout(BuildContext context, IrRemote r) {
    final isFanLike = r.category == Cat.fan || r.category == Cat.airPurifier;
    final topRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RemoteKey(icon: Icons.power_settings_new_rounded, style: KeyStyle.power, onPressed: _k('PWR')),
        if (isFanLike)
          RemoteKey(icon: Icons.timer_outlined, onPressed: _k('TIMER'))
        else
          RemoteKey(icon: Icons.input_rounded, onPressed: _any(['INPUT', 'TV', 'AUX'])),
        RemoteKey(
          icon: isFanLike ? Icons.nights_stay_outlined : Icons.volume_off_rounded,
          onPressed: isFanLike ? _k('SLEEP') : _k('MUTE'),
        ),
      ],
    );

    if (isFanLike) {
      return Column(children: [
        topRow,
        const SizedBox(height: 36),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          RockerKey(
            label: tr(context, 'SPEED', 'TỐC ĐỘ'),
            onUp: _any(['FAN_SPEED_UP', 'WIND_SPEED', 'FAN_SPEED', 'FAN_HIGH']),
            onDown: _any(['FAN_SPEED_DOWN', 'FAN_LOW']),
          ),
          Column(children: [
            RemoteKey(
              icon: Icons.threesixty_rounded,
              caption: tr(context, 'Oscillate', 'Đảo'),
              onPressed: _any(['SHAKE_WIND', 'OSCILLATE', 'SWING']),
            ),
            const SizedBox(height: 18),
            RemoteKey(icon: Icons.tune_rounded, caption: tr(context, 'Mode', 'Chế độ'), onPressed: _any(['WIND_TYPE', 'MODE'])),
          ]),
          Column(children: [
            RemoteKey(icon: Icons.lightbulb_outline_rounded, caption: tr(context, 'Light', 'Đèn'), onPressed: _k('LIGHT')),
            const SizedBox(height: 18),
            RemoteKey(icon: Icons.ac_unit_rounded, caption: tr(context, 'Cool', 'Mát'), onPressed: _any(['COLD_WIND', 'COOL'])),
          ]),
        ]),
      ]);
    }

    return Column(children: [
      topRow,
      const SizedBox(height: 28),
      DPad(
        onUp: _k('UP'),
        onDown: _k('DOWN'),
        onLeft: _k('LEFT'),
        onRight: _k('RIGHT'),
        onOk: _k('OK'),
      ),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        RemoteKey(icon: Icons.arrow_back_rounded, onPressed: _any(['BACK', 'EXIT'])),
        RemoteKey(icon: Icons.home_rounded, onPressed: _k('HOME')),
        RemoteKey(icon: Icons.menu_rounded, onPressed: _k('MENU')),
      ]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        RockerKey(label: 'VOL', onUp: _k('VOL_UP'), onDown: _k('VOL_DOWN')),
        Column(children: [
          RemoteKey(icon: Icons.play_arrow_rounded, onPressed: _k('PLAY')),
          const SizedBox(height: 18),
          RemoteKey(icon: Icons.pause_rounded, onPressed: _k('PAUSE')),
        ]),
        RockerKey(
          label: 'CH',
          onUp: _k('CH_UP'),
          onDown: _k('CH_DOWN'),
          upIcon: Icons.keyboard_arrow_up_rounded,
          downIcon: Icons.keyboard_arrow_down_rounded,
        ),
      ]),
    ]);
  }
}

class _AllButtons extends StatelessWidget {
  const _AllButtons({required this.signals});
  final List<IrSignal> signals;

  @override
  Widget build(BuildContext context) {
    return LuxCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(tr(context, 'All buttons (${signals.length})', 'Tất cả nút (${signals.length})'),
              style: const TextStyle(fontWeight: FontWeight.w500)),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in signals)
                  ActionChip(
                    label: Text(s.name.replaceAll('_', ' ')),
                    onPressed: () => sendIr(context, s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
