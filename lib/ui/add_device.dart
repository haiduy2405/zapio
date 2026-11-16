import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ac/ac.dart';
import '../devices/device_store.dart';
import '../ir/encoders.dart';
import '../ir/ir_file.dart';
import '../ir/ir_service.dart';
import '../ir/irdb.dart';
import '../l10n.dart';
import 'ac_remote_screen.dart';
import 'home_screen.dart';
import 'ir_remote_screen.dart';
import 'theme.dart';
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
    return LuxScaffold(
      title: tr(context, 'Add device', 'Thêm thiết bị'),
      body: FutureBuilder<bool>(
        future: IrService.instance.hasEmitter(),
        builder: (context, snap) {
          final hasIr = snap.data ?? false;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              LuxCard(
                highlight: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WifiDiscoverScreen()),
                ),
                child: Row(children: [
                  const IconBadge(Icons.wifi_rounded, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'Smart TV over Wi-Fi', 'Smart TV qua Wi-Fi'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'Samsung • LG • Roku — no IR blaster needed',
                            'Samsung • LG • Roku — không cần cổng hồng ngoại'),
                        style: const TextStyle(color: Lux.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Lux.gold),
                ]),
              ),
              SectionLabel(tr(context, 'Infrared', 'Hồng ngoại')),
              if (snap.hasData && !hasIr)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Text(
                    tr(context, 'This phone has no IR blaster — use Wi-Fi control.',
                        'Máy này không có cổng hồng ngoại — hãy dùng Wi-Fi.'),
                    style: const TextStyle(color: Lux.goldLight, fontSize: 13),
                  ),
                ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
                children: [
                  for (final c in [Cat.ac, ...Cat.irCategories])
                    _CategoryTile(cat: c, enabled: hasIr),
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
  const _CategoryTile({required this.cat, required this.enabled});
  final String cat;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: LuxCard(
        padding: const EdgeInsets.all(10),
        radius: 22,
        onTap: enabled
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => cat == Cat.ac
                      ? const AcBrandPickerScreen()
                      : BrandPickerScreen(category: cat),
                ))
            : null,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconBadge(categoryIcon(cat), size: 50),
          const SizedBox(height: 10),
          Text(Cat.label(context, cat),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.2)),
        ]),
      ),
    );
  }
}

/// Searchable brand list (popular brands first).
class _BrandList extends StatefulWidget {
  const _BrandList({required this.title, required this.brands, required this.popular, required this.onPick,
      this.trailing, this.footer});
  final String title;
  final List<String> brands;
  final List<String> popular;
  final void Function(String brand) onPick;
  final String? Function(String brand)? trailing;
  final Widget? footer;

  @override
  State<_BrandList> createState() => _BrandListState();
}

class _BrandListState extends State<_BrandList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final filtered = widget.brands.where((b) => b.toLowerCase().contains(q)).toList();
    final popular = q.isEmpty ? widget.popular.where(widget.brands.contains).toList() : <String>[];
    Widget tile(String b) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(b, style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.trailing?.call(b) != null)
              Text(widget.trailing!(b)!, style: const TextStyle(color: Lux.muted, fontSize: 12)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Lux.faint),
          ]),
          onTap: () => widget.onPick(b),
        );
    return LuxScaffold(
      title: widget.title,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, color: Lux.muted),
              hintText: tr(context, 'Search brand', 'Tìm thương hiệu'),
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            if (popular.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionLabel(tr(context, 'Top brands', 'Nhãn hiệu hàng đầu')),
              ),
              for (final b in popular) tile(b),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionLabel(tr(context, 'All brands', 'Tất cả nhãn hiệu')),
              ),
            ],
            for (final b in filtered) tile(b),
            if (widget.footer != null) widget.footer!,
          ]),
        ),
      ]),
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
    if (remotes == null) {
      return LuxScaffold(
        title: Cat.label(context, widget.category),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return _BrandList(
      title: Cat.label(context, widget.category),
      brands: IrDb.brands(remotes),
      popular: popularBrands,
      onPick: (b) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProbeScreen(
          category: widget.category,
          brand: b,
          steps: IrDb.probeGroups(remotes, b)
              .map((g) => ProbeStep(send: (c) => sendIr(c, g.power), remoteId: g.best.id))
              .toList(),
        ),
      )),
    );
  }
}

class AcBrandPickerScreen extends StatelessWidget {
  const AcBrandPickerScreen({super.key});

  static const _popular = ['Daikin', 'Panasonic', 'LG', 'Samsung', 'Casper', 'Gree', 'Midea', 'Toshiba', 'Funiki', 'Nagakawa'];

