class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.actionUrl,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String priority;
  final String? actionUrl;
  final DateTime createdAt;
  final bool isRead;
}
