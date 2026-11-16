import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../devices/device_store.dart';
import '../ir/encoders.dart';
import '../ir/ir_file.dart';
import '../ir/ir_service.dart';
import '../ir/irdb.dart';
import '../l10n.dart';
import 'home_screen.dart';
import 'ir_remote_screen.dart';
import 'widgets.dart';
import 'wifi_screens.dart';

/// Sends [s] over IR; shows a SnackBar only on failure.
Future<bool> sendIr(BuildContext context, IrSignal s) async {
  final messenger = ScaffoldMessenger.of(context);
  final noEmitter = tr(context, 'This phone has no IR blaster', 'Máy này không có cổng hồng ngoại');
  try {
    await IrService.instance.send(s);
    return true;
  } on UnsupportedProtocol catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  } on PlatformException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.code == 'NO_IR' ? noEmitter : 'IR: ${e.code} ${e.message ?? ''}'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
  return false;
}

class AddDeviceScreen extends StatelessWidget {
  const AddDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Add device', 'Thêm thiết bị'))),
      body: FutureBuilder<bool>(
        future: IrService.instance.hasEmitter(),
        builder: (context, snap) {
          final hasIr = snap.data ?? false;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.wifi, size: 32),
                  title: Text(tr(context, 'Smart TV over Wi-Fi', 'Smart TV qua Wi-Fi')),
                  subtitle: const Text('Samsung • LG • Roku'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WifiDiscoverScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(tr(context, 'Infrared (IR blaster)', 'Hồng ngoại (IR)'),
                  style: Theme.of(context).textTheme.titleMedium),
              if (snap.hasData && !hasIr)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr(context, 'This phone has no IR blaster — use Wi-Fi control.',
                        'Máy này không có cổng hồng ngoại — hãy dùng Wi-Fi.'),
                    style: const TextStyle(color: Colors.amberAccent),
                  ),
                ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final c in [...Cat.irCategories, Cat.ac])
                    _CategoryTile(
                      cat: c,
                      enabled: hasIr && c != Cat.ac,
                      badge: c == Cat.ac ? tr(context, 'Soon', 'Sắp có') : null,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.cat, required this.enabled, this.badge});
  final String cat;
  final bool enabled;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BrandPickerScreen(category: cat)))
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(categoryIcon(cat), size: 36),
            const SizedBox(height: 8),
            Text(Cat.label(context, cat),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            if (badge != null)
              Text(badge!, style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
          ]),
        ),
      ),
    );
  }
}

class BrandPickerScreen extends StatefulWidget {
  const BrandPickerScreen({super.key, required this.category});
  final String category;

  @override
  State<BrandPickerScreen> createState() => _BrandPickerScreenState();
}

class _BrandPickerScreenState extends State<BrandPickerScreen> {
  List<IrRemote>? _remotes;
  String _q = '';

  @override
  void initState() {
    super.initState();
    IrDb.category(widget.category).then((r) {
      if (mounted) setState(() => _remotes = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final remotes = _remotes;
    final all = remotes == null ? <String>[] : IrDb.brands(remotes);
    final q = _q.toLowerCase();
    final filtered = all.where((b) => b.toLowerCase().contains(q)).toList();
    final popular = q.isEmpty
        ? popularBrands.where((p) => all.contains(p)).toList()
        : <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(Cat.label(context, widget.category))),
      body: remotes == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr(context, 'Search brand', 'Tìm thương hiệu'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  if (popular.isNotEmpty) ...[
                    _header(context, tr(context, 'Top brands', 'Nhãn hiệu hàng đầu')),
                    for (final b in popular) _brandTile(b),
                    _header(context, tr(context, 'All brands', 'Tất cả nhãn hiệu')),
                  ],
                  for (final b in filtered) _brandTile(b),
                ]),
              ),
            ]),
    );
  }

  Widget _header(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(t, style: const TextStyle(color: Colors.white60)),
      );

  Widget _brandTile(String b) => ListTile(
        title: Text(b),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProbeScreen(
            category: widget.category,
            brand: b,
            groups: IrDb.probeGroups(_remotes!, b),
          ),
        )),
      );
}

/// Pairing by trial: send the power code of each code-group until the
/// device reacts, then save it.
class ProbeScreen extends StatefulWidget {
  const ProbeScreen({
    super.key,
    required this.category,
    required this.brand,
    required this.groups,
  });

  final String category;
  final String brand;
  final List<ProbeGroup> groups;

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  int _i = 0;
  bool _sent = false;

  ProbeGroup get _g => widget.groups[_i];

  Future<void> _send() async {
    HapticFeedback.mediumImpact();
    final ok = await sendIr(context, _g.power);
    if (ok && mounted) setState(() => _sent = true);
  }

  void _next() {
    if (_i + 1 >= widget.groups.length) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'No match found', 'Không tìm thấy mã phù hợp')),
          content: Text(tr(c,
              'All ${widget.groups.length} codes for ${widget.brand} were tried. Point the phone’s top edge at the device from 1–3 m and try again.',
              'Đã thử hết ${widget.groups.length} bộ mã của ${widget.brand}. Hãy hướng đầu trên điện thoại vào thiết bị, cách 1–3 m rồi thử lại.')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() {
                  _i = 0;
                  _sent = false;
                });
              },
              child: Text(tr(c, 'Start over', 'Thử lại từ đầu')),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _i++;
      _sent = false;
    });
  }

  Future<void> _works() async {
    final remote = _g.best;
    final store = DeviceStore.instance;
    final name = await askName(context, '${Cat.label(context, widget.category)} ${widget.brand}');
    if (name == null || !mounted) return;
    final d = SavedDevice(
      id: store.newId(),
      name: name,
      kind: DeviceKind.ir,
      category: widget.category,
      remoteId: remote.id,
    );
    await store.add(d);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => IrRemoteScreen(device: d)));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.groups.length;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.brand} • ${Cat.label(context, widget.category)}')),
      body: n == 0
          ? Center(child: Text(tr(context, 'No codes for this brand', 'Chưa có mã cho hãng này')))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                LinearProgressIndicator(value: (_i + 1) / n),
                const SizedBox(height: 8),
                Text(tr(context, 'Code ${_i + 1} of $n', 'Bộ mã ${_i + 1}/$n'),
                    style: const TextStyle(color: Colors.white60)),
                const Spacer(),
                Text(
                  tr(context, 'Point your phone at the device and tap Power',
                      'Hướng điện thoại vào thiết bị và bấm nút Nguồn'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 32),
                RemoteKey(
                  icon: Icons.power_settings_new,
                  size: 120,
                  color: Colors.red.shade800,
                  onPressed: _send,
                ),
                const Spacer(),
                Text(
                  _sent
                      ? tr(context, 'Did the device respond?', 'Thiết bị có phản ứng không?')
                      : ' ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: _next,
                      child: Text(tr(context, 'No, next code', 'Không, mã tiếp')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: _sent ? _works : null,
                      child: Text(tr(context, 'Yes, it works', 'Có, hoạt động')),
                    ),
                  ),
                ]),
              ]),
            ),
    );
  }
}
