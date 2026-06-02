class BehavioralSignal {
  const BehavioralSignal({
    required this.type,
    required this.value,
    required this.occurredAt,
    this.metadata = const {},
  });

  final String type;
  final double value;
  final DateTime occurredAt;
  final Map<String, Object?> metadata;
}
