import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/projection_refresh_providers.dart';
import 'package:my_life_graph/composition/widgets/preparation_budget_control.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/settings/domain/account_settings.dart';
import 'package:my_life_graph/features/settings/domain/account_settings_repository.dart';
import 'package:my_life_graph/features/settings/presentation/providers/account_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = AppProfile(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'synthetic@example.test',
  name: 'Student',
  timezone: 'Europe/Berlin',
  role: AppRole.user,
  onboardingDone: true,
  authProvider: 'email',
  preparationBudgetRevision: 3,
);

const _otherProfile = AppProfile(
  id: '22222222-2222-4222-8222-222222222222',
  email: 'other@example.test',
  name: 'Other student',
  timezone: 'UTC',
  role: AppRole.user,
  onboardingDone: true,
  authProvider: 'email',
  dailyPreparationBudgetMinutes: 60,
  preparationBudgetRevision: 9,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unset budget proposes eight hours but Cancel persists nothing', (
    tester,
  ) async {
    final harness = await _pump(tester);
    expect(find.text('All plans · No limit'), findsOneWidget);
    await _open(tester);
    expect(_input(tester), '480');
    expect(harness.repository.calls, isEmpty);
    expect(find.text('Remove budget'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, isEmpty);
    expect(
      harness.auth.state.value!.profile.dailyPreparationBudgetMinutes,
      isNull,
    );
    expect(harness.impacts, isEmpty);
  });

  testWidgets('explicit Save persists eight hours with opening revision', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _open(tester);
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, [(480, 3)]);
    expect(
      harness.auth.state.value!.profile.dailyPreparationBudgetMinutes,
      480,
    );
    expect(harness.auth.state.value!.profile.preparationBudgetRevision, 4);
    expect(find.text('All plans · 8h/day'), findsOneWidget);
    expect(harness.saved, 1);
    expect(harness.impacts, contains(ProductProjection.preparationWorkload));
    expect(harness.impacts, contains(ProductProjection.examPlanHealth));
  });

  testWidgets('existing custom value stays exact and Remove persists null', (
    tester,
  ) async {
    final harness = await _pump(tester, minutes: 135);
    expect(find.text('All plans · 2h 15m/day'), findsOneWidget);
    await _open(tester);
    expect(_input(tester), '135');
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, isEmpty);
    await _open(tester);
    await tester.tap(find.text('Remove budget'));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, [(null, 3)]);
    expect(find.text('All plans · No limit'), findsOneWidget);
  });

  testWidgets('invalid custom minutes cannot save; preset remains explicit', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _open(tester);
    for (final invalid in ['', '24', '31', '481', 'NaN']) {
      await tester.enterText(
        find.byKey(const ValueKey('daily-preparation-budget-input')),
        invalid,
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save budget'),
            )
            .onPressed,
        isNull,
      );
    }
    await tester.tap(find.text('2h'));
    await tester.pump();
    expect(_input(tester), '120');
    expect(harness.repository.calls, isEmpty);
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, [(120, 3)]);
  });

  for (final sample in [
    (
      const AccountPreparationBudgetUpdateOutcomeUnknownException('unknown'),
      'Retry the same value',
    ),
    (const AccountSettingConflictException('conflict'), 'changed elsewhere'),
    (StateError('offline'), 'Could not update'),
  ]) {
    testWidgets(
      'failed budget ${sample.$1} keeps persisted state and revision',
      (tester) async {
        final harness = await _pump(tester, minutes: 120);
        harness.repository.failure = sample.$1;
        await _open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('daily-preparation-budget-input')),
          '180',
        );
        await tester.pump();
        await tester.tap(find.text('Save budget'));
        await tester.pumpAndSettle();
        expect(harness.repository.calls, [(180, 3)]);
        expect(
          harness.auth.state.value!.profile.dailyPreparationBudgetMinutes,
          120,
        );
        expect(harness.auth.state.value!.profile.preparationBudgetRevision, 3);
        expect(harness.impacts, isEmpty);
        expect(harness.saved, 0);
        expect(find.textContaining(sample.$2), findsOneWidget);
        harness.repository.failure = null;
        await _open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('daily-preparation-budget-input')),
          '180',
        );
        await tester.pump();
        await tester.tap(find.text('Save budget'));
        await tester.pumpAndSettle();
        expect(harness.repository.calls, [(180, 3), (180, 3)]);
      },
    );
  }

  testWidgets('fallback display cannot enable unauthenticated writes', (
    tester,
  ) async {
    final harness = await _pump(tester, authenticated: false);
    expect(find.text('All plans · 2h/day'), findsOneWidget);
    final edit = find.byKey(const ValueKey('edit-preparation-budget'));
    expect(tester.widget<IconButton>(edit).onPressed, isNull);
    expect(harness.repository.calls, isEmpty);
  });

  testWidgets(
    'pending save is single flight and sign-out cannot restore profile',
    (tester) async {
      final harness = await _pump(tester);
      final pending = Completer<AccountPreparationBudgetWrite>();
      harness.repository.pending = pending;
      await _open(tester);
      await tester.tap(find.text('Save budget'));
      await tester.pump();
      expect(harness.repository.calls, [(480, 3)]);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('edit-preparation-budget')),
            )
            .onPressed,
        isNull,
      );
      harness.auth.signOutForTest();
      pending.complete(
        AccountPreparationBudgetWrite(
          minutes: 480,
          revision: 4,
          updatedAt: DateTime.utc(2026),
          replayed: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.auth.state.value, isNull);
      expect(harness.impacts, isEmpty);
      expect(harness.saved, 0);
    },
  );

  testWidgets('account change during the dialog blocks the old account save', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _open(tester);
    harness.auth.setProfile(_otherProfile);
    await tester.pump();
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isEmpty);
    expect(harness.auth.state.value!.profile.id, _otherProfile.id);
    expect(harness.auth.state.value!.profile.dailyPreparationBudgetMinutes, 60);
    expect(harness.auth.state.value!.profile.preparationBudgetRevision, 9);
    expect(harness.impacts, isEmpty);
    expect(harness.saved, 0);
    expect(tester.takeException(), isNull);
  });

  for (final switchAccount in [false, true]) {
    testWidgets(
      'disposed editor save ${switchAccount ? 'cannot overwrite another account' : 'updates the same account and projections'}',
      (tester) async {
        final harness = await _pump(tester);
        final pending = Completer<AccountPreparationBudgetWrite>();
        harness.repository.pending = pending;
        await _open(tester);
        await tester.tap(find.text('Save budget'));
        await tester.pump();
        expect(harness.repository.calls, [(480, 3)]);

        harness.visible.value = false;
        await tester.pump();
        expect(find.byType(PreparationBudgetControl), findsNothing);
        if (switchAccount) harness.auth.setProfile(_otherProfile);
        pending.complete(
          AccountPreparationBudgetWrite(
            minutes: 480,
            revision: 4,
            updatedAt: DateTime.utc(2026),
            replayed: false,
          ),
        );
        await tester.pumpAndSettle();

        final profile = harness.auth.state.value!.profile;
        expect(profile.id, switchAccount ? _otherProfile.id : _profile.id);
        expect(profile.dailyPreparationBudgetMinutes, switchAccount ? 60 : 480);
        expect(profile.preparationBudgetRevision, switchAccount ? 9 : 4);
        expect(
          harness.impacts,
          switchAccount
              ? isEmpty
              : [
                  ProductProjection.preparationWorkload,
                  ProductProjection.examPlanHealth,
                ],
        );
        expect(
          harness.saved,
          0,
          reason: 'Disposed editor callback is not invoked.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('edit-preparation-budget')));
  await tester.pumpAndSettle();
}

String _input(WidgetTester tester) => tester
    .widget<TextField>(
      find.byKey(const ValueKey('daily-preparation-budget-input')),
    )
    .controller!
    .text;

class _Auth extends AuthController {
  _Auth() : super(null);
  void setProfile(AppProfile profile) =>
      state = AsyncData(AppSession.authenticated(profile));
  void signOutForTest() => state = const AsyncData(null);
}

class _Harness {
  final auth = _Auth();
  final visible = ValueNotifier<bool>(true);
  final repository = _Repository();
  final impacts = <ProductProjection>[];
  int saved = 0;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  int? minutes,
  bool authenticated = true,
}) async {
  final harness = _Harness();
  addTearDown(harness.visible.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => harness.auth),
        appSurfaceCapabilitiesProvider.overrideWithValue(
          AppSurfaceCapabilities(
            isLocalDemo: !authenticated,
            canUseSyncedHabits: authenticated,
            canUseSyncedExecution: authenticated,
          ),
        ),
        accountSettingsRepositoryProvider.overrideWithValue(harness.repository),
        projectionRefreshCoordinatorProvider.overrideWithValue(
          ProjectionRefreshCoordinator(
            refreshDailySnapshot: (_) async {},
            invalidateProjection: harness.impacts.add,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: harness.visible,
            builder: (_, visible, __) => visible
                ? PreparationBudgetControl(
                    fallbackKnown: true,
                    fallbackMinutes: 120,
                    onSaved: () => harness.saved++,
                  )
                : const SizedBox(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (authenticated) {
    harness.auth.setProfile(_profile.withDailyPreparationBudget(minutes));
  }
  await tester.pumpAndSettle();
  return harness;
}

class _Repository implements AccountSettingsRepository {
  final calls = <(int?, int)>[];
  Object? failure;
  Completer<AccountPreparationBudgetWrite>? pending;

  @override
  Future<AccountPreparationBudgetWrite> updateDailyPreparationBudget(
    int? minutes, {
    required int expectedRevision,
  }) async {
    calls.add((minutes, expectedRevision));
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return AccountPreparationBudgetWrite(
      minutes: minutes,
      revision: expectedRevision + 1,
      updatedAt: DateTime.utc(2026),
      replayed: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
