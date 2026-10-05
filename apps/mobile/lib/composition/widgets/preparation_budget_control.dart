import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/app_surface_capabilities.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_icons.dart';
import '../../features/settings/domain/account_settings.dart';
import '../../features/settings/presentation/providers/account_settings_providers.dart';
import '../auth_providers.dart';
import '../projection_refresh_providers.dart';

/// Shared account-budget entry for Settings and preparation editors.
/// Fallback values are display-only and never authorize account writes.
class PreparationBudgetControl extends ConsumerStatefulWidget {
  const PreparationBudgetControl({
    super.key,
    this.compact = true,
    this.onSaved,
    this.fallbackKnown = false,
    this.fallbackMinutes,
  });

  final bool compact;
  final VoidCallback? onSaved;
  final bool fallbackKnown;
  final int? fallbackMinutes;

  @override
  ConsumerState<PreparationBudgetControl> createState() =>
      _PreparationBudgetControlState();
}

class _PreparationBudgetControlState
    extends ConsumerState<PreparationBudgetControl> {
  bool _editing = false;
  bool _saving = false;

  bool get _canEdit =>
      ref.read(authControllerProvider).valueOrNull?.isAuthenticated == true &&
      ref.read(appSurfaceCapabilitiesProvider).canUseSyncedExecution;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final synced =
        session?.isAuthenticated == true && capabilities.canUseSyncedExecution;
    final known = synced || widget.fallbackKnown;
    final minutes = synced
        ? session!.profile.dailyPreparationBudgetMinutes
        : widget.fallbackMinutes;
    final enabled = synced && !_editing;
    final icon = _saving
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(AppIcons.editOutlined);
    if (widget.compact) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'All plans · ${!known
                  ? 'Unavailable'
                  : minutes == null
                  ? 'No limit'
                  : '${_formatMinutes(minutes)}/day'}',
            ),
          ),
          IconButton(
            key: const ValueKey('edit-preparation-budget'),
            tooltip: 'Edit daily budget for all exam and assignment plans',
            onPressed: enabled ? _edit : null,
            icon: icon,
          ),
        ],
      );
    }
    return ListTile(
      key: const ValueKey('daily-preparation-budget-setting'),
      enabled: enabled,
      leading: _saving ? icon : const Icon(AppIcons.speedOutlined),
      title: const Text('Daily preparation budget'),
      subtitle: Text(
        !synced
            ? 'Available only for a synced account.'
            : minutes == null
            ? 'Not set. Existing per-plan limits still apply.'
            : '${_formatMinutes(minutes)} total per day across confirmed preparation plans.',
      ),
      trailing: enabled ? const Icon(AppIcons.editOutlined) : null,
      onTap: enabled ? _edit : null,
    );
  }

  Future<void> _edit() async {
    if (_editing || !_canEdit) return;
    final profile = ref.read(authControllerProvider).valueOrNull!.profile;
    setState(() => _editing = true);
    try {
      final choice = await showDialog<_PreparationBudgetChoice>(
        context: context,
        builder: (_) => _PreparationBudgetDialog(
          current: profile.dailyPreparationBudgetMinutes,
        ),
      );
      if (!mounted ||
          choice == null ||
          !_canEdit ||
          ref.read(authControllerProvider).valueOrNull?.profile.id !=
              profile.id ||
          choice.minutes == profile.dailyPreparationBudgetMinutes) {
        return;
      }
      final repository = ref.read(accountSettingsRepositoryProvider);
      final auth = ref.read(authControllerProvider.notifier);
      final refresh = ref.read(projectionRefreshCoordinatorProvider);
      final container = ProviderScope.containerOf(context, listen: false);
      setState(() => _saving = true);
      final saved = await repository.updateDailyPreparationBudget(
        choice.minutes,
        expectedRevision: profile.preparationBudgetRevision,
      );
      if (!auth.mounted ||
          container.read(authControllerProvider).valueOrNull?.profile.id != profile.id ||
          container.read(authControllerProvider).valueOrNull?.isAuthenticated != true) {
        return;
      }
      auth.updateDailyPreparationBudget(
        saved.minutes,
        revision: saved.revision,
      );
      await refresh.preparationBudgetChanged();
      if (mounted) {
        widget.onSaved?.call();
        _message(
          saved.minutes == null
              ? 'Account-wide preparation budget removed.'
              : 'Daily preparation budget set to ${_formatMinutes(saved.minutes!)}.',
        );
      }
    } on AccountPreparationBudgetRejectedException {
      _message('Choose 25 to 480 minutes in five-minute steps.');
    } on AccountPreparationBudgetUpdateOutcomeUnknownException {
      _message(
        'The budget update could not be confirmed. Retry the same value or sign in again before choosing another.',
      );
    } on AccountSettingConflictException {
      _message(
        'Preparation budget changed elsewhere. Reload Settings and try again.',
      );
    } catch (_) {
      _message('Could not update the preparation budget. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
        });
      }
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _PreparationBudgetChoice {
  const _PreparationBudgetChoice(this.minutes);
  final int? minutes;
}

class _PreparationBudgetDialog extends StatefulWidget {
  const _PreparationBudgetDialog({required this.current});
  final int? current;

  @override
  State<_PreparationBudgetDialog> createState() =>
      _PreparationBudgetDialogState();
}

class _PreparationBudgetDialogState extends State<_PreparationBudgetDialog> {
  late final _controller = TextEditingController(
    text: '${widget.current ?? 480}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(_controller.text.trim());
    final valid = minutes != null && isValidDailyPreparationBudget(minutes);
    return AlertDialog(
      scrollable: true,
      title: const Text('Daily preparation budget'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Across all exam and assignment plans. Existing reservations stay unchanged.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('daily-preparation-budget-input'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minutes per day',
                helperText: '25–480 minutes, in five-minute steps.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preset in const [60, 120, 180, 240, 360, 480])
                  ChoiceChip(
                    label: Text(_formatMinutes(preset)),
                    selected: minutes == preset,
                    onSelected: (_) =>
                        setState(() => _controller.text = '$preset'),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _PreparationBudgetChoice(null)),
            child: const Text('Remove budget'),
          ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, _PreparationBudgetChoice(minutes))
              : null,
          child: const Text('Save budget'),
        ),
      ],
    );
  }
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}
