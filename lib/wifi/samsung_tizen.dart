import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// A Samsung Smart TV (Tizen, 2016+) found on the local network.
class SamsungTv {
  SamsungTv({required this.ip, required this.name, this.model});
  final String ip;
  final String name;
  final String? model;
}

/// Discovery + remote-control client for Samsung Tizen TVs.
///
/// Discovery: GET http://IP:8001/api/v2/ returns device info.
/// Control:   WebSocket wss://IP:8002/api/v2/channels/samsung.remote.control
///            (falls back to ws://IP:8001 on older firmware). The first
///            connection shows an "Allow" prompt on the TV; the TV then
///            returns a token that we store for silent reconnects.
class SamsungTizen {
  static const appName = 'Zapio';

  static Future<SamsungTv?> probe(String ip,
      {Duration timeout = const Duration(milliseconds: 900)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip:8001/api/v2/'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final j = jsonDecode(body) as Map<String, dynamic>;
      final d = (j['device'] as Map<String, dynamic>?) ?? const {};
      return SamsungTv(
        ip: ip,
        name: (d['name'] ?? j['name'] ?? 'Samsung TV').toString(),
        model: d['modelName']?.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// IPv4 /24 prefixes of this phone's network interfaces (e.g. "192.168.1").
  static Future<List<String>> localPrefixes() async {
    final out = <String>{};
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (a.isLoopback) continue;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          out.add(ip.substring(0, ip.lastIndexOf('.')));
        }
      }
    }
    return out.toList();
  }

  /// Sweeps every /24 the phone is on. [onProgress] gets (done, total).
  static Future<List<SamsungTv>> scan(
      {void Function(int done, int total)? onProgress}) async {
    final prefixes = await localPrefixes();
    final ips = [
      for (final p in prefixes)
        for (var i = 1; i < 255; i++) '$p.$i'
    ];
    final found = <SamsungTv>[];
    var done = 0;
    const batch = 48;
    for (var i = 0; i < ips.length; i += batch) {
      final chunk = ips.sublist(i, math.min(i + batch, ips.length));
      final res = await Future.wait(chunk.map((ip) => probe(ip)));
      found.addAll(res.whereType<SamsungTv>());
      done += chunk.length;
      onProgress?.call(done, ips.length);
    }
    return found;
  }
}

enum TvLinkState { idle, connecting, waitingApproval, connected, denied, closed, error }

class SamsungRemoteSession {
  SamsungRemoteSession(this.ip, {required this.onState});

  final String ip;
  final void Function(TvLinkState state, String detail) onState;
  WebSocket? _ws;

  String get _tokenKey => 'samsung_token_$ip';

  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final name = base64.encode(utf8.encode(SamsungTizen.appName));
    final path = '/api/v2/channels/samsung.remote.control?name=$name'
        '${token != null ? '&token=$token' : ''}';

    onState(TvLinkState.connecting, 'Đang kết nối…');
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true; // TV uses a self-signed cert
    try {
      _ws = await WebSocket.connect('wss://$ip:8002$path', customClient: client)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Older Tizen firmware (2016–2017): plain ws on 8001.
      try {
        _ws = await WebSocket.connect('ws://$ip:8001$path')
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        onState(TvLinkState.error, 'Không kết nối được: $e');
        return;
      }
    }
    if (token == null) {
      onState(TvLinkState.waitingApproval, 'Bấm "Cho phép" trên TV');
    }
    _ws!.listen(
      (msg) {
        try {
          final j = jsonDecode(msg as String) as Map<String, dynamic>;
          switch (j['event']) {
            case 'ms.channel.connect':
              final t = (j['data'] as Map<String, dynamic>?)?['token'];
              if (t != null) prefs.setString(_tokenKey, t.toString());
              onState(TvLinkState.connected, 'Đã kết nối');
              break;
            case 'ms.channel.unauthorized':
              onState(TvLinkState.denied, 'TV đã từ chối kết nối');
              break;
            case 'ms.channel.timeOut':
              onState(TvLinkState.denied, 'Hết thời gian chờ cho phép trên TV');
              break;
          }
        } catch (_) {}
      },
      onDone: () => onState(TvLinkState.closed, 'Đã ngắt kết nối'),
      onError: (Object e) => onState(TvLinkState.error, 'Lỗi: $e'),
    );
  }

  /// Sends a key such as KEY_VOLUP, KEY_POWER, KEY_HOME, KEY_ENTER.
  void sendKey(String key) {
    _ws?.add(jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': key,
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      },
    }));
  }

  Future<void> close() async {
    await _ws?.close();
    _ws = null;
  }
}