  @override
  Widget build(BuildContext context) {
    final brands = {...AcBrands.map.keys, ...AcBrands.comingSoon}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _BrandList(
      title: Cat.label(context, Cat.ac),
      brands: brands,
      popular: _popular,
      trailing: (b) => AcBrands.comingSoon.contains(b) ? tr(context, 'Soon', 'Sắp có') : null,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.auto_fix_high_rounded, color: Lux.gold),
          label: Text(tr(context, 'Other brand — auto detect', 'Hãng khác — dò tự động')),
          onPressed: () => _open(context, tr(context, 'Air conditioner', 'Điều hòa')),
        ),
      ),
      onPick: (b) {
        if (AcBrands.comingSoon.contains(b)) {
          showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(tr(c, '$b support is coming', 'Sắp hỗ trợ $b')),
              content: Text(tr(c,
                  'Zapio does not speak the $b protocol yet. You can still try the common protocols — some units use them.',
                  'Zapio chưa hỗ trợ giao thức riêng của $b. Bạn vẫn có thể thử các giao thức phổ biến — một số máy dùng chung.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'Close', 'Đóng'))),
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    _open(context, b);
                  },
                  child: Text(tr(c, 'Try anyway', 'Vẫn thử')),
                ),
              ],
            ),
          );
        } else {
          _open(context, b);
        }
      },
    );
  }

  void _open(BuildContext context, String brand) {
    final protos = AcBrands.protocolsFor(brand)
        .map(AcProtocol.byId)
        .whereType<AcProtocol>()
        .toList();
    final test = AcState(power: true, mode: AcMode.cool, temp: 26, fan: AcFan.auto);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProbeScreen(
        category: Cat.ac,
        brand: brand,
        steps: [
          for (final p in protos)
            ProbeStep(send: (c) => sendAc(c, p, test, wasOn: false), remoteId: 'ac:${p.id}'),
        ],
        hint: tr(context, 'Point at the AC and tap Power. It should beep and start cooling at 26 °C.',
            'Hướng vào điều hòa và bấm Nguồn. Máy sẽ kêu "bíp" và bật làm mát 26 °C.'),
      ),
    ));
  }
}

/// One candidate code in the pairing flow.
class ProbeStep {
  ProbeStep({required this.send, required this.remoteId});
  final Future<bool> Function(BuildContext context) send;
  final String remoteId;
}

/// Pairing by trial: send each candidate power code until the device reacts.
class ProbeScreen extends StatefulWidget {
  const ProbeScreen({
    super.key,
    required this.category,
    required this.brand,
    required this.steps,
    this.hint,
  });

  final String category;
  final String brand;
  final List<ProbeStep> steps;
  final String? hint;

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  int _i = 0;
  bool _sent = false;

  Future<void> _send() async {
    HapticFeedback.mediumImpact();
    final ok = await widget.steps[_i].send(context);
    if (ok && mounted) setState(() => _sent = true);
  }

  void _next() {
    if (_i + 1 >= widget.steps.length) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'No match found', 'Không tìm thấy mã phù hợp')),
          content: Text(tr(c,
              'All ${widget.steps.length} codes were tried. Point the top edge of the phone at the device from 1–3 m and try again.',
              'Đã thử hết ${widget.steps.length} bộ mã. Hướng đầu trên điện thoại vào thiết bị, cách 1–3 m rồi thử lại.')),
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
    final store = DeviceStore.instance;
    final name = await askName(context, '${Cat.label(context, widget.category)} ${widget.brand}');
    if (name == null || !mounted) return;
    final d = SavedDevice(
      id: store.newId(),
      name: name,
      kind: DeviceKind.ir,
      category: widget.category,
      remoteId: widget.steps[_i].remoteId,
    );
    await store.add(d);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => d.category == Cat.ac ? AcRemoteScreen(device: d) : IrRemoteScreen(device: d),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.steps.length;
    return LuxScaffold(
      title: widget.brand,
      body: n == 0
          ? Center(child: Text(tr(context, 'No codes for this brand yet', 'Chưa có mã cho hãng này')))
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: (_i + 1) / n, minHeight: 6),
                ),
                const SizedBox(height: 10),
                Text(tr(context, 'Code ${_i + 1} of $n', 'Bộ mã ${_i + 1}/$n'),
                    style: const TextStyle(color: Lux.muted, letterSpacing: 0.5)),
                const Spacer(),
                Text(
                  widget.hint ??
                      tr(context, 'Point your phone at the device and tap Power',
                          'Hướng điện thoại vào thiết bị và bấm nút Nguồn'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500, height: 1.45),
                ),
                const SizedBox(height: 40),
                RemoteKey(
                  icon: Icons.power_settings_new_rounded,
                  size: 132,
                  style: KeyStyle.power,
                  onPressed: _send,
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: _sent ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    tr(context, 'Did the device respond?', 'Thiết bị có phản ứng không?'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _next,
                      child: Text(tr(context, 'No, next code', 'Không, mã tiếp')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
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
