import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/presentation/providers/auth_providers.dart';
import 'package:my_life_graph/features/settings/application/account_export_saver.dart';
import 'package:my_life_graph/features/settings/domain/account_settings.dart';
import 'package:my_life_graph/features/settings/domain/account_settings_repository.dart';
import 'package:my_life_graph/features/settings/presentation/pages/settings_page.dart';
import 'package:my_life_graph/features/settings/presentation/providers/account_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'synced settings retries timezone, exports, and requires typed deletion',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository()
      ..failNextTimezone = true;
    final exportSaver = _FakeExportSaver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
              canUseWeeklyReview: true,
              canUseCalendarIntegration: true,
              canAccessCoachBackend: true,
              canShowCoachSurface: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
          accountExportSaverProvider.overrideWithValue(exportSaver),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Synced account'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Synced account')),
    );
    await tester.scrollUntilVisible(
      find.text('In-app reminders'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('In-app reminders'), findsOneWidget);
    expect(
      find.text(
        'Allow banners while the app is open and choose what may appear.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Change timezone'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Existing preparation reservations keep'),
      findsOneWidget,
    );
    expect(
      find.textContaining('do not refresh automatically'),
      findsOneWidget,
    );
    await tester.tap(find.text('Europe/Berlin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save timezone'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not update the timezone. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Change timezone'), findsOneWidget);

    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Berlin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save timezone'));
    await tester.pumpAndSettle();

    expect(accountRepository.timezoneCalls, ['Europe/London', 'Europe/London']);
    expect(find.text('Europe/London'), findsOneWidget);

    accountRepository.timezoneError =
        const AccountProfileUpdateOutcomeUnknownException('unknown');
    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Paris').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save timezone'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Timezone update could not be confirmed. Select the same timezone again to retry safely, or sign in again to verify it before choosing another.',
      ),
      findsOneWidget,
    );
    expect(find.text('Europe/London'), findsOneWidget);

    accountRepository.timezoneError =
        const AccountTimezoneRejectedException('not recognized');
    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Paris').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save timezone'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Timezone was not recognized. Choose another IANA timezone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Europe/London'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Export data'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Export data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export data'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(accountRepository.exportCalls, 1);
    expect(exportSaver.calls, 1);
    expect(find.text('Account export saved.'), findsOneWidget);

    accountRepository.exportError = const AccountExportTooLargeException(
      'too large',
    );
    await tester.tap(find.text('Export data'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This account exceeds the V1 export limits. Retrying unchanged will not help; reduce deletable history or request a larger export workflow.',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    final confirmButton = find.widgetWithText(FilledButton, 'Delete account');
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'delete',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(accountRepository.deleteCalls, 1);
    expect(authRepository.deletedAccountSignOutCalls, 1);
    expect(
      container.read(authNoticeProvider)?.message,
      'Account and canonical synced data deleted.',
    );
    expect(container.read(authNoticeProvider)?.isError, isFalse);
  });

  testWidgets('custom IANA timezone path is available and validated',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Berlin').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enter another IANA timezone…'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Enter another IANA timezone…').last);
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Save timezone');
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom IANA timezone'),
      'not-a-zone',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom IANA timezone'),
      'Africa/Johannesburg',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(accountRepository.timezoneCalls, ['Africa/Johannesburg']);
  });

  testWidgets('daily preparation budget can be saved and removed explicitly',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    final setting = find.byKey(
      const ValueKey('daily-preparation-budget-setting'),
    );
    await tester.dragUntilVisible(
      setting,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(setting.hitTestable(), findsOneWidget);
    await tester.tap(setting.hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('transparent rule, not an AI estimate'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('daily-preparation-budget-input')),
      '120',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
    await tester.pumpAndSettle();

    expect(accountRepository.preparationBudgetCalls, [120]);
    expect(
      find.text('2h total per day across confirmed preparation plans.'),
      findsOneWidget,
    );

    await tester.dragUntilVisible(
      setting,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(setting.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove budget'));
    await tester.pumpAndSettle();

    expect(accountRepository.preparationBudgetCalls, [120, null]);
    expect(
      find.text('Not set. Existing per-plan limits still apply.'),
      findsOneWidget,
    );
  });

  testWidgets('preparation budget dialog stays usable at 320px and 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final setting = find.byKey(
      const ValueKey('daily-preparation-budget-setting'),
    );
    await tester.dragUntilVisible(
      setting,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(setting.hitTestable(), findsOneWidget);
    await tester.tap(setting.hitTestable());
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(tester.widget<AlertDialog>(dialog).scrollable, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('daily-preparation-budget-input')),
      '120',
    );
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save budget');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending account export does not hand off after navigation',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final exportRequest = Completer<void>();
    final accountRepository = _FakeAccountSettingsRepository()
      ..exportCompleter = exportRequest;
    final exportSaver = _FakeExportSaver();
    final showSettings = ValueNotifier(true);
    addTearDown(showSettings.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
          accountExportSaverProvider.overrideWithValue(exportSaver),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showSettings,
              builder: (_, visible, __) => visible
                  ? const SettingsPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Export data'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Export data'));
    await tester.pump();

    expect(accountRepository.exportCalls, 1);
    expect(exportSaver.calls, 0);
    showSettings.value = false;
    await tester.pump();
    exportRequest.complete();
    await tester.pumpAndSettle();

    expect(find.text('Different destination'), findsOneWidget);
    expect(exportSaver.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account dialog results are ignored after Settings unmounts',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository();
    final showSettings = ValueNotifier<bool>(true);
    addTearDown(showSettings.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showSettings,
              builder: (_, visible, __) => visible
                  ? const SettingsPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Berlin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    showSettings.value = false;
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save timezone'));
    await tester.pumpAndSettle();

    expect(accountRepository.timezoneCalls, isEmpty);
    expect(tester.takeException(), isNull);

    showSettings.value = true;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    showSettings.value = false;
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(accountRepository.deleteCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent-auth deletion rejection keeps the account signed in',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository()
      ..deleteError = const AccountRecentAuthenticationRequiredException(
        'recent authentication required',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Synced account')),
    );

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(accountRepository.deleteCalls, 1);
    expect(authRepository.deletedAccountSignOutCalls, 0);
    expect(container.read(authControllerProvider).valueOrNull, isNotNull);
    expect(
      find.text(
        'For safety, sign out and sign in again, then return here to delete the account.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ambiguous deletion closes the local session without retrying',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository()
      ..deleteError = const AccountDeletionOutcomeUnknownException(
        'outcome unknown',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Synced account')),
    );

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(accountRepository.deleteCalls, 1);
    expect(authRepository.deletedAccountSignOutCalls, 1);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
    expect(
      container.read(authNoticeProvider)?.message,
      'Deletion could not be confirmed. Sign in again; if the account remains, retry deletion.',
    );
    expect(container.read(authNoticeProvider)?.isError, isTrue);
  });

  testWidgets('delete finalization survives leaving Settings before commit',
      (tester) async {
    final authRepository = _SettingsAuthRepository();
    final deletion = Completer<void>();
    final accountRepository = _FakeAccountSettingsRepository()
      ..deleteCompleter = deletion;
    final showSettings = ValueNotifier<bool>(true);
    addTearDown(showSettings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showSettings,
              builder: (_, visible, __) => visible
                  ? const SettingsPage()
                  : const Text('Different destination'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Synced account')),
    );

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();

    showSettings.value = false;
    await tester.pump();
    expect(find.text('Different destination'), findsOneWidget);
    deletion.complete();
    await tester.pumpAndSettle();

    expect(authRepository.deletedAccountSignOutCalls, 1);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
    expect(
      container.read(authNoticeProvider)?.message,
      'Account and canonical synced data deleted.',
    );
    expect(container.read(authNoticeProvider)?.isError, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account dialogs keep their lower actions reachable at 320 pixels with larger text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authRepository = _SettingsAuthRepository();
    final accountRepository = _FakeAccountSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          appSurfaceCapabilitiesProvider.overrideWithValue(
            const AppSurfaceCapabilities(
              isLocalDemo: false,
              canUseSyncedHabits: true,
              canUseSyncedExecution: true,
            ),
          ),
          accountSettingsRepositoryProvider.overrideWithValue(
            accountRepository,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final changeTimezone = find.text('Change timezone');
    await tester.dragUntilVisible(
      changeTimezone,
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(changeTimezone.hitTestable(), findsOneWidget);
    await tester.tap(changeTimezone.hitTestable());
    await tester.pumpAndSettle();

    var dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(tester.widget<AlertDialog>(dialog).scrollable, isTrue);
    final saveTimezone = find.widgetWithText(
      FilledButton,
      'Save timezone',
    );
    await tester.ensureVisible(saveTimezone);
    await tester.pumpAndSettle();
    expect(saveTimezone.hitTestable(), findsOneWidget);
    await tester.tap(saveTimezone.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Account timezone'), findsNothing);

    final deleteEntry = find.text('Delete account');
    await tester.scrollUntilVisible(
      deleteEntry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(deleteEntry);
    await tester.pumpAndSettle();
    await tester.tap(deleteEntry);
    await tester.pumpAndSettle();

    dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(tester.widget<AlertDialog>(dialog).scrollable, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      'DELETE',
    );
    await tester.pump();
    final confirmDelete = find.widgetWithText(
      FilledButton,
      'Delete account',
    );
    await tester.ensureVisible(confirmDelete);
    await tester.pumpAndSettle();
    expect(confirmDelete.hitTestable(), findsOneWidget);
    await tester.tap(confirmDelete.hitTestable());
    await tester.pumpAndSettle();

    expect(accountRepository.deleteCalls, 1);
    expect(authRepository.deletedAccountSignOutCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _SettingsAuthRepository extends AuthRepository {
  _SettingsAuthRepository()
      : super(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          useMockData: false,
        );

  final _session = AppSession.authenticated(
    const AppProfile(
      id: 'account-id',
      email: 'person@example.test',
      name: 'Account Person',
      timezone: 'Europe/Berlin',
      role: AppRole.user,
      onboardingDone: true,
      authProvider: 'email',
    ),
  );
  int deletedAccountSignOutCalls = 0;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AppSession?> currentSession() async => _session;

  @override
  Future<void> signOutAfterAccountDeletion() async {
    deletedAccountSignOutCalls += 1;
  }
}

class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool failNextTimezone = false;
  Object? timezoneError;
  Object? deleteError;
  Completer<void>? deleteCompleter;
  final List<String> timezoneCalls = [];
  final List<int?> preparationBudgetCalls = [];
  int exportCalls = 0;
  Object? exportError;
  Completer<void>? exportCompleter;
  int deleteCalls = 0;

  @override
  Future<String> updateTimezone(String timezone) async {
    timezoneCalls.add(timezone);
    if (failNextTimezone) {
      failNextTimezone = false;
      throw StateError('temporary profile failure');
    }
    final error = timezoneError;
    timezoneError = null;
    if (error != null) throw error;
    return timezone;
  }

  @override
  Future<int?> updateDailyPreparationBudget(int? minutes) async {
    preparationBudgetCalls.add(minutes);
    return minutes;
  }

  @override
  Future<AccountExportEnvelope> exportAccount() async {
    exportCalls += 1;
    final completer = exportCompleter;
    if (completer != null) await completer.future;
    final error = exportError;
    exportError = null;
    if (error != null) throw error;
    final data = <String, dynamic>{
      for (final table in accountExportV1TableNames)
        table: <Map<String, dynamic>>[],
    };
    return AccountExportEnvelope.fromJson({
      'contract_version': 'account-export-v1',
      'exported_at': '2026-07-13T12:00:00Z',
      'data': data,
      'record_counts': <String, int>{
        for (final table in accountExportV1TableNames) table: 0,
      },
      'ledger_policy': {
        'sanitized_tables': accountExportV1SanitizedTables,
        'omitted_tables': accountExportV1OmittedTables,
      },
      'limits': {
        'max_rows_per_table': accountExportV1MaxRowsPerTable,
        'max_total_rows': accountExportV1MaxTotalRows,
        'max_json_bytes': accountExportV1MaxJsonBytes,
      },
    });
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls += 1;
    final completer = deleteCompleter;
    if (completer != null) await completer.future;
    final error = deleteError;
    if (error != null) throw error;
  }
}

class _FakeExportSaver implements AccountExportSaver {
  int calls = 0;

  @override
  Future<AccountExportSaveResult> save({
    required String suggestedName,
    required AccountExportEnvelope export,
    Rect? sharePositionOrigin,
  }) async {
    calls += 1;
    expect(suggestedName, startsWith('mylifegraph-export-'));
    expect(export.contractVersion, 'account-export-v1');
    return AccountExportSaveResult.saved;
  }
}
