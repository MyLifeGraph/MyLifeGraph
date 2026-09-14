import '../../../core/contracts/strict_contract.dart';

const quickNotesContractVersion = 'quick-notes-v1';

abstract interface class QuickCaptureApi {
  Future<Map<String, dynamic>> propose({
    required String requestId,
    required String branch,
    required String transcript,
  });
  Future<QuickNote> saveNote({
    required String noteId,
    required String timezone,
    required String text,
  });
  Future<QuickNotesPage> notes({String? before});
  Future<void> deleteNote(String noteId);
}

class QuickNote {
  const QuickNote({
    required this.id,
    required this.text,
    required this.entryDate,
  });
  final String id;
  final String text;
  final String entryDate;

  factory QuickNote.fromJson(Map<String, dynamic> json) {
    final id = requireStrictUuid(
      json['id'],
      onFailure: () {
        throw const FormatException('Invalid quick note identity.');
      },
    );
    final text = json['text'];
    final date = json['entry_date'];
    if (text is! String ||
        text.trim().isEmpty ||
        text.length > 2000 ||
        date is! String ||
        !isStrictLocalDate(date)) {
      throw const FormatException('Invalid quick note.');
    }
    return QuickNote(id: id, text: text, entryDate: date);
  }
}

class QuickNotesPage {
  const QuickNotesPage(this.notes, this.nextCursor);
  final List<QuickNote> notes;
  final String? nextCursor;
}
