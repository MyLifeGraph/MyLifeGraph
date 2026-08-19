import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/pilot_participation.dart';

class PilotPrivacyNoticePage extends ConsumerWidget {
  const PilotPrivacyNoticePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      body: AppPage(
        title: 'Pilot privacy notice',
        subtitle: 'Read this before creating an account or entering real data.',
        backFallback: AppRoutes.auth,
        maxWidth: 760,
        children: [
          const _NoticeSection(
            title: 'Purpose and participation',
            body:
                'MyLifeGraph is a first evaluation prototype for personal planning, reflection, and an optional read-only Coach. Participation in this pilot is restricted to people who are 18 or older. The app records a versioned self-attestation and its backend time; it does not ask for or store your birth date.',
          ),
          const _NoticeSection(
            title: 'Data you may choose to enter',
            body:
                'A normal synced account may contain real mood, sleep, stress, energy, study, task, habit, Focus, planning, calendar, reflection, notification, and Coach conversation data. These are personal account records, not anonymous test data. Setup and ordinary product use store data in Supabase. Calendar import and Coach use require separate deliberate actions.',
          ),
          const _NoticeSection(
            title: 'Services involved',
            body:
                'Supabase provides authentication and account storage. Vercel may serve the web client. The project VPS processes authenticated API requests and Coach turns. Google processes data only if you choose Google sign-in. If you choose a BYOK Coach provider, relevant bounded read-only query results are sent to that selected provider. A shared operator Coach, when enabled, processes the same bounded Coach request through the project executor.',
          ),
          const _NoticeSection(
            title: 'Control, export, and deletion',
            body:
                'You can export the bounded product data listed in Settings and can request permanent account deletion. You can stop participating by deleting the account or contacting the project. Backup retention and deletion replay follow the pilot operations procedure; ask the project contact for the currently approved evaluation and backup-retention period before entering data.',
          ),
          _NoticeSection(
            title: 'Project and incident contact',
            body:
                '${config.pilotContactEmail}\nUse this address for privacy questions, withdrawal, access requests, or suspected incidents.',
          ),
          const _NoticeSection(
            title: 'Important limits',
            body:
                'This prototype is not medical, crisis, legal, or professional advice. Rule-based outputs and Coach responses may be incomplete or wrong. Do not enter information you are not comfortable sharing under this notice.',
          ),
          Text(
            'Notice version: $pilotParticipationNoticeVersion',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoticeSection extends StatelessWidget {
  const _NoticeSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: AppSurfaceVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
