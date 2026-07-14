class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.summary,
    required this.confidence,
    required this.tags,
  });

  final String id;
  final String title;
  final String summary;
  final double? confidence;
  final List<String> tags;

  String get confidenceLabel => confidence == null
      ? 'Confidence not stored'
      : '${(confidence! * 100).floor()}% confidence';
}
