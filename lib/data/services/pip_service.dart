import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service managing Picture-in-Picture (PiP) window mode.
class PipService {
  static const MethodChannel _channel = MethodChannel('io.github.clubanderson.clubtivi/pip');

  final ValueNotifier<bool> isInPipNotifier = ValueNotifier<bool>(false);

  bool get isInPip => isInPipNotifier.value;

  PipService() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onPipModeChanged') {
          final inPip = call.arguments as bool? ?? false;
          isInPipNotifier.value = inPip;
        }
      });
    }
  }

  /// Checks if Picture-in-Picture is supported on the current Android device.
  Future<bool> isPipSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isPipSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enters Picture-in-Picture floating mode with the given aspect ratio.
  Future<bool> enterPip({int aspectNumerator = 16, int aspectDenominator = 9}) async {
    if (!Platform.isAndroid) return false;
    try {
      final success = await _channel.invokeMethod<bool>('enterPip', {
        'aspectNumerator': aspectNumerator,
        'aspectDenominator': aspectDenominator,
      });
      if (success == true) {
        isInPipNotifier.value = true;
      }
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Refreshes whether the app is currently in PiP mode.
  Future<bool> checkInPip() async {
    if (!Platform.isAndroid) return false;
    try {
      final inPip = await _channel.invokeMethod<bool>('isInPip');
      final val = inPip ?? false;
      isInPipNotifier.value = val;
      return val;
    } catch (_) {
      return false;
    }
  }
}

final pipServiceProvider = Provider<PipService>((ref) {
  return PipService();
});
