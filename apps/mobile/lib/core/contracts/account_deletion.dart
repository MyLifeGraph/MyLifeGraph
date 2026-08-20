const accountDeletionContractVersion = 'account-deletion-v2';
const accountDeletionStatusContractVersion = 'account-deletion-status-v2';

enum AccountDeletionState {
  deletionPending('deletion_pending'),
  completed('completed');

  const AccountDeletionState(this.wireValue);

  final String wireValue;

  static AccountDeletionState? fromWire(String value) {
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.deletionId,
    required this.state,
    required this.acceptedAt,
    required this.completedAt,
    required this.journalDurable,
  });

  final String deletionId;
  final AccountDeletionState state;
  final DateTime acceptedAt;
  final DateTime? completedAt;
  final bool journalDurable;

  bool get isCompleted => state == AccountDeletionState.completed;
}

class AccountDeletionRecovery {
  const AccountDeletionRecovery({
    required this.deletionId,
    required this.result,
  });

  final String deletionId;
  final AccountDeletionResult? result;

  bool get outcomeKnown => result != null;
  bool get journalDurable => result?.journalDurable ?? false;
  bool get isCompleted => result?.isCompleted ?? false;
}
