import 'package:flutter/material.dart';
import '../../../../core/theme/app_icons.dart';
import 'capture_calendar_dialog.dart';
export 'capture_calendar_dialog.dart';

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
    this.loadStatuses,
  });
  final DateTime date;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final Future<Map<String, CaptureDayStatus>> Function()? loadStatuses;

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
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (_) => CaptureCalendarDialog(
                  date: date,
                  today: today,
                  loadStatuses: loadStatuses,
                ),
              );
              if (picked == null ||
                  !context.mounted ||
                  DateUtils.isSameDay(picked, date)) {
                return;
              }
              onChanged(picked);
            },
    ),
  );
}
