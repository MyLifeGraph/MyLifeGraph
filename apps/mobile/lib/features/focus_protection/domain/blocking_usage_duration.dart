/// Compact display of measured usage, without changing the underlying duration.
String formatBlockingUsageDuration(int milliseconds) {
  if (milliseconds <= 0) return '0m';
  if (milliseconds < 1000) return '<1s';

  var remaining = milliseconds ~/ 1000;
  final parts = <String>[];
  for (final (seconds, unit) in const [
    (86400, 'd'),
    (3600, 'h'),
    (60, 'm'),
    (1, 's'),
  ]) {
    final quantity = remaining ~/ seconds;
    remaining %= seconds;
    if (quantity > 0) parts.add('$quantity$unit');
    if (parts.length == 3) break;
  }
  return parts.join(' ');
}
