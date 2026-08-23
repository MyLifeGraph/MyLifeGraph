class MissingProfileInvariantException implements Exception {
  const MissingProfileInvariantException();

  @override
  String toString() => 'The authenticated account profile is unavailable.';
}
