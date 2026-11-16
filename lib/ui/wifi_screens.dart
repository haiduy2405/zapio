import 'package:flutter/material.dart';

import '../devices/device_store.dart';
import '../l10n.dart';
import '../wifi/android_tv.dart';
import '../wifi/discovery.dart';
import '../wifi/tv_link.dart';
import 'theme.dart';
import 'widgets.dart';

String kindLabel(DeviceKind k) => switch (k) {
      DeviceKind.samsung => 'Samsung',
      DeviceKind.lg => 'LG webOS',
      DeviceKind.roku => 'Roku',
      DeviceKind.androidTv => 'Android / Google TV',
      DeviceKind.ir => 'IR',
    };

class WifiDiscoverScreen extends StatefulWidget {
  const WifiDiscoverScreen({super.key});

  @override
  State<WifiDiscoverScreen> createState() => _WifiDiscoverScreenState();
}

class _WifiDiscoverScreenState extends State<WifiDiscoverScreen> {
  final _found = <FoundTv>[];
  final _ipCtrl = TextEditingController();
  bool _scanning = false;
  double _progress = 0;
  String? _note;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _progress = 0;
      _found.clear();
      _note = null;
    });
    await TvDiscovery.scan(
      onFound: (t) {
        if (mounted) setState(() => _found.add(t));
      },
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _scanning = false;
      if (_found.isEmpty) {
        _note = tr(context,
            'No TV found. Make sure the TV is on and on the same Wi-Fi as this phone.',
            'Không tìm thấy TV. Kiểm tra TV đang bật và cùng mạng Wi-Fi với điện thoại.');
      }
    });
  }

  Future<void> _manual() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _note = tr(context, 'Checking $ip…', 'Đang kiểm tra $ip…'));
    final t = await TvDiscovery.probeIp(ip);
    if (!mounted) return;
    if (t == null) {
      setState(() => _note = tr(context, 'No supported TV at $ip.', 'Không có TV hỗ trợ tại $ip.'));
      return;
    }
    setState(() => _note = null);
    _pick(t);
  }

  Future<void> _pick(FoundTv t) async {
    final store = DeviceStore.instance;
    var d = store.findWifi(t.kind, t.ip);
    if (d == null) {
      d = SavedDevice(id: store.newId(), name: t.name, kind: t.kind, category: Cat.tv, ip: t.ip);
      await store.add(d);
    }
    if (!mounted) return;
    final saved = d;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvRemoteScreen(device: saved)));
  }

  @override
  Widget build(BuildContext context) {
    return LuxScaffold(
      title: tr(context, 'Smart TV over Wi-Fi', 'Smart TV qua Wi-Fi'),
      actions: [
        IconButton(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_scanning) ...[
            Center(child: _Radar(progress: _progress)),
            const SizedBox(height: 12),
            Center(
              child: Text(tr(context, 'Searching your network…', 'Đang tìm trong mạng…'),
                  style: const TextStyle(color: Lux.muted)),
            ),
            const SizedBox(height: 20),
          ],
          for (final t in _found)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LuxCard(
                onTap: () => _pick(t),
                child: Row(children: [
                  const IconBadge(Icons.tv_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${kindLabel(t.kind)} • ${t.ip}', style: const TextStyle(color: Lux.muted, fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Lux.gold),
                ]),
              ),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_note!, style: const TextStyle(color: Lux.goldLight)),
            ),
          SectionLabel(tr(context, 'Enter IP manually', 'Nhập IP thủ công')),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '192.168.1.23'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _manual, child: Text(tr(context, 'Connect', 'Kết nối'))),
          ]),
          const SizedBox(height: 22),
          Text(
            tr(context,
                'Supported: Android / Google TV, Samsung (2016+), LG webOS and Roku. Follow the pairing instructions on your TV.',
                'Hỗ trợ Android / Google TV, Samsung (2016+), LG webOS và Roku. Làm theo hướng dẫn ghép nối trên TV.'),
            style: const TextStyle(color: Lux.faint, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Radar extends StatefulWidget {
  const _Radar({required this.progress});
  final double progress;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          for (var i = 0; i < 3; i++)
            Builder(builder: (_) {
              final t = (_c.value + i / 3) % 1;
              return Container(
                width: 50 + 110 * t,
                height: 50 + 110 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Lux.gold.withValues(alpha: (1 - t) * 0.6), width: 1.2),
                ),
              );
            }),
          const IconBadge(Icons.wifi_rounded, size: 56),
        ]),
      ),
    );
  }
}

class TvRemoteScreen extends StatefulWidget {
  const TvRemoteScreen({super.key, required this.device});
  final SavedDevice device;

  @override
  State<TvRemoteScreen> createState() => _TvRemoteScreenState();
}

