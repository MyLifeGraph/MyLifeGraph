import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_icons.dart';
import '../application/app_updates.dart';

Future<bool> openAppUpdate(AppUpdate update) async {
  try {
    return await launchUrl(update.url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    required this.update,
    this.open = openAppUpdate,
    super.key,
  });
  final AppUpdate update;
  final Future<bool> Function(AppUpdate) open;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _opening = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Update available'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.update.name),
          if (_failed) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Could not open download. Try again.'),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: _opening
            ? null
            : () async {
                setState(() {
                  _opening = true;
                  _failed = false;
                });
                final opened = await widget.open(widget.update);
                if (!mounted || !context.mounted) return;
                if (opened) {
                  Navigator.of(context).pop();
                } else {
                  setState(() {
                    _opening = false;
                    _failed = true;
                  });
                }
              },
        icon: const Icon(AppIcons.downloadOutlined),
        label: const Text('Download now'),
      ),
    ],
  );
}
