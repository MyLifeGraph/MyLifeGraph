import 'package:flutter/material.dart';
import '../../../../core/theme/app_icons.dart';

/// Calendar-day arithmetic deliberately avoids 23/25-hour DST day offsets.
DateTime captureDayOffset(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

class CaptureDatePicker extends StatelessWidget {
  const CaptureDatePicker({
    super.key,
    required this.date,
    required this.today,
    required this.onChanged,
    this.enabled = true,
  });
  final DateTime date;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      icon: const Icon(AppIcons.calendarTodayOutlined),
      label: Text(
        DateUtils.isSameDay(date, today)
            ? 'Today · Change date'
            : MaterialLocalizations.of(context).formatMediumDate(date),
      ),
      onPressed: !enabled
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date.isAfter(today)
                    ? today
                    : date.isBefore(captureDayOffset(today, -7))
                    ? captureDayOffset(today, -7)
                    : date,
                firstDate: captureDayOffset(today, -7),
                lastDate: today,
                helpText: 'Check-in date',
              );
              if (picked == null ||
                  !context.mounted ||
                  DateUtils.isSameDay(picked, date)) {
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Change check-in date?'),
                  content: const Text(
                    'Unsaved answers will be replaced by the selected day’s answers.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep editing'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Change date'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) onChanged(picked);
            },
    ),
  );
}
