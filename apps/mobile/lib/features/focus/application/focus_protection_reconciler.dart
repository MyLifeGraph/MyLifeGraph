import '../../focus_protection/application/focus_protection_gateway.dart';
import '../../focus_protection/domain/focus_protection.dart';
import '../domain/focus_session.dart';

class FocusProtectionDeactivation {
  const FocusProtectionDeactivation({
    required this.status,
    required this.confirmed,
  });

  final FocusProtectionStatus? status;
  final bool confirmed;
}

/// Keeps device-local protection reconciliation separate from synced Focus.
///
/// Every method treats native failures as protection state only. It never
/// starts, finishes, abandons, or otherwise reinterprets a canonical session.
class FocusProtectionReconciler {
  const FocusProtectionReconciler({
    required FocusProtectionGateway gateway,
    required bool platformSupported,
  })  : _gateway = gateway,
        _platformSupported = platformSupported;

  final FocusProtectionGateway _gateway;
  final bool _platformSupported;

  Future<FocusProtectionStatus?> reconcile({
    required FocusSession? canonicalSession,
    FocusProtectionStatus? lastKnownStatus,
    bool Function()? shouldContinue,
  }) async {
    if (!_platformSupported) return null;
    bool canContinue() => shouldContinue?.call() ?? true;
    var lastKnownConfiguration = lastKnownStatus?.configuration;
    try {
      var status = await _gateway.readStatus();
      lastKnownConfiguration = status.configuration;
      if (!canContinue()) return null;
      if (canonicalSession == null && status.lease != null) {
        status = await _gateway.deactivateLease(status.lease!.sessionId);
        if (!canContinue()) return null;
      }
      if (canonicalSession != null && status.configuration.enabled) {
        status = await _gateway.activateLease(
          sessionId: canonicalSession.id,
          startedAt: canonicalSession.startedAt,
          endsAt: canonicalSession.startedAt.add(
            Duration(minutes: canonicalSession.plannedMinutes),
          ),
        );
        if (!canContinue()) return null;
      }
      return status;
    } catch (_) {
      if (!canContinue()) return null;
      return FocusProtectionStatus.nativeFailure(
        configuration: lastKnownConfiguration,
      );
    }
  }

  Future<FocusProtectionDeactivation> deactivate({
    required String sessionId,
    FocusProtectionStatus? lastKnownStatus,
  }) async {
    if (!_platformSupported) {
      return const FocusProtectionDeactivation(
        status: null,
        confirmed: true,
      );
    }
    try {
      final status = await _gateway.deactivateLease(sessionId);
      return FocusProtectionDeactivation(
        status: status,
        confirmed: !status.warnings.contains(
              FocusProtectionWarning.nativeFailure,
            ) &&
            status.lease?.sessionId != sessionId,
      );
    } catch (_) {
      return FocusProtectionDeactivation(
        status: FocusProtectionStatus.nativeFailure(
          configuration: lastKnownStatus?.configuration,
        ),
        confirmed: false,
      );
    }
  }

  Future<FocusProtectionStatus> emergencyRelease(String sessionId) {
    return _gateway.emergencyRelease(sessionId);
  }
}
