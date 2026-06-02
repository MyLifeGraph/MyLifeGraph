import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';

class DeepWorkPage extends StatelessWidget {
  const DeepWorkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: context.pop,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Alerts'),
                    ),
                    const Spacer(),
                    _DeepIcon(
                      icon: Icons.timer_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'FOCUS MODE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 4,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Deep Work',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 48,
                        height: 1,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Start a focused block from an alert, timetable gap, or study plan.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFA8B5BE),
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _FocusStats(),
                const SizedBox(height: AppSpacing.lg),
                const _FocusSessionCard(),
                const SizedBox(height: AppSpacing.lg),
                const _DistractionGuardCard(),
                const SizedBox(height: AppSpacing.lg),
                const _FocusHistoryCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusStats extends StatelessWidget {
  const _FocusStats();

  @override
  Widget build(BuildContext context) {
    const stats = [
      _FocusMetric(Icons.schedule, '0m', 'This week', Color(0xFF5BE7C4)),
      _FocusMetric(
        Icons.local_fire_department_outlined,
        '0',
        'Sessions',
        Color(0xFFFFA42E),
      ),
      _FocusMetric(
        Icons.timer_outlined,
        '0',
        'Distractions',
        Color(0xFF20B9FF),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 0.78,
      children:
          stats.map((metric) => _FocusMetricCard(metric: metric)).toList(),
    );
  }
}

class _FocusMetricCard extends StatelessWidget {
  const _FocusMetricCard({required this.metric});

  final _FocusMetric metric;

  @override
  Widget build(BuildContext context) {
    return _DeepPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, color: metric.color, size: 30),
          const Spacer(),
          Text(metric.value, style: Theme.of(context).textTheme.headlineMedium),
          Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FocusSessionCard extends StatelessWidget {
  const _FocusSessionCard();

  @override
  Widget build(BuildContext context) {
    return _DeepPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DEEP WORK',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 4,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Focus session',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const _StatusBadge(label: 'Ready'),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: SizedBox(
              width: 248,
              height: 248,
              child: CustomPaint(
                painter: _TimerRingPainter(),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Time remaining',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '50:00',
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(fontSize: 64),
                      ),
                      Text(
                        '0% complete',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: const [
              Expanded(child: _DurationButton(label: '25m')),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: _DurationButton(label: '50m', isSelected: true)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: _DurationButton(label: '90m')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: const [
              Expanded(
                child: _ControlButton(
                  icon: Icons.play_arrow,
                  label: 'Start',
                  isPrimary: true,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: _ControlButton(icon: Icons.stop, label: 'Stop')),
              SizedBox(width: AppSpacing.sm),
              _ResetButton(),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistractionGuardCard extends StatelessWidget {
  const _DistractionGuardCard();

  @override
  Widget build(BuildContext context) {
    return _DeepPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DeepIcon(
            icon: Icons.shield_outlined,
            color: Color(0xFFFFA42E),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distraction guard',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Log urges or interruptions. At three, the app switches to a stronger warning.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFA8B5BE),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: const [
                    Expanded(
                      child: _ControlButton(
                        icon: Icons.history_toggle_off,
                        label: 'Log distraction',
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    _CountPill(count: '0'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusHistoryCard extends StatelessWidget {
  const _FocusHistoryCard();

  @override
  Widget build(BuildContext context) {
    return _DeepPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Focus history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text('7 days', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _HistoryPainter(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeepPanel extends StatelessWidget {
  const _DeepPanel({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2A424A), width: 2),
      ),
      child: child,
    );
  }
}

class _DeepIcon extends StatelessWidget {
  const _DeepIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
}

class _DurationButton extends StatelessWidget {
  const _DurationButton({required this.label, this.isSelected = false});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF0C1218),
        foregroundColor: isSelected ? Colors.black : const Color(0xFFA8B5BE),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: () {},
      child: Text(label),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: isPrimary
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF0C1218),
        foregroundColor: isPrimary ? Colors.black : const Color(0xFFEFF4F6),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: () {},
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF242B34),
          foregroundColor: const Color(0xFFEFF4F6),
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: () {},
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final String count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF242B34),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(count, style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF242B34),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF242B34)
      ..strokeWidth = 34
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 24, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HistoryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pillPaint = Paint()..color = const Color(0xFF1F2C34);
    final linePaint = Paint()
      ..color = const Color(0xFF18AEEA)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 24, size.width, size.height * 0.62),
        const Radius.circular(64),
      ),
      pillPaint,
    );
    final y = size.height - 18;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FocusMetric {
  const _FocusMetric(this.icon, this.value, this.label, this.color);

  final IconData icon;
  final String value;
  final String label;
  final Color color;
}
