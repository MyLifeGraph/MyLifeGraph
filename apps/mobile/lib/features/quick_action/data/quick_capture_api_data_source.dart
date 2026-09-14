import '../../../core/contracts/strict_contract.dart';
import '../../../core/network/api_client.dart';
import '../domain/quick_capture_api.dart';
import '../domain/capture_draft_proposal.dart';

class QuickCaptureApiDataSource implements QuickCaptureApi {
  const QuickCaptureApiDataSource(this._client, this._headers);
  final ApiClient _client;
  final Future<Map<String, String>> Function(bool needsCoach) _headers;

  @override
  Future<Map<String, dynamic>> propose({
    required String requestId,
    required String branch,
    required String transcript,
  }) async => _client.postJsonWithTimeout(
    '/v1/daily-capture/draft',
    headers: await _headers(true),
    receiveTimeout: const Duration(seconds: 190),
    body: {
      'contract_version': dailyCaptureDraftVersion,
      'request_id': requestId,
      'branch': branch,
      'transcript': transcript,
    },
  );

  @override
  Future<QuickNote> saveNote({
    required String noteId,
    required String timezone,
    required String text,
  }) async {
    final json = await _client.postJson(
      '/v1/quick-notes',
      headers: await _headers(false),
      body: {
        'contract_version': quickNotesContractVersion,
        'note_id': noteId,
        'timezone': timezone,
        'text': text,
      },
    );
    _checkVersion(json);
    final note = QuickNote.fromJson(
      Map<String, dynamic>.from(json['note'] as Map),
    );
    if (note.id != noteId || note.text != text) {
      throw const FormatException('Quick note response did not match.');
    }
    return note;
  }

  @override
  Future<QuickNotesPage> notes({String? before}) async {
    if (before != null && !isStrictUuid(before)) {
      throw const FormatException('Invalid note cursor.');
    }
    final json = await _client.getJson(
      '/v1/quick-notes${before == null ? '' : '?before=$before'}',
      headers: await _headers(false),
    );
    _checkVersion(json);
    final items = json['notes'];
    final cursor = json['next_cursor'];
    if (items is! List ||
        items.length > 50 ||
        (cursor != null && (cursor is! String || !isStrictUuid(cursor)))) {
      throw const FormatException('Invalid quick notes response.');
    }
    return QuickNotesPage(
      items
          .map(
            (item) =>
                QuickNote.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      cursor as String?,
    );
  }

  @override
  Future<void> deleteNote(String noteId) async {
    if (!isStrictUuid(noteId)) {
      throw const FormatException('Invalid note identity.');
    }
    final json = await _client.deleteJson(
      '/v1/quick-notes/$noteId',
      headers: await _headers(false),
    );
    _checkVersion(json);
    if (json['note_id'] != noteId || json['deleted'] != true) {
      throw const FormatException('Quick note deletion was not confirmed.');
    }
  }

  void _checkVersion(Map<String, dynamic> json) {
    if (json['contract_version'] != quickNotesContractVersion) {
      throw const FormatException('Unsupported quick notes response.');
    }
  }
}
