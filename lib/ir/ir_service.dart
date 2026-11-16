import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'encoders.dart';
import 'ir_file.dart';

/// Thin wrapper over the native "zapio/ir" channel (Android ConsumerIrManager).
class IrService {
  IrService._();
  static final instance = IrService._();

  static const _ch = MethodChannel('zapio/ir');

  Future<bool> hasEmitter() async {
    try {
      return await _ch.invokeMethod<bool>('hasEmitter') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// List of [min, max] carrier ranges in Hz.
  Future<List<List<int>>> carrierFrequencies() async {
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('carrierFrequencies');
      return [
        for (final e in r ?? const [])
          [for (final v in (e as List)) (v as num).toInt()]
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> transmitFrame(IrFrame f) async {
    await _ch.invokeMethod('transmit', {
      'frequency': f.frequency,
      'pattern': Int32List.fromList(f.pattern),
    });
  }

  /// Encodes and sends; returns the frame that was sent.
  Future<IrFrame> send(IrSignal s) async {
    final f = encodeSignal(s);
    await transmitFrame(f);
    return f;
  }
}
