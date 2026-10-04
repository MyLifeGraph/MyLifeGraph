import '../../domain/blocking_plan.dart';

/// Display-only, device-local summary. Native status remains enforcement truth.
String blockingPlanKinds(BlockingPlan plan, DateTime now) => [
  if (plan.focus) 'Focus',
  if (plan.windows.isNotEmpty) 'Weekly',
  if (plan.always) 'Always',
  if (plan.until > now.millisecondsSinceEpoch) 'Timer',
  if (plan.budget > 0) 'Daily limit',
].join(' · ');

String blockingPlanTiming(
  BlockingPlan plan, {
  required DateTime now,
  required bool usageGranted,
}) {
  if (!plan.enabled || plan.pausedUntil > now.millisecondsSinceEpoch) {
    return 'Paused';
  }
  final timed = plan.until > now.millisecondsSinceEpoch;
  final kinds = [
    plan.focus,
    plan.always,
    plan.windows.isNotEmpty,
    timed,
    plan.budget > 0,
  ].where((value) => value).length;
  if (plan.budget > 0 && kinds == 1) {
    if (!usageGranted) return 'Usage unavailable';
    final left = (plan.budget * 60000 - plan.usedMs).clamp(
      0,
      plan.budget * 60000,
    );
    return 'All day · ${(left / 60000).ceil()}m left';
  }
  if (!plan.active) {
    return kinds == 0 && plan.until > 0 ? 'Expired' : 'Scheduled';
  }
  if (plan.always) return 'All day';
  // A finite rule must not claim protection ends while another OR rule holds.
  if (kinds != 1) return 'Active';
  DateTime? end;
  if (timed) {
    end = DateTime.fromMillisecondsSinceEpoch(plan.until, isUtc: now.isUtc);
  } else if (plan.windows.isNotEmpty) {
    bool inWindow(DateTime at) {
      final minute = at.hour * 60 + at.minute;
      final yesterday = at.weekday == 1 ? 7 : at.weekday - 1;
      return plan.windows.any(
        (w) => w.start < w.end
            ? w.days.contains(at.weekday) && minute >= w.start && minute < w.end
            : (w.days.contains(at.weekday) && minute >= w.start) ||
                  (w.days.contains(yesterday) && minute < w.end),
      );
    }

    if (!inWindow(now)) return 'Active'; // Status refresh may be pending.
    // Advance actual minutes so repeated/skipped DST hours retain device truth.
    var candidate = now.subtract(
      Duration(
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond,
      ),
    );
    for (var minute = 0; minute < 8 * 24 * 60; minute++) {
      candidate = candidate.add(const Duration(minutes: 1));
      if (!inWindow(candidate)) {
        end = candidate;
        break;
      }
    }
    if (end == null) return 'All day';
  }
  if (end == null) return 'Active';
  final clock =
      '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  final sameDay =
      end.year == now.year && end.month == now.month && end.day == now.day;
  return 'Active until ${sameDay ? '' : '${end.day}/${end.month} · '}$clock';
}
