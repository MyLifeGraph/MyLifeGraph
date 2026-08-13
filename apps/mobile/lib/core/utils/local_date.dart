String localDateKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

int civilDateDifferenceInDays(String later, String earlier) {
  final laterParts = later.split('-').map(int.parse).toList(growable: false);
  final earlierParts =
      earlier.split('-').map(int.parse).toList(growable: false);
  if (laterParts.length != 3 || earlierParts.length != 3) {
    throw const FormatException('Expected ISO local dates.');
  }
  return DateTime.utc(laterParts[0], laterParts[1], laterParts[2])
      .difference(
        DateTime.utc(
          earlierParts[0],
          earlierParts[1],
          earlierParts[2],
        ),
      )
      .inDays;
}
