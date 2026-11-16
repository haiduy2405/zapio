import 'package:flutter/material.dart';

import '../devices/device_store.dart';
import '../l10n.dart';
import '../wifi/discovery.dart';
import '../wifi/tv_link.dart';
import 'widgets.dart';

String kindLabel(DeviceKind k) => switch (k) {
      DeviceKind.samsung => 'Samsung',
      DeviceKind.lg => 'LG webOS',
      DeviceKind.roku => 'Roku',
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
    setState(() => _note = '…');
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
      d = SavedDevice(
        id: store.newId(),
        name: t.name,
        kind: t.kind,
        category: Cat.tv,
        ip: t.ip,
      );
      await store.add(d);
    }
    if (!mounted) return;
    final saved = d;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvRemoteScreen(device: saved)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Smart TV over Wi-Fi', 'Smart TV qua Wi-Fi')),
        actions: [
          IconButton(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_scanning) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 8),
            Text(tr(context, 'Searching your network…', 'Đang tìm trong mạng…'),
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 8),
          ],
          for (final t in _found)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tv, size: 32),
                title: Text(t.name),
                subtitle: Text('${kindLabel(t.kind)} • ${t.ip}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pick(t),
              ),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_note!, style: const TextStyle(color: Colors.amberAccent)),
            ),
          const SizedBox(height: 24),
          Text(tr(context, 'Or enter the TV’s IP address', 'Hoặc nhập địa chỉ IP của TV'),
              style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '192.168.1.23',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _manual,
              child: Text(tr(context, 'Connect', 'Kết nối')),
            ),
          ]),
          const SizedBox(height: 24),
          Text(
            tr(context,
                'Supported: Samsung (2016+), LG webOS, Roku. The first time, accept the request shown on the TV.',
                'Hỗ trợ: Samsung (2016+), LG webOS, Roku. Lần đầu kết nối, chọn "Cho phép" trên TV.'),
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
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
    _link.close();
    super.dispose();
  }

  VoidCallback? _k(TvKey k) => _state == TvLinkState.connected ? () => _link.send(k) : null;

  String _statusText(BuildContext c) => switch (_state) {
        TvLinkState.idle || TvLinkState.connecting => tr(c, 'Connecting…', 'Đang kết nối…'),
        TvLinkState.waitingApproval =>
          tr(c, 'Accept the request on your TV', 'Chọn "Cho phép" trên TV'),
        TvLinkState.connected => tr(c, 'Connected', 'Đã kết nối'),
        TvLinkState.denied => tr(c, 'The TV refused the connection', 'TV đã từ chối kết nối'),
        TvLinkState.closed => tr(c, 'Disconnected', 'Đã ngắt kết nối'),
        TvLinkState.error => tr(c, 'Can’t reach the TV (is it on?)', 'Không kết nối được TV (TV đang bật?)'),
      };

  @override
  Widget build(BuildContext context) {
    final ok = _state == TvLinkState.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            color: ok ? Colors.teal.shade900 : Colors.blueGrey.shade900,
            child: ListTile(
              leading: Icon(ok ? Icons.wifi : Icons.wifi_off),
              title: Text(_statusText(context)),
              subtitle: Text(
                '${kindLabel(widget.device.kind)} • ${widget.device.ip}'
                '${_detail.isNotEmpty && !ok ? '\n$_detail' : ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ok || _state == TvLinkState.connecting
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await _link.close();
                        _link.connect();
                      },
                      child: Text(tr(context, 'Retry', 'Thử lại')),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RemoteKey(icon: Icons.power_settings_new, color: Colors.red.shade800, onPressed: _k(TvKey.power)),
            RemoteKey(icon: Icons.input, onPressed: _k(TvKey.source)),
            RemoteKey(icon: Icons.volume_off, onPressed: _k(TvKey.mute)),
          ]),
          const SizedBox(height: 24),
          Center(
            child: DPad(
              onUp: _k(TvKey.up),
              onDown: _k(TvKey.down),
              onLeft: _k(TvKey.left),
              onRight: _k(TvKey.right),
              onOk: _k(TvKey.ok),
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RemoteKey(icon: Icons.arrow_back, onPressed: _k(TvKey.back)),
            RemoteKey(icon: Icons.home_outlined, onPressed: _k(TvKey.home)),
            RemoteKey(icon: Icons.menu, onPressed: _k(TvKey.menu)),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            RockerKey(label: 'VOL', onUp: _k(TvKey.volUp), onDown: _k(TvKey.volDown)),
            Column(children: [
              RemoteKey(icon: Icons.play_arrow, onPressed: _k(TvKey.play)),
              const SizedBox(height: 18),
              RemoteKey(icon: Icons.pause, onPressed: _k(TvKey.pause)),
            ]),
            RockerKey(
              label: 'CH',
              onUp: _k(TvKey.chUp),
              onDown: _k(TvKey.chDown),
              upIcon: Icons.keyboard_arrow_up,
              downIcon: Icons.keyboard_arrow_down,
            ),
          ]),
          if (!ok) ...[
            const SizedBox(height: 20),
            Text(
              tr(context,
                  'Tip: when the TV is fully off, Wi-Fi control can’t wake it — add the same TV over IR to turn it on.',
                  'Mẹo: khi TV tắt hẳn, Wi-Fi không bật được TV — hãy thêm TV này qua hồng ngoại để bật nguồn.'),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
