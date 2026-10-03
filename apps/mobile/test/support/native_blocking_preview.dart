import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supplies the platform surface only; blocking commands still use each test's
/// explicit gateway. These widget tests do not execute the Android renderer.
void stubNativeBlockingPreview() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
    call,
  ) async {
    if (call.method == 'create') return 0;
    if (call.method == 'resize') {
      final args = call.arguments as Map;
      return {'width': args['width'], 'height': args['height']};
    }
    return null;
  });
}
