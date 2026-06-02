class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.summary,
    required this.impact,
    required this.tags,
  });

  final String id;
  final String title;
  final String summary;
  final String impact;
  final List<String> tags;
}
