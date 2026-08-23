import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachResponseCancellationAuthority {
  void Function()? _cancel;
  int _generation = 0;

  int register(void Function() cancel) {
    _generation += 1;
    _cancel = cancel;
    return _generation;
  }

  void unregister(int generation) {
    if (generation == _generation) _cancel = null;
  }

  void cancel() => _cancel?.call();
}

final coachResponseCancellationAuthorityProvider =
    Provider<CoachResponseCancellationAuthority>(
  (_) => CoachResponseCancellationAuthority(),
);
