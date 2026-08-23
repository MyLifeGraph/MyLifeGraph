import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/settings/application/account_export_saver.dart';

void main() {
  test('Android and iOS use the supported native share handoff', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        usesMobileAccountExportShareSheet(isWeb: false, platform: platform),
        isTrue,
        reason: 'platform=$platform',
      );
    }
  });

  test('web and desktop keep their download/save-location path', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        usesMobileAccountExportShareSheet(isWeb: true, platform: platform),
        isFalse,
      );
    }
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        usesMobileAccountExportShareSheet(isWeb: false, platform: platform),
        isFalse,
      );
    }
  });
}
