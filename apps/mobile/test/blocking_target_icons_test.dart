import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_target_list.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_website_icon.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_website_marks.dart';

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  testWidgets(
    'native app PNG bytes stay bound to package after selection/reorder',
    (t) async {
      final alpha = (await t.runAsync(() => _png(Colors.blue)))!;
      final beta = (await t.runAsync(() => _png(Colors.orange)))!;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.liquidGlass,
          home: Scaffold(
            body: BlockingPlanEditor(
              plan: const BlockingPlan(
                id: 'icons',
                name: 'Icons',
                focus: true,
                apps: {'alpha'},
                sites: {'instagram.com'},
              ),
              catalog: [
                {
                  'packageName': 'alpha',
                  'label': 'Alpha',
                  'icon': base64Encode(alpha),
                },
                {
                  'packageName': 'beta',
                  'label': 'Beta',
                  'icon': base64Encode(beta),
                },
                {
                  'packageName': 'missing',
                  'label': 'Missing',
                  'icon': 'invalid-base64',
                },
              ],
              usageGranted: true,
              websiteAllowed: true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('blocking-editor-tab-1')));
      await t.pumpAndSettle();
      Image appImage(String id) => t.widget<Image>(
        find.descendant(
          of: find.byKey(ValueKey('blocking-app-$id')),
          matching: find.byType(Image),
        ),
      );
      expect((appImage('alpha').image as MemoryImage).bytes, alpha);
      expect((appImage('beta').image as MemoryImage).bytes, beta);
      expect(appImage('alpha').width, 32);
      expect(appImage('alpha').height, 32);
      expect(appImage('alpha').errorBuilder, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('blocking-app-missing')),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('blocking-app-beta')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('blocking-app-alpha')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds,
        ['beta', 'alpha', 'missing'],
      );
      expect((appImage('alpha').image as MemoryImage).bytes, alpha);
      expect((appImage('beta').image as MemoryImage).bytes, beta);
      await t.tap(find.byKey(const ValueKey('blocking-editor-tab-2')));
      await t.pumpAndSettle();
      final original = t
          .widget<BlockingTargetList>(find.byType(BlockingTargetList))
          .orderedIds;
      await t.tap(find.byKey(const ValueKey('blocking-site-x.com')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .take(2),
        ['instagram.com', 'x.com'],
      );
      await t.tap(find.byKey(const ValueKey('blocking-site-x.com')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds,
        original,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final theme in [
    AppTheme.liquidGlass,
    AppTheme.dark,
    AppTheme.light,
    AppTheme.space,
  ]) {
    testWidgets(
      'bundled brand paths render at unchanged 24px on ${theme.brightness}/${theme.scaffoldBackgroundColor}',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Row(
                children: [
                  for (final host in blockingWebsiteMarks.keys)
                    blockingWebsiteIcon(host),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(SvgPicture), findsNWidgets(6));
        for (final icon in t.widgetList<SvgPicture>(find.byType(SvgPicture))) {
          expect(icon.width, 24);
          expect(icon.height, 24);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  test('exact hosts and real subdomains only; no guessed logos', () {
    for (final host in blockingWebsiteMarks.keys) {
      expect(
        blockingWebsiteIcon('www.${host.toUpperCase()}'),
        isA<SvgPicture>(),
      );
      expect(blockingWebsiteIcon('$host.attacker.example'), isA<Icon>());
      expect(blockingWebsiteIcon('not$host'), isA<Icon>());
    }
    expect(blockingWebsiteIcon('unknown.example'), isA<Icon>());
  });
}
