import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/quick_action/data/quick_capture_api_data_source.dart';
import 'package:my_life_graph/features/quick_action/domain/capture_draft_proposal.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_capture_api.dart';

const _id = '11111111-1111-4111-8111-111111111111';

void main() {
  test(
    'draft uses separate versioned route and request-scoped Coach headers',
    () async {
      final client = _Client();
      final modes = <bool>[];
      final source = QuickCaptureApiDataSource(client, (coach) async {
        modes.add(coach);
        return {'Authorization': 'Bearer test-only'};
      });
      await source.propose(
        requestId: _id,
        branch: 'morning',
        transcript: 'Energy 7/10',
      );
      expect(modes, [true]);
      expect(client.path, '/v1/daily-capture/draft');
      expect(client.body, {
        'contract_version': dailyCaptureDraftVersion,
        'request_id': _id,
        'branch': 'morning',
        'transcript': 'Energy 7/10',
      });
      expect(client.timeout, const Duration(seconds: 190));
    },
  );

  test(
    'note requests use no Coach key and require exact confirmed response',
    () async {
      final client = _Client()
        ..response = {
          'contract_version': quickNotesContractVersion,
          'note': _note(),
          'replayed': false,
        };
      final source = QuickCaptureApiDataSource(client, (coach) async {
        expect(coach, isFalse);
        return {};
      });
      final note = await source.saveNote(
        noteId: _id,
        timezone: 'Europe/Berlin',
        text: 'Context',
      );
      expect(note.id, _id);
      expect(client.body!['note_id'], _id);
      client.response['note'] = {..._note(), 'text': 'Different'};
      await expectLater(
        source.saveNote(
          noteId: _id,
          timezone: 'Europe/Berlin',
          text: 'Context',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'unsupported response versions and invalid note dates fail closed',
    () async {
      final client = _Client()
        ..response = {
          'contract_version': 'other',
          'notes': [],
          'next_cursor': null,
        };
      final source = QuickCaptureApiDataSource(client, (_) async => {});
      await expectLater(source.notes(), throwsFormatException);
      expect(
        () => QuickNote.fromJson({..._note(), 'entry_date': '2026-02-31'}),
        throwsFormatException,
      );
      expect(
        () => QuickNote.fromJson({..._note(), 'text': '   '}),
        throwsFormatException,
      );
    },
  );

  test(
    'pagination is bounded and cursor cannot add query parameters',
    () async {
      final client = _Client()
        ..response = {
          'contract_version': quickNotesContractVersion,
          'notes': [_note()],
          'next_cursor': _id,
        };
      final source = QuickCaptureApiDataSource(client, (_) async => {});
      final page = await source.notes(before: _id);
      expect(page.nextCursor, _id);
      expect(client.path, '/v1/quick-notes?before=$_id');
      await expectLater(
        source.notes(before: 'bad&owner=other'),
        throwsFormatException,
      );
      client.response['notes'] = List.generate(51, (_) => _note());
      await expectLater(source.notes(), throwsFormatException);
    },
  );

  test('delete requires exact identity and positive confirmation', () async {
    final client = _Client()
      ..response = {
        'contract_version': quickNotesContractVersion,
        'note_id': _id,
        'deleted': true,
      };
    final source = QuickCaptureApiDataSource(client, (_) async => {});
    await source.deleteNote(_id);
    expect(client.path, '/v1/quick-notes/$_id');
    client.response['deleted'] = false;
    await expectLater(source.deleteNote(_id), throwsFormatException);
  });
}

Map<String, dynamic> _note() => {
  'id': _id,
  'text': 'Context',
  'entry_date': '2026-09-14',
  'timezone': 'Europe/Berlin',
  'created_at': '2026-09-14T12:00:00Z',
};

class _Client extends ApiClient {
  _Client() : super(Dio());
  String? path;
  Map<String, dynamic>? body;
  Duration? timeout;
  Map<String, dynamic> response = {};
  @override
  Future<Map<String, dynamic>> postJsonWithTimeout(
    String path, {
    required Duration receiveTimeout,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    timeout = receiveTimeout;
    return postJson(path, body: body, headers: headers);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.body = body;
    return response;
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    this.path = path;
    return response;
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    this.path = path;
    return response;
  }
}
