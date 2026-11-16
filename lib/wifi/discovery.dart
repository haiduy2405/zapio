import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../devices/device_store.dart';
import 'roku.dart';
import 'samsung_tizen.dart';

class FoundTv {
  FoundTv(this.kind, this.ip, this.name);
  final DeviceKind kind;
  final String ip;
  final String name;
  String get key => '${kind.name}@$ip';
}

/// Finds Samsung, LG and Roku TVs on the LAN:
/// 1. SSDP M-SEARCH (fast, finds all three when multicast works);
/// 2. a /24 sweep of Samsung's :8001 and Roku's :8060 as a fallback.
class TvDiscovery {
  static const _searchTargets = [
    'ssdp:all',
    'roku:ecp',
    'urn:lge-com:service:webos-second-screen:1',
    'urn:samsung.com:device:RemoteControlReceiver:1',
    'urn:dial-multiscreen-org:service:dial:1',
  ];

  static Future<List<FoundTv>> scan({
    void Function(FoundTv tv)? onFound,
    void Function(double progress)? onProgress,
  }) async {
    final found = <String, FoundTv>{};
    void add(FoundTv t) {
      if (found.containsKey(t.key)) return;
      found[t.key] = t;
      onFound?.call(t);
    }

    await Future.wait([
      _ssdp(add),
      _sweep(add, onProgress),
    ]);
    return found.values.toList();
  }

  static Future<void> _ssdp(void Function(FoundTv) add) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final seen = <String>{};
      final sub = sock.listen((ev) async {
        if (ev != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final ip = dg.address.address;
        final h = text.toLowerCase();
        if (h.contains('roku')) {
          if (seen.add('roku@$ip')) {
            final n = await RokuLink.probe(ip, timeout: const Duration(seconds: 2));
            if (n != null) add(FoundTv(DeviceKind.roku, ip, n));
          }
        } else if (h.contains('webos') || h.contains('lge-com') || h.contains('lg smart')) {
          if (seen.add('lg@$ip')) add(FoundTv(DeviceKind.lg, ip, await _lgName(text, ip)));
        } else if (h.contains('samsung')) {
          if (seen.add('samsung@$ip')) {
            final n = await SamsungLink.probe(ip, timeout: const Duration(seconds: 2));
            if (n != null) add(FoundTv(DeviceKind.samsung, ip, n));
          }
        }
      });
      final target = InternetAddress('239.255.255.250');
      for (var round = 0; round < 2; round++) {
        for (final st in _searchTargets) {
          final msg = 'M-SEARCH * HTTP/1.1\r\n'
              'HOST: 239.255.255.250:1900\r\n'
              'MAN: "ssdp:discover"\r\n'
              'MX: 2\r\n'
              'ST: $st\r\n\r\n';
          sock.send(utf8.encode(msg), target, 1900);
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      await sub.cancel();
    } catch (_) {
      // Multicast blocked on this network: the sweep still runs.
    } finally {
      sock?.close();
    }
  }

  static Future<String> _lgName(String ssdpReply, String ip) async {
    final loc = RegExp(r'^location:\s*(\S+)', caseSensitive: false, multiLine: true)
        .firstMatch(ssdpReply)
        ?.group(1);
    if (loc != null) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      try {
        final req = await client.getUrl(Uri.parse(loc)).timeout(const Duration(seconds: 2));
        final res = await req.close().timeout(const Duration(seconds: 2));
        final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
        final n = RegExp('<friendlyName>([^<]*)</friendlyName>').firstMatch(body)?.group(1);
        if (n != null && n.trim().isNotEmpty) return n.trim();
      } catch (_) {
      } finally {
        client.close(force: true);
      }
    }
    return 'LG TV';
  }

  /// IPv4 /24 prefixes of this phone's interfaces (e.g. "192.168.1").
  static Future<List<String>> localPrefixes() async {
    final out = <String>{};
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
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

  static Future<void> _sweep(
      void Function(FoundTv) add, void Function(double)? onProgress) async {
    final prefixes = await localPrefixes();
    final ips = [
      for (final p in prefixes)
        for (var i = 1; i < 255; i++) '$p.$i'
    ];
    const batch = 48;
    for (var i = 0; i < ips.length; i += batch) {
      final chunk = ips.sublist(i, math.min(i + batch, ips.length));
      await Future.wait(chunk.map((ip) async {
        final s = await SamsungLink.probe(ip);
        if (s != null) add(FoundTv(DeviceKind.samsung, ip, s));
        final r = await RokuLink.probe(ip, timeout: const Duration(milliseconds: 600));
        if (r != null) add(FoundTv(DeviceKind.roku, ip, r));
      }));
      onProgress?.call(math.min(1, (i + batch) / ips.length));
    }
    onProgress?.call(1);
  }

  /// Manual entry: try each protocol on [ip].
  static Future<FoundTv?> probeIp(String ip) async {
    final s = await SamsungLink.probe(ip, timeout: const Duration(seconds: 3));
    if (s != null) return FoundTv(DeviceKind.samsung, ip, s);
    final r = await RokuLink.probe(ip, timeout: const Duration(seconds: 3));
    if (r != null) return FoundTv(DeviceKind.roku, ip, r);
    if (await _portOpen(ip, 3000) || await _portOpen(ip, 3001)) {
      return FoundTv(DeviceKind.lg, ip, 'LG TV');
    }
    return null;
  }

  static Future<bool> _portOpen(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
