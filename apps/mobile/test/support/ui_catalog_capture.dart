// Opt-in, synthetic screenshots for design review; never contacts real accounts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const captureUiCatalog = bool.fromEnvironment('UI_CATALOG');
const _catalogVariant = String.fromEnvironment('UI_CATALOG_VARIANT', defaultValue: 'before');

Future<void> loadCatalogFonts() async {
  SharedPreferences.setMockInitialValues({});
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    await (FontLoader('InstrumentSans')
          ..addFont(rootBundle.load('assets/fonts/InstrumentSans-$weight.ttf')))
        .load();
  }
  for (final style in ['Regular', 'Fill', 'Bold']) {
    await (FontLoader('packages/phosphor_flutter/Phosphor$style')..addFont(
          rootBundle.load(
            'packages/phosphor_flutter/lib/fonts/Phosphor${style == 'Regular' ? '' : '-$style'}.ttf',
          ),
        ))
        .load();
  }
}

Future<void> captureCatalog(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../../.tools/ui-catalog/$_catalogVariant/$name.png'),
  );
}
