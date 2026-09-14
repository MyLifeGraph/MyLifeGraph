import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushPlatform {
  const PushPlatform();
  static const channel = MethodChannel('com.mylifegraph.app/push');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<T?> call<T>(String method, [Map<String, dynamic>? args]) =>
      channel.invokeMethod<T>(method, args);
  static Future<void> clearForSignOut() async {
    if (!supported) return;
    try {
      await channel
          .invokeMethod<void>('clear')
          .timeout(const Duration(seconds: 10));
    } on MissingPluginException {
      // Older test/platform runners have no optional push adapter.
    } on PlatformException {
      // Native code clears local receipt permission before token deletion.
    } on TimeoutException {
      // Token cleanup may time out offline; the native local switch is off first.
    }
  }
}
