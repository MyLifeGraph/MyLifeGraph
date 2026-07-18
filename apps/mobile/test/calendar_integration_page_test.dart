import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/calendar_integration/application/calendar_integration_controller.dart';
import 'package:my_life_graph/features/calendar_integration/application/calendar_ics_file_picker.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration_repository.dart';
import 'package:my_life_graph/features/calendar_integration/presentation/pages/calendar_integration_page.dart';
import 'package:my_life_graph/features/calendar_integration/presentation/providers/calendar_integration_providers.dart';

import 'support/calendar_integration_fixtures.dart';

void main() {
  test('only ambiguous or server failures require exact unchanged retry', () {
    DioException failure(int statusCode) {
      final request = RequestOptions(path: '/calendar');
      return DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: statusCode),
      );
    }

    expect(calendarOperationRequiresExactRetry(failure(409)), isFalse);
    expect(calendarOperationRequiresExactRetry(failure(422)), isFalse);
    expect(calendarOperationRequiresExactRetry(failure(500)), isTrue);
    expect(
      calendarOperationRequiresExactRetry(
        AppException('request failed', cause: failure(503)),
      ),
      isTrue,
    );
    expect(
      calendarOperationRequiresExactRetry(
        DioException(
          requestOptions: RequestOptions(path: '/calendar'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      isTrue,
    );
  });

  testWidgets('local demo is honest and exposes no import controls',
      (tester) async {
    final repository = _FakeCalendarRepository(
      CalendarIntegrationFeed.localDemo(),
    );
    await _pumpPage(tester, repository: repository);

    expect(
      find.text('Calendar import unavailable in local demo'),
      findsOneWidget,
    );
    expect(find.text('Create read-only source'), findsNothing);
    expect(find.text('Choose .ics file'), findsNothing);
    expect(repository.getCalls, 1);
    expect(repository.mutationCalls, 0);
  });

  testWidgets('explicit consent is required before creating a source',
      (tester) async {
    final repository = _FakeCalendarRepository(_emptyFeed());
    await _pumpPage(tester, repository: repository);

    FilledButton createButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Create read-only source'),
        );
    expect(createButton().onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), 'Work calendar');
    expect(createButton().onPressed, isNull);
    await tester.tap(find.text('I consent to this read-only import'));
    await tester.pump();
    expect(createButton().onPressed, isNotNull);
  });

  testWidgets('source label keeps focus while request identity rotates',
      (tester) async {
    final repository = _FakeCalendarRepository(_emptyFeed());
    await _pumpPage(tester, repository: repository);

    final field = find.byKey(const ValueKey('calendar-source-label'));
    await tester.tap(field);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'W',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Work calendar',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'Work calendar',
    );
  });

  testWidgets('ambiguous create retries the exact locked request',
      (tester) async {
    final repository = _FakeCalendarRepository(
      _emptyFeed(),
      failFirstCreateAmbiguously: true,
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'Work calendar');
    await tester.tap(find.text('I consent to this read-only import'));
    await tester.pump();
    await tester.tap(find.text('Create read-only source'));
    await tester.pumpAndSettle();

    expect(find.text('Retry unchanged'), findsOneWidget);
    expect(find.text('Could not confirm the calendar change'), findsOneWidget);
    expect(
      find.textContaining('submitted values or file are still here'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );

    await tester.tap(find.text('Retry unchanged'));
    await tester.pumpAndSettle();

    expect(repository.createRequestIds, hasLength(2));
    expect(repository.createRequestIds.toSet(), hasLength(1));
    expect(repository.createLabels, ['Work calendar', 'Work calendar']);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('file retry keeps bytes and request id without repicking',
      (tester) async {
    final repository = _FakeCalendarRepository(
      _connectedFeed(includeImport: false),
      failFirstImportAmbiguously: true,
    );
    final picker = _FakeCalendarPicker(
      SelectedCalendarIcsFile.fromBytes(
        name: 'work.ics',
        bytes: const [66, 69, 71, 73, 78],
      ),
    );
    await _pumpPage(tester, repository: repository, picker: picker);

    await tester.tap(find.text('Choose .ics file'));
    await tester.pumpAndSettle();
    expect(find.text('work.ics · 5 bytes'), findsOneWidget);
    await tester.tap(find.text('Import selected file'));
    await tester.pumpAndSettle();
    expect(find.text('Retry unchanged'), findsOneWidget);

    await tester.tap(find.text('Retry unchanged'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(repository.importRequestIds, hasLength(2));
    expect(repository.importRequestIds.toSet(), hasLength(1));
    expect(repository.importTexts, ['BEGIN', 'BEGIN']);
    expect(find.text('Imported · read-only'), findsNWidgets(2));
    expect(
      find.text('2026-07-13 · 22:30–2026-07-14 01:30'),
      findsOneWidget,
    );
  });

  testWidgets('disconnected never-imported source can still be cleared',
      (tester) async {
    final repository = _FakeCalendarRepository(
      _disconnectedFeed(includeImport: false),
    );
    await _pumpPage(tester, repository: repository);

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.textContaining('No file was imported'), findsOneWidget);
    expect(find.text('No file has been imported yet.'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Delete imported data'));
    await tester.tap(find.text('Delete imported data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete imported calendar data?'), findsOneWidget);
    expect(repository.deleteRequestIds, isEmpty);

    await tester.tap(find.text('Delete local imported data'));
    await tester.pumpAndSettle();
    expect(repository.deleteRequestIds, hasLength(1));
    expect(find.text('Imported data deleted'), findsOneWidget);
    expect(find.text('Create read-only source'), findsOneWidget);
  });

  testWidgets('ambiguous disconnect retries the exact request id',
      (tester) async {
    final repository = _FakeCalendarRepository(
      _connectedFeed(includeImport: true),
      failFirstDisconnectAmbiguously: true,
    );
    await _pumpPage(tester, repository: repository);

    await tester.ensureVisible(find.text('Disconnect source'));
    await tester.tap(find.text('Disconnect source'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Retry unchanged'), findsOneWidget);

    await tester.tap(find.text('Retry unchanged'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(repository.disconnectRequestIds, hasLength(2));
    expect(repository.disconnectRequestIds.toSet(), hasLength(1));
    expect(
      find.text('Disconnected · may be out of date'),
      findsOneWidget,
    );
  });

  testWidgets('ambiguous deletion retries the exact request id',
      (tester) async {
    final repository = _FakeCalendarRepository(
      _disconnectedFeed(includeImport: true),
      failFirstDeleteAmbiguously: true,
    );
    await _pumpPage(tester, repository: repository);

    await tester.ensureVisible(find.text('Delete imported data'));
    await tester.tap(find.text('Delete imported data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete local imported data'));
    await tester.pumpAndSettle();
    expect(find.text('Retry unchanged'), findsOneWidget);

    await tester.tap(find.text('Retry unchanged'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete local imported data'));
    await tester.pumpAndSettle();

    expect(repository.deleteRequestIds, hasLength(2));
    expect(repository.deleteRequestIds.toSet(), hasLength(1));
    expect(find.text('Imported data deleted'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeCalendarRepository repository,
  CalendarIcsFilePicker? picker,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarIntegrationRepositoryProvider.overrideWithValue(repository),
        calendarIcsFilePickerProvider.overrideWithValue(
          picker ?? _FakeCalendarPicker(null),
        ),
      ],
      child: const MaterialApp(home: CalendarIntegrationPage()),
    ),
  );
  await tester.pumpAndSettle();
}

CalendarIntegrationFeed _emptyFeed() => CalendarIntegrationFeed.fromJson(
      calendarFeedJson(noConnection: true),
    );

CalendarIntegrationFeed _connectedFeed({required bool includeImport}) =>
    CalendarIntegrationFeed.fromJson(
      calendarFeedJson(
        connection: calendarConnectionJson(includeImport: includeImport),
      ),
    );

CalendarIntegrationFeed _disconnectedFeed({required bool includeImport}) =>
    CalendarIntegrationFeed.fromJson(
      calendarFeedJson(
        connection: calendarConnectionJson(
          status: 'disconnected',
          includeImport: includeImport,
        ),
      ),
    );

class _FakeCalendarPicker implements CalendarIcsFilePicker {
  _FakeCalendarPicker(this.file);

  final SelectedCalendarIcsFile? file;
  int calls = 0;

  @override
  Future<SelectedCalendarIcsFile?> pickFile() async {
    calls += 1;
    return file;
  }
}

class _FakeCalendarRepository implements CalendarIntegrationRepository {
  _FakeCalendarRepository(
    this.feed, {
    this.failFirstCreateAmbiguously = false,
    this.failFirstImportAmbiguously = false,
    this.failFirstDisconnectAmbiguously = false,
    this.failFirstDeleteAmbiguously = false,
  });

  CalendarIntegrationFeed feed;
  final bool failFirstCreateAmbiguously;
  final bool failFirstImportAmbiguously;
  final bool failFirstDisconnectAmbiguously;
  final bool failFirstDeleteAmbiguously;
  int getCalls = 0;
  final List<String> createRequestIds = [];
  final List<String> createLabels = [];
  final List<String> importRequestIds = [];
  final List<String> importTexts = [];
  final List<String> disconnectRequestIds = [];
  final List<String> deleteRequestIds = [];

  int get mutationCalls =>
      createRequestIds.length +
      importRequestIds.length +
      disconnectRequestIds.length +
      deleteRequestIds.length;

  DioException get _ambiguous => DioException(
        requestOptions: RequestOptions(path: '/calendar'),
        type: DioExceptionType.connectionTimeout,
      );

  @override
  Future<CalendarIntegrationFeed> getIntegration() async {
    getCalls += 1;
    return feed;
  }

  @override
  Future<CalendarIntegrationFeed> createConnection({
    required String requestId,
    required String sourceLabel,
  }) async {
    createRequestIds.add(requestId);
    createLabels.add(sourceLabel);
    if (failFirstCreateAmbiguously && createRequestIds.length == 1) {
      throw _ambiguous;
    }
    feed = _connectedFeed(includeImport: false);
    return feed;
  }

  @override
  Future<CalendarImportResponse> importCalendar({
    required String connectionId,
    required String requestId,
    required String calendarText,
  }) async {
    importRequestIds.add(requestId);
    importTexts.add(calendarText);
    if (failFirstImportAmbiguously && importRequestIds.length == 1) {
      throw _ambiguous;
    }
    final response = CalendarImportResponse.fromJson(
      calendarImportResponseJson(),
    );
    feed = CalendarIntegrationFeed.authenticated(response.connection);
    return response;
  }

  @override
  Future<CalendarEventPage> getEvents({
    required String connectionId,
    String? cursor,
  }) async {
    return CalendarEventPage.fromJson(calendarEventsPageJson());
  }

  @override
  Future<CalendarIntegrationFeed> disconnect({
    required String connectionId,
    required String requestId,
  }) async {
    disconnectRequestIds.add(requestId);
    if (failFirstDisconnectAmbiguously && disconnectRequestIds.length == 1) {
      throw _ambiguous;
    }
    feed = _disconnectedFeed(includeImport: true);
    return feed;
  }

  @override
  Future<CalendarIntegrationFeed> deleteImportedData({
    required String connectionId,
    required String requestId,
  }) async {
    deleteRequestIds.add(requestId);
    if (failFirstDeleteAmbiguously && deleteRequestIds.length == 1) {
      throw _ambiguous;
    }
    feed = CalendarIntegrationFeed.fromJson(
      calendarFeedJson(
        connection: calendarConnectionJson(
          status: 'disconnected',
          includeImport: false,
          deleted: true,
        ),
      ),
    );
    return feed;
  }
}
