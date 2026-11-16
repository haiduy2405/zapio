import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'tv_link.dart';

/// LG webOS TV (2014+) over the SSAP WebSocket API.
///
/// Connects to wss://IP:3001 (newer firmware) or ws://IP:3000, registers with
/// pairingType PROMPT (TV shows an accept dialog the first time) and stores
/// the returned client-key. Navigation keys go through the pointer-input
/// socket the TV hands out via getPointerInputSocket.
class LgLink extends TvLink {
  LgLink(super.ip, super.onState);

  WebSocket? _ws;
  WebSocket? _pointer;
  int _seq = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  String get _keyPref => 'lg_client_key_$ip';

  static HttpClient _insecure() =>
      HttpClient()..badCertificateCallback = (cert, host, port) => true;

  static const _permissions = [
    'LAUNCH', 'LAUNCH_WEBAPP', 'APP_TO_APP', 'CONTROL_AUDIO', 'CONTROL_DISPLAY',
    'CONTROL_INPUT_JOYSTICK', 'CONTROL_INPUT_MEDIA_RECORDING',
    'CONTROL_INPUT_MEDIA_PLAYBACK', 'CONTROL_INPUT_TV', 'CONTROL_POWER',
    'READ_APP_STATUS', 'READ_CURRENT_CHANNEL', 'READ_INPUT_DEVICE_LIST',
    'READ_NETWORK_STATE', 'READ_RUNNING_APPS', 'READ_TV_CHANNEL_LIST',
    'WRITE_NOTIFICATION_TOAST', 'READ_POWER_STATE', 'READ_COUNTRY_INFO',
    'CONTROL_MOUSE_AND_KEYBOARD', 'CONTROL_INPUT_TEXT',
  ];

  @override
  Future<void> connect() async {
    onState(TvLinkState.connecting, '');
    try {
      _ws = await WebSocket.connect('wss://$ip:3001', customClient: _insecure())
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        _ws = await WebSocket.connect('ws://$ip:3000').timeout(const Duration(seconds: 5));
      } catch (e) {
        onState(TvLinkState.error, '$e');
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyPref);

    _ws!.listen(
      (msg) => _onMessage(msg as String, prefs),
      onDone: () => onState(TvLinkState.closed, ''),
      onError: (Object e) => onState(TvLinkState.error, '$e'),
    );
    _ws!.add(jsonEncode({
      'type': 'register',
      'id': 'register_0',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        if (key != null) 'client-key': key,
        'manifest': {
          'manifestVersion': 1,
          'appVersion': '1.0',
          'permissions': _permissions,
        },
      },
    }));
  }

  void _onMessage(String msg, SharedPreferences prefs) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(msg) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = j['id']?.toString();
    final payload = (j['payload'] as Map<String, dynamic>?) ?? const {};
    if (id == 'register_0') {
      switch (j['type']) {
        case 'response':
          if (payload['pairingType'] == 'PROMPT') {
            onState(TvLinkState.waitingApproval, '');
          }
        case 'registered':
          final k = payload['client-key'];
          if (k != null) prefs.setString(_keyPref, k.toString());
          onState(TvLinkState.connected, '');
          _openPointer();
        case 'error':
          onState(TvLinkState.denied, j['error']?.toString() ?? '');
      }
      return;
    }
    final c = id == null ? null : _pending.remove(id);
    if (c != null && !c.isCompleted) c.complete(j);
  }

  Future<Map<String, dynamic>?> _request(String uri, [Map<String, dynamic>? payload]) async {
    final ws = _ws;
    if (ws == null) return null;
    final id = 'req_${_seq++}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    ws.add(jsonEncode({
      'type': 'request',
      'id': id,
      'uri': uri,
      if (payload != null) 'payload': payload,
    }));
    try {
      return await c.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      _pending.remove(id);
      return null;
    }
  }

  Future<void> _openPointer() async {
    final r = await _request('ssap://com.webos.service.networkinput/getPointerInputSocket');
    final path = (r?['payload'] as Map<String, dynamic>?)?['socketPath']?.toString();
    if (path == null) return;
    try {
      _pointer = await WebSocket.connect(path, customClient: _insecure())
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static const _buttons = {
    TvKey.up: 'UP', TvKey.down: 'DOWN', TvKey.left: 'LEFT', TvKey.right: 'RIGHT',
    TvKey.ok: 'ENTER', TvKey.back: 'BACK', TvKey.home: 'HOME', TvKey.menu: 'MENU',
    TvKey.volUp: 'VOLUMEUP', TvKey.volDown: 'VOLUMEDOWN', TvKey.mute: 'MUTE',
    TvKey.chUp: 'CHANNELUP', TvKey.chDown: 'CHANNELDOWN',
    TvKey.play: 'PLAY', TvKey.pause: 'PAUSE',
  };

  @override
  Future<void> send(TvKey key) async {
    switch (key) {
      case TvKey.power:
        await _request('ssap://system/turnOff');
        return;
      case TvKey.source:
        await _request('ssap://tv/getExternalInputList');
        return;
      default:
        break;
    }
    final b = _buttons[key];
    if (b == null) return;
    final p = _pointer;
    if (p != null) {
      p.add('type:button\nname:$b\n\n');
      return;
    }
    // No pointer socket: fall back to SSAP for the keys that have one.
    switch (key) {
      case TvKey.volUp:
        await _request('ssap://audio/volumeUp');
      case TvKey.volDown:
        await _request('ssap://audio/volumeDown');
      case TvKey.chUp:
        await _request('ssap://tv/channelUp');
      case TvKey.chDown:
        await _request('ssap://tv/channelDown');
      case TvKey.play:
        await _request('ssap://media.controls/play');
      case TvKey.pause:
        await _request('ssap://media.controls/pause');
      default:
        break;
    }
  }

  @override
  Future<void> close() async {
    await _pointer?.close();
    await _ws?.close();
    _pointer = null;
    _ws = null;
  }
}
