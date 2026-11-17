import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../devices/device_store.dart';
import '../devices/share_codec.dart';
import '../l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shows a QR code another phone running Zapio can scan to copy [devices].
class ShareQrScreen extends StatelessWidget {
  const ShareQrScreen({super.key, required this.devices});
  final List<SavedDevice> devices;

  @override
  Widget build(BuildContext context) {
    final title = devices.length == 1
        ? devices.first.name
        : tr(context, '${devices.length} devices', '${devices.length} thiết bị');
    return LuxScaffold(
      title: tr(context, 'Share remote', 'Chia sẻ điều khiển'),
      body: FutureBuilder<String>(
        future: ShareCodec.encode(devices),
        builder: (context, snap) {
          final code = snap.data;
          if (code == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                tr(context, 'On the other phone: Zapio → Scan QR code',
                    'Trên điện thoại kia: mở Zapio → Quét mã QR'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Lux.muted),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [BoxShadow(color: Color(0x55D9B676), blurRadius: 40)],
                ),
                child: QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF111111)),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF111111),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              for (final d in devices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(categoryIcon(d.category), size: 18, color: Lux.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(d.name)),
                    Text(d.isWifi ? 'Wi-Fi' : 'IR', style: const TextStyle(color: Lux.muted, fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(tr(context, 'Copy as text', 'Sao chép dạng văn bản')),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr(context,
                        'Copied — paste it in Zapio on the other phone (Scan QR → Paste)',
                        'Đã sao chép — dán vào Zapio trên máy kia (Quét mã QR → Dán)')),
                  ));
                },
              ),
              const SizedBox(height: 12),
              Text(
                tr(context,
                    'Wi-Fi TVs will ask to pair again on the new phone.',
                    'TV Wi-Fi sẽ hỏi cho phép kết nối lại trên điện thoại mới.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Lux.faint, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Camera scanner for Zapio share codes (also accepts a pasted code).
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String? raw) async {
    if (_handled || raw == null) return;
    final store = DeviceStore.instance;
    final r = ShareCodec.decode(raw, store.newId);
    if (r == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Not a Zapio share code', 'Không phải mã chia sẻ của Zapio')),
      ));
      return;
    }
    _handled = true;
    HapticFeedback.mediumImpact();
    await _controller.stop();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'Add ${r.$1.length} devices?', 'Thêm ${r.$1.length} thiết bị?')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in r.$1)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(categoryIcon(d.category), color: Lux.gold),
              title: Text(d.name),
              subtitle: Text(Cat.label(c, d.category)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'Cancel', 'Hủy'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'Add', 'Thêm'))),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await ShareCodec.import(r.$1, r.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Added ${r.$1.length} devices', 'Đã thêm ${r.$1.length} thiết bị')),
      ));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      _handled = false;
      await _controller.start();
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _handle(data?.text);
  }

  @override
  Widget build(BuildContext context) {
    return LuxScaffold(
      title: tr(context, 'Scan QR code', 'Quét mã QR'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Text(
            tr(context, 'On the other phone open Zapio → long-press a device → Share. Point this camera at the code.',
                'Trên máy kia mở Zapio → nhấn giữ thiết bị → Chia sẻ. Hướng camera vào mã QR.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Lux.muted, height: 1.45),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      final v = b.rawValue;
                      if (v != null && v.startsWith(ShareCodec.prefix)) {
                        _handle(v);
                        return;
                      }
                    }
                  },
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Lux.gold, width: 2),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.content_paste_rounded),
            label: Text(tr(context, 'Paste code', 'Dán mã đã sao chép')),
            onPressed: _paste,
          ),
        ),
      ]),
    );
  }
}
