import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_card.dart';
import '../../features/health_connect/presentation/health_connect_page.dart';

class HealthConnectSettingsEntry extends StatelessWidget {
  const HealthConnectSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(AppIcons.fitnessCenterOutlined),
      title: const Text('Health Connect (optional)'),
      subtitle: const Text('Connect Garmin through Android · steps and sleep'),
      trailing: const Icon(AppIcons.chevronRight),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HealthConnectPage()),
      ),
    ),
  );
}
