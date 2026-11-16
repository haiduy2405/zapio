import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wifi/samsung_tizen.dart';

class WifiHomeScreen extends StatefulWidget {
  const WifiHomeScreen({super.key});

  @override
  State<WifiHomeScreen> createState() => _WifiHomeScreenState();
}

class _WifiHomeScreenState extends State<WifiHomeScreen> {
  final _ipCtrl = TextEditingController();
  List<SamsungTv> _found = [];
  bool _scanning = false;
  double _progress = 0;
  String? _note;

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _progress = 0;
      _found = [];
      _note = null;
    });
    final tvs = await SamsungTizen.scan(onProgress: (d, t) {
      if (mounted) setState(() => _progress = t == 0 ? 1 : d / t);
    });
    if (!mounted) return;
    setState(() {
      _found = tvs;
      _scanning = false;
      _note = tvs.isEmpty
          ? 'Không tìm thấy TV Samsung. Kiểm tra TV đang bật và cùng mạng Wi-Fi.'
          : null;
    });
  }

  Future<void> _manual() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _note = 'Đang kiểm tra $ip…');
    final tv = await SamsungTizen.probe(ip, timeout: const Duration(seconds: 3));
    if (!mounted) return;
    if (tv == null) {
      setState(() => _note = 'Không phải TV Samsung Tizen, hoặc TV đang tắt.');
      return;
    }
    setState(() => _note = null);
    _open(tv);
  }

  void _open(SamsungTv tv) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SamsungRemoteScreen(tv: tv)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zapio • Wi-Fi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('TV Samsung (Tizen, 2016+)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.radar),
            label: Text(_scanning ? 'Đang quét…' : 'Quét mạng Wi-Fi'),
            onPressed: _scanning ? null : _scan,
          ),
          if (_scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
          ],
          const SizedBox(height: 12),
          for (final tv in _found)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tv),
                title: Text(tv.name),
                subtitle: Text('${tv.model ?? ''}  ${tv.ip}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(tv),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hoặc nhập IP của TV',
                  hintText: '192.168.1.23',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _manual, child: const Text('Kết nối')),
          ]),
          if (_note != null) ...[
            const SizedBox(height: 12),
            Text(_note!, style: const TextStyle(color: Colors.amberAccent)),
          ],
          const SizedBox(height: 24),
          const Text(
            'Mẹo: lần đầu kết nối, TV sẽ hiện hộp thoại "Cho phép" — chọn Cho phép. '
            'TV đang tắt hẳn thì Wi-Fi không bật được, hãy dùng nút nguồn ở tab Hồng ngoại.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class SamsungRemoteScreen extends StatefulWidget {
  const SamsungRemoteScreen({super.key, required this.tv});
  final SamsungTv tv;

  @override
  State<SamsungRemoteScreen> createState() => _SamsungRemoteScreenState();
}

class _SamsungRemoteScreenState extends State<SamsungRemoteScreen> {
  late final SamsungRemoteSession _session;
  TvLinkState _state = TvLinkState.idle;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    _session = SamsungRemoteSession(widget.tv.ip, onState: (s, d) {
      if (mounted) {
        setState(() {
          _state = s;
          _detail = d;
        });
      }
    });
    _session.connect();
  }

  @override
  void dispose() {
    _session.close();
    super.dispose();
  }

  void _key(String k) {
    HapticFeedback.lightImpact();
    _session.sendKey(k);
  }

  Widget _btn(IconData icon, String key, {String? label}) => Padding(
        padding: const EdgeInsets.all(6),
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(72, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _state == TvLinkState.connected ? () => _key(key) : null,
          child: label == null ? Icon(icon) : Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ok = _state == TvLinkState.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.tv.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: ok ? Colors.teal.shade900 : Colors.blueGrey.shade900,
            child: ListTile(
              leading: Icon(ok ? Icons.link : Icons.link_off),
              title: Text(_detail.isEmpty ? '…' : _detail),
              subtitle: Text(widget.tv.ip),
              trailing: ok
                  ? null
                  : TextButton(onPressed: _session.connect, child: const Text('Thử lại')),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _btn(Icons.power_settings_new, 'KEY_POWER'),
            _btn(Icons.home, 'KEY_HOME'),
            _btn(Icons.input, 'KEY_SOURCE'),
          ]),
          const SizedBox(height: 8),
          Center(child: _btn(Icons.keyboard_arrow_up, 'KEY_UP')),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _btn(Icons.keyboard_arrow_left, 'KEY_LEFT'),
            _btn(Icons.circle_outlined, 'KEY_ENTER', label: 'OK'),
            _btn(Icons.keyboard_arrow_right, 'KEY_RIGHT'),
          ]),
          Center(child: _btn(Icons.keyboard_arrow_down, 'KEY_DOWN')),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _btn(Icons.arrow_back, 'KEY_RETURN'),
            _btn(Icons.volume_off, 'KEY_MUTE'),
            _btn(Icons.menu, 'KEY_MENU'),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(children: [
              _btn(Icons.volume_up, 'KEY_VOLUP'),
              _btn(Icons.volume_down, 'KEY_VOLDOWN'),
            ]),
            Column(children: [
              _btn(Icons.play_arrow, 'KEY_PLAY'),
              _btn(Icons.pause, 'KEY_PAUSE'),
            ]),
            Column(children: [
              _btn(Icons.keyboard_arrow_up, 'KEY_CHUP', label: 'CH +'),
              _btn(Icons.keyboard_arrow_down, 'KEY_CHDOWN', label: 'CH −'),
            ]),
          ]),
        ],
      ),
    );
  }
}
