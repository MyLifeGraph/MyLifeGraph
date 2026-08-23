import '../../../core/network/api_failure.dart';
import '../data/guest_setup_data_source.dart';

enum SetupFailureOperation { load, save }

/// Maps Setup failures to bounded student-facing copy.
///
/// Raw URLs, HTTP bodies, status codes, Dio diagnostics, nested causes, and
/// contract validator messages must never cross this boundary into widgets.
String setupUserMessage(
  Object? error, {
  required SetupFailureOperation operation,
}) {
  if (operation == SetupFailureOperation.load) {
    return 'Your saved setup could not be loaded. Retry; no draft changes were made.';
  }
  if (error is GuestSetupRevisionException) {
    return 'Saved Setup changed elsewhere. Reload it, then review your draft again.';
  }
  if (error is GuestSetupIdempotencyException) {
    return 'This save no longer matches its original draft. Reload Setup before trying again.';
  }
  final statusCode = apiFailureFrom(error)?.statusCode;
  if (statusCode == 409) {
    return 'Saved Setup changed elsewhere. Reload it; your draft is still here.';
  }
  if (statusCode == 401 || statusCode == 403) {
    return 'Your session could not save Setup. Sign in again; your draft is still here.';
  }
  if (statusCode != null && statusCode >= 400 && statusCode < 500) {
    return 'Setup could not be saved as entered. Review the highlighted values; your draft is still here.';
  }
  return 'Setup could not be saved. Keep this draft open and retry unchanged.';
}
