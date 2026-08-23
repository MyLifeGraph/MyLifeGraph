abstract interface class FocusRecoveryStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class MemoryFocusRecoveryStore implements FocusRecoveryStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}
