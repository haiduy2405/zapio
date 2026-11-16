import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ir/encoders.dart';
import '../ir/ir_file.dart';
import '../ir/ir_library.dart';
import '../ir/ir_service.dart';

const _categoryLabels = {'AC': 'Điều hòa', 'TV': 'TV', 'Fan': 'Quạt'};
const _categoryIcons = {'AC': Icons.ac_unit, 'TV': Icons.tv, 'Fan': Icons.wind_power};

/// Sends [s] and reports the result in a SnackBar.
Future<bool> sendWithFeedback(BuildContext context, IrSignal s) async {
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.lightImpact();
  try {
    final f = await IrService.instance.send(s);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 900),
      content: Text('Đã phát "${s.name}" • ${f.frequency ~/ 1000} kHz • '
          '${f.pattern.length} xung • ${(f.durationUs / 1000).round()} ms'),
    ));
    return true;
  } on UnsupportedProtocol catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  } on PlatformException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Lỗi phát IR: ${e.code} ${e.message ?? ''}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
  }
  return false;
}

class IrHomeScreen extends StatelessWidget {
  const IrHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zapio • Hồng ngoại')),
      body: FutureBuilder<IrLibrary>(
        future: IrLibrary.load(),
        builder: (context, snap) {
          final lib = snap.data;
          if (lib == null) {
            return snap.hasError
                ? Center(child: Text('Lỗi tải kho mã: ${snap.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _EmitterStatusCard(),
              const SizedBox(height: 16),
              for (final cat in lib.categories()) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(_categoryLabels[cat] ?? cat,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Card(
                  child: Column(children: [
                    for (final b in lib.brands(cat))
                      ListTile(
                        leading: Icon(_categoryIcons[cat] ?? Icons.devices_other),
                        title: Text(b),
                        subtitle: Text('${lib.remotes(cat, b).length} mẫu remote'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BrandScreen(
                            category: cat,
                            brand: b,
                            remotes: lib.remotes(cat, b),
                          ),
                        )),
                      ),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmitterStatusCard extends StatelessWidget {
  const _EmitterStatusCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, List<List<int>>)>(
      future: () async {
        final has = await IrService.instance.hasEmitter();
        final f = has ? await IrService.instance.carrierFrequencies() : <List<int>>[];
        return (has, f);
      }(),
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const LinearProgressIndicator();
        final (has, freqs) = d;
        final ranges = freqs.map((r) => '${r[0] ~/ 1000}–${r[1] ~/ 1000} kHz').join(', ');
        return Card(
          color: has ? Colors.teal.shade900 : Colors.red.shade900,
          child: ListTile(
            leading: Icon(has ? Icons.check_circle : Icons.error_outline),
            title: Text(has ? 'Máy có cổng hồng ngoại' : 'Máy KHÔNG có cổng hồng ngoại'),
            subtitle: Text(has
                ? (ranges.isEmpty ? 'Không đọc được dải tần' : 'Dải tần: $ranges')
                : 'Chỉ dùng được điều khiển qua Wi-Fi'),
          ),
        );
      },
    );
  }
}

class BrandScreen extends StatelessWidget {
  const BrandScreen({
    super.key,
    required this.category,
    required this.brand,
    required this.remotes,
  });

  final String category;
  final String brand;
  final List<IrRemoteEntry> remotes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${_categoryLabels[category] ?? category} $brand')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PowerProbeCard(remotes: remotes),
          const SizedBox(height: 16),
          Text('Tất cả mẫu', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final r in remotes)
                ListTile(
                  title: Text(r.model),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RemoteScreen(entry: r)),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// "Dò mã" flow: fire POWER of each remote until the device reacts.
class PowerProbeCard extends StatefulWidget {
  const PowerProbeCard({super.key, required this.remotes});
  final List<IrRemoteEntry> remotes;

  @override
  State<PowerProbeCard> createState() => _PowerProbeCardState();
}

class _PowerProbeCardState extends State<PowerProbeCard> {
  int _i = 0;
  IrSignal? _power;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sigs = await IrLibrary.signalsOf(widget.remotes[_i]);
    if (!mounted) return;
    setState(() {
      _power = findPowerSignal(sigs) ?? (sigs.isNotEmpty ? sigs.first : null);
      _loading = false;
    });
  }

  void _next() {
    if (_i + 1 >= widget.remotes.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã thử hết các mẫu của hãng này.'),
      ));
      return;
    }
    _i++;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.remotes[_i];
    final p = _power;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dò mã nhanh', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Mẫu ${_i + 1}/${widget.remotes.length}: ${r.model}'),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else
              FilledButton.icon(
                icon: const Icon(Icons.power_settings_new),
                label: Text(p == null ? 'Không có nút nguồn' : 'Phát "${p.name}"'),
                onPressed: p == null ? null : () => sendWithFeedback(context, p),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _next,
                  child: const Text('Không phản ứng → mẫu sau'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RemoteScreen(entry: r)),
                  ),
                  child: const Text('Hoạt động! Mở remote'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key, required this.entry});
  final IrRemoteEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(entry.model)),
      body: FutureBuilder<List<IrSignal>>(
        future: IrLibrary.signalsOf(entry),
        builder: (context, snap) {
          final sigs = snap.data;
          if (sigs == null) return const Center(child: CircularProgressIndicator());
          if (sigs.isEmpty) return const Center(child: Text('File không có tín hiệu hợp lệ'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.4,
            ),
            itemCount: sigs.length,
            itemBuilder: (context, i) {
              final s = sigs[i];
              final supported = s.isRaw || supportedProtocols.contains(s.protocol);
              return FilledButton.tonal(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.all(6),
                ),
                onPressed: supported ? () => sendWithFeedback(context, s) : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(s.name.replaceAll('_', ' '),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(s.isRaw ? 'raw' : s.protocol ?? '',
                        style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
