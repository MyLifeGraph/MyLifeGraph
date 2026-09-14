import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/coach.dart';

/// Presents uncertainty, not a guarantee of correctness, for current and saved turns.
class CoachUncertaintyView extends StatelessWidget {
  const CoachUncertaintyView({required this.uncertainty, super.key});

  final CoachUncertainty uncertainty;

  @override
  Widget build(BuildContext context) {
    final (label, icon, tone) = switch (uncertainty.level) {
      'low' => ('Low uncertainty', AppIcons.infoOutline, AppStatusTone.success),
      'medium' => (
        'Medium uncertainty',
        AppIcons.warningAmberOutlined,
        AppStatusTone.attention,
      ),
      'high' => (
        'High uncertainty',
        AppIcons.errorOutline,
        AppStatusTone.danger,
      ),
      _ => (
        'Uncertainty unavailable',
        AppIcons.errorOutline,
        AppStatusTone.attention,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusPill(label: label, icon: icon, tone: tone),
        const SizedBox(height: AppSpacing.xs),
        Text(uncertainty.reason),
      ],
    );
  }
}