class _TvRemoteScreenState extends State<TvRemoteScreen> {
  late final TvLink _link;
  final _pin = TextEditingController();
  bool _pairing = false;
  bool _pinError = false;
  TvLinkState _state = TvLinkState.idle;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    _link = TvLink.create(widget.device.kind, widget.device.ip ?? '', (s, d) {
      if (mounted) {
        setState(() {
          _state = s;
          _detail = d;
        });
      }
    });
    _link.connect();
  }

  @override
  void dispose() {
    _pin.dispose();
    _link.close();
    super.dispose();
  }

  VoidCallback? _k(TvKey k) => _state == TvLinkState.connected ? () => _link.send(k) : null;

  Future<void> _submitPin(AndroidTvLink link) async {
    if (_pairing) return;
    final code = _pin.text.trim();
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(code)) {
      setState(() => _pinError = true);
      return;
    }
    setState(() {
      _pairing = true;
      _pinError = false;
    });
    final ok = await link.pair(code);
    if (!mounted) return;
    if (ok) _pin.clear();
    setState(() {
      _pairing = false;
      _pinError = !ok;
    });
  }

  String _statusText(BuildContext c) => switch (_state) {
        TvLinkState.idle || TvLinkState.connecting => tr(c, 'Connecting…', 'Đang kết nối…'),
        TvLinkState.waitingApproval => tr(c, 'Accept the request on your TV', 'Chọn "Cho phép" trên TV'),
        TvLinkState.connected => tr(c, 'Connected', 'Đã kết nối'),
        TvLinkState.denied => tr(c, 'The TV refused the connection', 'TV đã từ chối kết nối'),
        TvLinkState.closed => tr(c, 'Disconnected', 'Đã ngắt kết nối'),
        TvLinkState.error => tr(c, 'Can’t reach the TV — is it on?', 'Không kết nối được TV — TV đang bật?'),
      };

  @override
  Widget build(BuildContext context) {
    final ok = _state == TvLinkState.connected;
    final busy = _state == TvLinkState.connecting || _state == TvLinkState.idle;
    final link = _link;
    final androidTv = link is AndroidTvLink && _state == TvLinkState.waitingApproval ? link : null;
    final needsPin = androidTv != null;
    return LuxScaffold(
      title: widget.device.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0x0DFFFFFF),
              border: Border.all(color: ok ? const Color(0x554CC38A) : Lux.line),
            ),
            child: Row(children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ok ? Lux.jade : (busy ? Lux.gold : Lux.ruby),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    needsPin
                        ? tr(context, 'Enter the code shown on your TV', 'Nhập mã hiển thị trên TV')
                        : _statusText(context),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${kindLabel(widget.device.kind)} • ${widget.device.ip}'
                    '${_detail.isNotEmpty && !ok ? ' • $_detail' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Lux.muted, fontSize: 12),
                  ),
                ]),
              ),
              if (!ok && !busy && !needsPin)
                TextButton(
                  onPressed: () async {
                    await _link.close();
                    _link.connect();
                  },
                  child: Text(tr(context, 'Retry', 'Thử lại')),
                ),
            ]),
          ),
          if (androidTv != null) ...[
            const SizedBox(height: 16),
            LuxCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _pin,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enabled: !_pairing,
                  onSubmitted: (_) => _submitPin(androidTv),
                  decoration: InputDecoration(
                    labelText: tr(context, '6-character code', 'Mã 6 ký tự'),
                    errorText: _pinError
                        ? tr(context, 'Check the code shown on the TV', 'Kiểm tra lại mã trên TV')
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _pairing ? null : () => _submitPin(androidTv),
                  child: Text(tr(context, 'Pair TV', 'Ghép nối TV')),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RemoteKey(icon: Icons.power_settings_new_rounded, style: KeyStyle.power, onPressed: _k(TvKey.power)),
            RemoteKey(icon: Icons.input_rounded, onPressed: _k(TvKey.source)),
            RemoteKey(icon: Icons.volume_off_rounded, onPressed: _k(TvKey.mute)),
          ]),
          const SizedBox(height: 28),
          Center(
            child: DPad(
              onUp: _k(TvKey.up),
              onDown: _k(TvKey.down),
              onLeft: _k(TvKey.left),
              onRight: _k(TvKey.right),
              onOk: _k(TvKey.ok),
            ),
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RemoteKey(icon: Icons.arrow_back_rounded, onPressed: _k(TvKey.back)),
            RemoteKey(icon: Icons.home_rounded, onPressed: _k(TvKey.home)),
            RemoteKey(icon: Icons.menu_rounded, onPressed: _k(TvKey.menu)),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            RockerKey(label: 'VOL', onUp: _k(TvKey.volUp), onDown: _k(TvKey.volDown)),
            Column(children: [
              RemoteKey(icon: Icons.play_arrow_rounded, onPressed: _k(TvKey.play)),
              const SizedBox(height: 18),
              RemoteKey(icon: Icons.pause_rounded, onPressed: _k(TvKey.pause)),
            ]),
            RockerKey(
              label: 'CH',
              onUp: _k(TvKey.chUp),
              onDown: _k(TvKey.chDown),
              upIcon: Icons.keyboard_arrow_up_rounded,
              downIcon: Icons.keyboard_arrow_down_rounded,
            ),
          ]),
          if (!ok) ...[
            const SizedBox(height: 24),
            Text(
              tr(context,
                  'Tip: when the TV is fully off, Wi-Fi can’t wake it — add the same TV over infrared to turn it on.',
                  'Mẹo: khi TV tắt hẳn, Wi-Fi không bật được TV — hãy thêm TV này qua hồng ngoại để bật nguồn.'),
              style: const TextStyle(color: Lux.faint, fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
