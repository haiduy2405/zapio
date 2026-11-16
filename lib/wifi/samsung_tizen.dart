import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'tv_link.dart';

/// Samsung Smart TV (Tizen, 2016+).
///
/// Info:    GET http://IP:8001/api/v2/
/// Control: WebSocket wss://IP:8002/api/v2/channels/samsung.remote.control
///          (falls back to ws://IP:8001 on older firmware). The first
///          connection shows an "Allow" prompt on the TV; the returned token
///          is stored for silent reconnects.
class SamsungLink extends TvLink {
  SamsungLink(super.ip, super.onState);

  static const appName = 'Zapio';
  WebSocket? _ws;

  String get _tokenKey => 'samsung_token_$ip';

  /// Returns the TV name if [ip] is a Samsung Tizen TV, else null.
  static Future<String?> probe(String ip,
      {Duration timeout = const Duration(milliseconds: 900)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:8001/api/v2/')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final j = jsonDecode(body) as Map<String, dynamic>;
      final d = (j['device'] as Map<String, dynamic>?) ?? const {};
      return (d['name'] ?? j['name'] ?? 'Samsung TV').toString();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final name = base64.encode(utf8.encode(appName));
    final path = '/api/v2/channels/samsung.remote.control?name=$name'
        '${token != null ? '&token=$token' : ''}';

    onState(TvLinkState.connecting, '');
    final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    try {
      _ws = await WebSocket.connect('wss://$ip:8002$path', customClient: client)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      try {
        _ws = await WebSocket.connect('ws://$ip:8001$path').timeout(const Duration(seconds: 6));
      } catch (e) {
        onState(TvLinkState.error, '$e');
        return;
      }
    }
    if (token == null) onState(TvLinkState.waitingApproval, '');
    _ws!.listen(
      (msg) {
        try {
          final j = jsonDecode(msg as String) as Map<String, dynamic>;
          switch (j['event']) {
            case 'ms.channel.connect':
              final t = (j['data'] as Map<String, dynamic>?)?['token'];
              if (t != null) prefs.setString(_tokenKey, t.toString());
              onState(TvLinkState.connected, '');
            case 'ms.channel.unauthorized':
            case 'ms.channel.timeOut':
              onState(TvLinkState.denied, '');
          }
        } catch (_) {}
      },
      onDone: () => onState(TvLinkState.closed, ''),
      onError: (Object e) => onState(TvLinkState.error, '$e'),
    );
  }

  static const _keys = {
    TvKey.power: 'KEY_POWER', TvKey.volUp: 'KEY_VOLUP', TvKey.volDown: 'KEY_VOLDOWN',
    TvKey.mute: 'KEY_MUTE', TvKey.chUp: 'KEY_CHUP', TvKey.chDown: 'KEY_CHDOWN',
    TvKey.up: 'KEY_UP', TvKey.down: 'KEY_DOWN', TvKey.left: 'KEY_LEFT',
    TvKey.right: 'KEY_RIGHT', TvKey.ok: 'KEY_ENTER', TvKey.back: 'KEY_RETURN',
    TvKey.home: 'KEY_HOME', TvKey.menu: 'KEY_MENU', TvKey.play: 'KEY_PLAY',
    TvKey.pause: 'KEY_PAUSE', TvKey.source: 'KEY_SOURCE',
  };

  @override
  Future<void> send(TvKey key) async {
    _ws?.add(jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': _keys[key],
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      },
    }));
  }

  @override
  Future<void> close() async {
    await _ws?.close();
    _ws = null;
  }
}
