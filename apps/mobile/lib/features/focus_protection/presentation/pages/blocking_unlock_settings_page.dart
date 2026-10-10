import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/blocking_gateway.dart';

/// Device-local settings. Native authority rechecks disabled mode and revision.
class BlockingUnlockSettingsPage extends StatefulWidget {
  const BlockingUnlockSettingsPage({
    required this.snapshot,
    required this.gateway,
    required this.methodSummary,
    required this.editMethod,
    required this.focusLocked,
    super.key,
  });
  final BlockingSnapshot snapshot;
  final BlockingGateway gateway;
  final String Function(BlockingSnapshot) methodSummary;
  final Future<void> Function(BuildContext, BlockingSnapshot) editMethod;
  final bool focusLocked;

  @override
  State<BlockingUnlockSettingsPage> createState() => _UnlockSettingsState();
}

class _UnlockSettingsState extends State<BlockingUnlockSettingsPage> {
  late BlockingSnapshot _snapshot = widget.snapshot;
  bool _saving = false;
  String? _error;

  Future<void> _reload() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final next = await widget.gateway.command('status');
      if (mounted) {
        setState(() {
          _snapshot = next;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reload. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _change(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = await widget.gateway.command('stayOnScreen', {
        'enabled': value,
        'revision': _snapshot.revision,
      });
      if (mounted) setState(() => _snapshot = next);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save. Reload and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _method() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.editMethod(context, _snapshot);
      final next = await widget.gateway.command('status');
      if (mounted) setState(() => _snapshot = next);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reload. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _snapshot.strict['enabled'] == true;
    final stay = _snapshot.strict['stayOnScreen'] == true;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        body: AppPage(
          title: 'Unlock settings',
          maxWidth: 640,
          onRefresh: _reload,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AppStatusPill(
                label: enabled ? 'Discipline on' : 'Discipline off',
                icon: AppIcons.lockOutline,
                tone: AppStatusTone.neutral,
              ),
            ),
            AppSurface(
              radius: AppRadii.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stay on screen'),
                    subtitle: Text(
                      stay
                          ? 'Leaving resets the timer.'
                          : 'Timer continues in background.',
                    ),
                    value: stay,
                    onChanged: enabled || widget.focusLocked || _saving
                        ? null
                        : _change,
                  ),
                  const Divider(height: AppSpacing.lg),
                  Text(
                    enabled
                        ? 'Turn off Discipline to change.'
                        : 'Changes apply next time.',
                  ),
                ],
              ),
            ),
            AppSurface(
              radius: AppRadii.lg,
              onTap: _snapshot.locked || widget.focusLocked || _saving
                  ? null
                  : _method,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.timerOutlined),
                title: const Text('Unlock method'),
                subtitle: Text(widget.methodSummary(_snapshot)),
                trailing: const Icon(AppIcons.chevronRight),
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, semanticsLabel: _error),
          ],
        ),
      ),
    );
  }
}
