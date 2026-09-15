import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/core/preferences/assistant_language.dart';
import 'package:my_life_graph/composition/widgets/assistant_language_button.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'English default and independent saved choices survive a new instance',
    () async {
      final coach = AssistantLanguage('coach');
      await coach.ready;
      expect(coach.value, 'en');
      expect(await coach.toggle(), isTrue);
      coach.dispose();
      final reopened = AssistantLanguage('coach');
      final capture = AssistantLanguage('capture');
      addTearDown(reopened.dispose);
      addTearDown(capture.dispose);
      await Future.wait([reopened.ready, capture.ready]);
      expect(reopened.value, 'de');
      expect(capture.value, 'en');
    },
  );

  test('English wire is unchanged and German names its additive extension', () {
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    expect(CoachRequest(requestId: id, message: 'Hello').toJson(), {
      'contract_version': 'coach-request-v4',
      'request_id': id,
      'message': 'Hello',
    });
    expect(
      CoachRequest(
        requestId: id,
        message: 'Hallo',
        responseLanguage: 'de',
      ).toJson(),
      {
        'contract_version': 'coach-request-v4',
        'request_id': id,
        'message': 'Hallo',
        'response_language': 'de',
        'language_contract': 'coach-language-v1',
      },
    );
  });

  testWidgets('flag toggles directly and respects disabled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AssistantLanguageButton(scope: 'coach')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-flag-en')), findsOneWidget);
    await tester.tap(find.byKey(const Key('coach-language-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-flag-de')), findsOneWidget);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AssistantLanguageButton(scope: 'coach', enabled: false),
          ),
        ),
      ),
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });
}
