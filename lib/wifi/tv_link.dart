import '../devices/device_store.dart';
import 'android_tv.dart';
import 'lg_webos.dart';
import 'roku.dart';
import 'samsung_tizen.dart';

/// Remote keys every Wi-Fi TV implementation understands.
enum TvKey {
  power, volUp, volDown, mute, chUp, chDown,
  up, down, left, right, ok, back, home, menu,
  play, pause, source,
}

enum TvLinkState { idle, connecting, waitingApproval, connected, denied, closed, error }

typedef TvStateCallback = void Function(TvLinkState state, String detail);

/// Common interface for Wi-Fi TV control.
abstract class TvLink {
  TvLink(this.ip, this.onState);
  final String ip;
  final TvStateCallback onState;

  Future<void> connect();
  Future<void> send(TvKey key);
  Future<void> close();

  static TvLink create(DeviceKind kind, String ip, TvStateCallback onState) =>
      switch (kind) {
        DeviceKind.samsung => SamsungLink(ip, onState),
        DeviceKind.lg => LgLink(ip, onState),
        DeviceKind.roku => RokuLink(ip, onState),
        DeviceKind.androidTv => AndroidTvLink(ip, onState),
        DeviceKind.ir => throw ArgumentError('IR devices have no TvLink'),
      };
}
