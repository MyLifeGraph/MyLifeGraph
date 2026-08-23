import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CoachTurnNoticeStatus {
  completed,
  failed;
}

class CoachTurnNotice {
  const CoachTurnNotice({
    required this.profileId,
    required this.requestId,
    required this.status,
  });

  final String profileId;
  final String requestId;
  final CoachTurnNoticeStatus status;

  String get message => switch (status) {
        CoachTurnNoticeStatus.completed => 'Your Coach answer is ready.',
        CoachTurnNoticeStatus.failed =>
          'Coach could not finish the answer. Open Coach to review or retry.',
      };

  String get semanticsLabel => switch (status) {
        CoachTurnNoticeStatus.completed => 'Unread Coach answer',
        CoachTurnNoticeStatus.failed => 'Unread Coach failure',
      };
}

class CoachTurnNoticeController extends StateNotifier<CoachTurnNotice?> {
  CoachTurnNoticeController({required this.profileId}) : super(null);

  final String? profileId;

  void publish({
    required String profileId,
    required String requestId,
    required CoachTurnNoticeStatus status,
  }) {
    if (this.profileId == null || profileId != this.profileId) return;
    state = CoachTurnNotice(
      profileId: profileId,
      requestId: requestId,
      status: status,
    );
  }

  void markRead({
    required String profileId,
    required String requestId,
    CoachTurnNoticeStatus? status,
  }) {
    final current = state;
    if (current == null ||
        current.profileId != profileId ||
        current.requestId != requestId ||
        status != null && current.status != status) {
      return;
    }
    state = null;
  }
}
