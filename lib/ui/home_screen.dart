import 'package:flutter/material.dart';

import '../devices/device_store.dart';
import '../l10n.dart';
import '../update/update_gate.dart';
import '../update/updater.dart';
import 'ac_remote_screen.dart';
import 'add_device.dart';
import 'share_screens.dart';
import '../devices/share_codec.dart';
import 'ir_remote_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wifi_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final store = DeviceStore.instance;
  late final Future<(int, String)> _appVersion;

  @override
  void initState() {
    super.initState();
    _appVersion = Updater.instance.currentVersion();
    store.addListener(_changed);
    if (!store.loaded) store.load();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _add() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));

  void _shareQr(List<SavedDevice> list) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ShareQrScreen(devices: list)));

  void _scanQr() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const ScanQrScreen()));

  void _open(SavedDevice d) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => d.isWifi
            ? TvRemoteScreen(device: d)
            : d.category == Cat.ac
                ? AcRemoteScreen(device: d)
                : IrRemoteScreen(device: d),
      ));

  Future<void> _menu(SavedDevice d) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Lux.faint, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(d.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded, color: Lux.gold),
              title: Text(tr(c, 'Share via QR code', 'Chia sẻ qua mã QR')),
              subtitle: Text(tr(c, 'Copy this remote to another phone', 'Sao chép remote sang điện thoại khác'),
                  style: const TextStyle(color: Lux.muted, fontSize: 12)),
              onTap: () => Navigator.pop(c, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_rounded),
              title: Text(tr(c, 'Duplicate', 'Nhân bản')),
              onTap: () => Navigator.pop(c, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr(c, 'Rename', 'Đổi tên')),
              onTap: () => Navigator.pop(c, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Lux.ruby),
              title: Text(tr(c, 'Delete', 'Xóa'), style: const TextStyle(color: Lux.ruby)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'share') {
      _shareQr([d]);
    } else if (action == 'duplicate') {
      final name = await askName(context, '${d.name} (2)');
      if (name != null) await ShareCodec.duplicate(d, name);
    } else if (action == 'delete') {
      await store.remove(d);
    } else if (action == 'rename') {
      final name = await askName(context, d.name);
      if (name != null) {
        d.name = name;
        await store.update(d);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = store.devices;
    return LuxScaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: GoldText('Zapio',
                      style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                ),
                IconButton(
                  tooltip: tr(context, 'Scan QR code', 'Quét mã QR'),
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: Lux.gold),
                  onPressed: _scanQr,
                ),
                if (devices.isNotEmpty)
                  IconButton(
                    tooltip: tr(context, 'Share all devices', 'Chia sẻ tất cả thiết bị'),
                    icon: const Icon(Icons.ios_share_rounded, color: Lux.gold),
                    onPressed: () => _shareQr(List.of(devices)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(
                devices.isEmpty
                    ? tr(context, 'Your home, one remote', 'Một remote cho cả ngôi nhà')
                    : tr(context, '${devices.length} devices', '${devices.length} thiết bị'),
                style: const TextStyle(color: Lux.muted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _AppSignature(version: _appVersion),
              if (updateChannel == 'github')
                TextButton.icon(
                  onPressed: () => UpdateGate.checkNow(context),
                  icon: const Icon(Icons.system_update_rounded, size: 16),
                  label: Text(tr(context, 'Check for updates', 'Kiểm tra cập nhật')),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0)),
                ),
            ]),
          ),
        ),
        if (!store.loaded)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (devices.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _Empty(onAdd: _add))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.98,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  if (i == devices.length) return _AddTile(onTap: _add);
                  final d = devices[i];
                  return LuxCard(
                    onTap: () => _open(d),
                    onLongPress: () => _menu(d),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBadge(categoryIcon(d.category)),
                        const Spacer(),
                        Icon(d.isWifi ? Icons.wifi_rounded : Icons.settings_remote_rounded,
                            size: 16, color: Lux.faint),
                      ]),
                      const Spacer(),
                      Text(d.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25)),
                      const SizedBox(height: 4),
                      Text(
                        '${Cat.label(context, d.category)} • ${d.isWifi ? 'Wi-Fi' : tr(context, 'Infrared', 'Hồng ngoại')}',
                        style: const TextStyle(color: Lux.muted, fontSize: 12),
                      ),
                    ]),
                  );
                },
                childCount: devices.length + 1,
              ),
            ),
          ),
      ]),
    );
  }
}

class _AppSignature extends StatelessWidget {
  const _AppSignature({required this.version});

  final Future<(int, String)> version;

  @override
  Widget build(BuildContext context) => FutureBuilder<(int, String)>(
        future: version,
        builder: (context, snapshot) {
          final versionName = snapshot.data?.$2.trim() ?? '';
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (versionName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x14D9B676),
                    border: Border.all(color: const Color(0x55D9B676)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v$versionName',
                    style: const TextStyle(
                      color: Lux.goldLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Text.rich(
                TextSpan(
                  text: 'Made by ',
                  children: [
                    TextSpan(
                      text: 'duyluma',
                      style: TextStyle(
                        color: Lux.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(color: Lux.muted, fontSize: 11),
              ),
            ],
          );
        },
      );
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LuxCard(
        onTap: onTap,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_circle_outline_rounded, color: Lux.gold, size: 36),
            const SizedBox(height: 10),
            Text(tr(context, 'Add device', 'Thêm thiết bị'),
                style: const TextStyle(color: Lux.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x55D9B676), width: 1.2),
            gradient: const RadialGradient(colors: [Color(0x22D9B676), Color(0x00D9B676)]),
          ),
          child: const Icon(Icons.settings_remote_rounded, size: 56, color: Lux.gold),
        ),
        const SizedBox(height: 28),
        Text(tr(context, 'No devices yet', 'Chưa có thiết bị nào'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(
          tr(context, 'Add your TV, fan, air conditioner or projector and control everything from here.',
              'Thêm TV, quạt, điều hòa hay máy chiếu để điều khiển tất cả tại đây.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Lux.muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(220, 56)),
          icon: const Icon(Icons.add_rounded),
          label: Text(tr(context, 'Add device', 'Thêm thiết bị')),
          onPressed: onAdd,
        ),
      ]),
    );
  }
}

Future<String?> askName(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, 'Device name', 'Tên thiết bị')),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'Cancel', 'Hủy'))),
        TextButton(
          onPressed: () {
            final t = ctrl.text.trim();
            Navigator.pop(c, t.isEmpty ? null : t);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
