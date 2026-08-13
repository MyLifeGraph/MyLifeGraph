class PreparationMutationGate {
  Object? _owner;

  bool get isLocked => _owner != null;

  bool tryAcquire(Object owner) {
    if (_owner != null) return identical(_owner, owner);
    _owner = owner;
    return true;
  }

  void release(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }
}
