import 'package:flutter/material.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/theme/app_icons.dart';
import '../../domain/quick_check_in.dart';

enum CaptureDayStatus { done, open, unknown }

/// Eight existing date-addressed reads; failures never become missing answers.
Future<Map<String, CaptureDayStatus>> loadCaptureCalendarStatuses(
  QuickCheckInStore store,
  DateTime today, {
  required bool morning,
}) async {
  final result = <String, CaptureDayStatus>{};
  for (var offset = -7; offset <= 0; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final key = dailyCaptureEntryDate(day);
    try {
      final entry = await store.loadToday(day);
      result[key] = entry != null && entry.entryDate != key
          ? CaptureDayStatus.unknown
          : (morning
                ? entry?.morning?.isComplete == true
                : entry?.evening?.isComplete == true)
          ? CaptureDayStatus.done
          : CaptureDayStatus.open;
    } catch (_) {
      result[key] = CaptureDayStatus.unknown;
    }
  }
  return result;
}

class CaptureCalendarDialog extends StatefulWidget {
  const CaptureCalendarDialog({
    super.key,
    required this.date,
    required this.today,
    this.loadStatuses,
  });
  final DateTime date;
  final DateTime today;
  final Future<Map<String, CaptureDayStatus>> Function()? loadStatuses;
  @override
  State<CaptureCalendarDialog> createState() => _CaptureCalendarDialogState();
}

class _CaptureCalendarDialogState extends State<CaptureCalendarDialog> {
  late DateTime _month;
  Map<String, CaptureDayStatus> _statuses = {};
  bool _loading = false;
  bool _unavailable = false;
  DateTime get _today => DateUtils.dateOnly(widget.today);
  DateTime get _first => DateTime(_today.year, _today.month, _today.day - 7);
  bool _allowed(DateTime day) => !day.isBefore(_first) && !day.isAfter(_today);

  @override
  void initState() {
    super.initState();
    final date = _allowed(DateUtils.dateOnly(widget.date))
        ? widget.date
        : _today;
    _month = DateTime(date.year, date.month);
    if (widget.loadStatuses != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final statuses = await widget.loadStatuses!();
      if (mounted) {
        setState(() {
          _statuses = statuses;
          _unavailable = statuses.values.any(
            (s) => s == CaptureDayStatus.unknown,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statuses = {};
          _unavailable = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTokens;
    final local = MaterialLocalizations.of(context);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = _month.weekday - 1;
    final rows = ((days + offset) / 7).ceil();
    final previous = DateTime(_month.year, _month.month, 0);
    final next = DateTime(_month.year, _month.month + 1);
    // No LayoutBuilder inside AlertDialog's intrinsic sizing pass.
    final circleSize =
        (((MediaQuery.sizeOf(context).width -
                            MediaQuery.paddingOf(context).horizontal -
                            12)
                        .clamp(0.0, 336.0) /
                    7) -
                8)
            .clamp(0.0, 40.0)
            .toDouble();
    return AlertDialog(
      title: const Text('Check-in date', textAlign: TextAlign.center),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      content: SizedBox(
        width: 336,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: local.previousMonthTooltip,
                  onPressed: previous.isBefore(_first)
                      ? null
                      : () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month - 1),
                        ),
                  icon: const Icon(AppIcons.chevronLeft),
                ),
                Expanded(
                  child: Text(
                    local.formatMonthYear(_month),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: local.nextMonthTooltip,
                  onPressed: next.isAfter(_today)
                      ? null
                      : () => setState(() => _month = next),
                  icon: const Icon(AppIcons.chevronRight),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      local.narrowWeekdays[(i + 1) % 7],
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var row = 0; row < rows; row++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (_) {
                          final number = row * 7 + col - offset + 1;
                          if (number < 1 || number > days) {
                            return const SizedBox(height: 48);
                          }
                          final day = DateTime(
                            _month.year,
                            _month.month,
                            number,
                          );
                          final enabled = _allowed(day);
                          final today = DateUtils.isSameDay(day, _today);
                          final selected = DateUtils.isSameDay(
                            day,
                            widget.date,
                          );
                          final status = enabled
                              ? _statuses[dailyCaptureEntryDate(day)]
                              : null;
                          final color = status == CaptureDayStatus.done
                              ? tokens.success
                              : status == CaptureDayStatus.open
                              ? tokens.danger
                              : null;
                          final statusLabel = status == CaptureDayStatus.done
                              ? 'Done'
                              : status == CaptureDayStatus.open
                              ? 'Open'
                              : 'Status unavailable';
                          return Semantics(
                            button: enabled,
                            enabled: enabled,
                            selected: selected,
                            onTap: enabled
                                ? () => Navigator.pop(context, day)
                                : null,
                            label:
                                '${local.formatFullDate(day)}${today ? ', Today' : ''}, $statusLabel',
                            excludeSemantics: true,
                            child: SizedBox(
                              height: 48,
                              child: TextButton(
                                key: Key(
                                  'capture-day-${dailyCaptureEntryDate(day)}',
                                ),
                                onPressed: enabled
                                    ? () => Navigator.pop(context, day)
                                    : null,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(44, 44),
                                  foregroundColor: today
                                      ? tokens.onBrand
                                      : tokens.textPrimary,
                                  backgroundColor: Colors.transparent,
                                  disabledForegroundColor: tokens.textSecondary,
                                  shape: const CircleBorder(),
                                ),
                                child: Container(
                                  key: Key(
                                    'capture-day-face-${dailyCaptureEntryDate(day)}',
                                  ),
                                  width: circleSize,
                                  height: circleSize,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: today
                                        ? tokens.brand
                                        : selected
                                        ? tokens.surfaceInteractive
                                        : Colors.transparent,
                                    border: Border.fromBorderSide(
                                      today
                                          ? BorderSide(color: tokens.brand)
                                          : color != null
                                          ? BorderSide(color: color, width: 1)
                                          : selected
                                          ? BorderSide(
                                              color: tokens.outlineSoft,
                                            )
                                          : BorderSide.none,
                                    ),
                                  ),
                                  child: Text(
                                    '$number',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: !enabled
                                              ? tokens.textSecondary
                                              : today
                                              ? tokens.onBrand
                                              : tokens.textPrimary,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_unavailable)
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Status unavailable · Retry'),
              ),
          ],
        ),
      ),
      actions: [
        if (MediaQuery.textScalerOf(context).scale(14) > 16.8)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _legend('Done', tokens.success),
                  _legend('Open', tokens.danger),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(local.cancelButtonLabel),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _legend('Done', tokens.success),
                    _legend('Open', tokens.danger),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(local.cancelButtonLabel),
              ),
            ],
          ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color),
        ),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
