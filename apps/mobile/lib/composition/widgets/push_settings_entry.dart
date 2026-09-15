import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_card.dart';
import '../../features/notifications/presentation/pages/push_settings_page.dart';

class PushSettingsEntry extends StatelessWidget {
  const PushSettingsEntry({super.key});
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(AppIcons.notificationsActiveOutlined),
      title: const Text('Push reminders'),
      subtitle: const Text('Important reminders on Android'),
      trailing: const Icon(AppIcons.chevronRight),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const PushSettingsPage())),
    ),
  );
}
