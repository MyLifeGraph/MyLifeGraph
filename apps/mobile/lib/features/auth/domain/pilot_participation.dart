import '../../../core/contracts/strict_contract.dart';

const pilotParticipationContractVersion = 'pilot-participation-v1';
const pilotParticipationNoticeVersion = 'pilot-participation-notice-v1';

class PilotParticipationAcceptance {
  const PilotParticipationAcceptance({
    required this.noticeVersion,
    required this.acceptedAt,
    required this.replayed,
  });

  factory PilotParticipationAcceptance.fromJson(Map<String, dynamic> json) {
    Never invalid() => throw const PilotParticipationContractException();
    requireStrictKeys(
      json,
      requiredKeys: const {
        'contract_version',
        'notice_version',
        'accepted_at',
        'replayed',
      },
      onFailure: invalid,
    );
    if (json['contract_version'] != pilotParticipationContractVersion ||
        json['notice_version'] != pilotParticipationNoticeVersion ||
        json['accepted_at'] is! String ||
        json['replayed'] is! bool) {
      invalid();
    }
    final acceptedAt = DateTime.tryParse(json['accepted_at'] as String);
    if (acceptedAt == null || !acceptedAt.isUtc) invalid();
    return PilotParticipationAcceptance(
      noticeVersion: json['notice_version'] as String,
      acceptedAt: acceptedAt,
      replayed: json['replayed'] as bool,
    );
  }

  final String noticeVersion;
  final DateTime acceptedAt;
  final bool replayed;
}

class PilotParticipationContractException implements Exception {
  const PilotParticipationContractException();

  @override
  String toString() => 'Pilot participation returned an invalid result.';
}
