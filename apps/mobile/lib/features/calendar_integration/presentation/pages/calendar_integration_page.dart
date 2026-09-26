import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/calendar_ics_file_picker.dart';
import '../../application/calendar_integration_controller.dart';
import '../../data/calendar_integration_repository_impl.dart';
import '../../domain/calendar_integration.dart';
import '../providers/calendar_integration_providers.dart';

class CalendarIntegrationPage extends ConsumerWidget {
  const CalendarIntegrationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarIntegrationControllerProvider);
    final controller = ref.read(calendarIntegrationControllerProvider.notifier);

    return AppPage(
      title: 'Calendar import',
      compactHeader: true,
      backFallback: AppRoutes.settings,
      actions: [
        IconButton(
          tooltip: 'Reload calendar state',
          onPressed: state.isBusy ? null : controller.load,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: _children(context, state, controller),
    );
  }

  List<Widget> _children(
    BuildContext context,
    CalendarIntegrationState state,
    CalendarIntegrationController controller,
  ) {
    if (state.isLoading) {
      return const [
        AppCard(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ];
    }
    if (state.loadError != null) {
      return [
        _MessageCard(
          icon: AppIcons.cloudOffOutlined,
          title: 'Calendar import unavailable',
          message:
              'The calendar status could not be read. Check your connection and try again.',
          actionLabel: 'Retry calendar status',
          onAction: controller.load,
        ),
      ];
    }
    final feed = state.feed!;
    if (feed.origin == CalendarIntegrationOrigin.localDemo) {
      return const [
        _MessageCard(
          icon: AppIcons.cloudOffOutlined,
          title: 'Calendar import unavailable in local demo',
          message:
              'Calendar import requires a synced account. Nothing was connected or imported, and the standalone app remains available.',
        ),
      ];
    }

    final connection = feed.connection;
    final deleted = connection?.importedDataDeleted == true;
    return [
      if (connection == null) ...[
        _ConnectionSetupCard(state: state, controller: controller),
      ] else if (deleted) ...[
        _MessageCard(
          icon: AppIcons.deleteOutline,
          title: 'Imported data deleted',
          message:
              'Imported event content was deleted. A minimal audit record remains, and the original calendar was never changed.',
        ),
        _ConnectionSetupCard(state: state, controller: controller),
      ] else ...[
        LayoutBuilder(builder: (context, constraints) {
          final source = _ImportFileCard(state: state, controller: controller);
          final hasEvents = connection.lastImport != null || state.eventError != null;
          final events = _ImportedEventsCard(state: state, controller: controller);
          final details = connection.lastImport == null
              ? null
              : _ConnectionStatusCard(connection: connection);
          if (constraints.maxWidth >= 900 &&
              MediaQuery.textScalerOf(context).scale(16) < 24 && hasEvents) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [
                  source,
                  if (details != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    details,
                  ],
                ])),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: events),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              source,
              if (hasEvents) ...[
                const SizedBox(height: AppSpacing.md),
                events,
              ],
              if (details != null) ...[
                const SizedBox(height: AppSpacing.md),
                details,
              ],
            ],
          );
        }),
      ],
      if (state.operationError != null)
        _OperationErrorCard(state: state, controller: controller),
    ];
  }
}


class _ConnectionSetupCard extends StatelessWidget {
  const _ConnectionSetupCard({required this.state, required this.controller});

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;

  @override
  Widget build(BuildContext context) {
    final fieldsLocked = state.isBusy || state.operationRequiresExactRetry;
    final label = state.sourceLabel.trim();
    final canCreate =
        !state.isBusy &&
        (state.retryKind == null ||
            state.retryKind == CalendarIntegrationRetryKind.create) &&
        state.consentAccepted &&
        label.isNotEmpty &&
        label.runes.length <= 80;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppInfoSectionDisclosure(
            heading: 'Set up file import',
            description:
                'Creating this source records consent only. No file is read '
                'until you deliberately choose and import one.',
            keyPrefix: 'calendar-info',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Name your calendar, then allow read-only import.'),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('calendar-source-label'),
            initialValue: state.sourceLabel,
            enabled: !fieldsLocked,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Calendar name',
              hintText: 'Work calendar',
              counterText: '',
            ),
            onChanged: controller.updateSourceLabel,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: state.consentAccepted,
            onChanged: fieldsLocked
                ? null
                : (value) => controller.setConsentAccepted(value ?? false),
            title: const Text('I consent to this read-only import'),
            subtitle: const Text(
              'Read calendar events and store event basics only. MyLifeGraph will not change the source calendar or send event text to AI.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: canCreate ? controller.createConnection : null,
            icon: state.operation == CalendarIntegrationOperation.creating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.addLink),
            label: Text(
              state.operation == CalendarIntegrationOperation.creating
                  ? 'Creating…'
                  : state.retryKind == CalendarIntegrationRetryKind.create
                  ? 'Retry unchanged'
                  : 'Create read-only source',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.connection});
  final CalendarConnection connection;

  @override
  Widget build(BuildContext context) {
    final lastImport = connection.lastImport!;
    return AppCard(
      child: ExpansionTile(
        key: const ValueKey('calendar-import-details'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Last import'),
        subtitle: Text(_formatImportedAt(lastImport.importedAt)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Window: ${lastImport.window.startsOn} to before ${lastImport.window.endsBefore} · '
              '${lastImport.window.timezone}\n'
              '${lastImport.counts.accepted} accepted · '
              '${lastImport.counts.cancelled} cancelled · '
              '${lastImport.counts.outOfWindow} outside window · '
              '${lastImport.counts.unsupportedRecurring} recurring unsupported · '
              '${lastImport.counts.invalid} invalid',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportFileCard extends StatelessWidget {
  const _ImportFileCard({required this.state, required this.controller});

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;

  @override
  Widget build(BuildContext context) {
    final file = state.selectedFile;
    final connection = state.feed!.connection!;
    final locked = state.isBusy || state.operationRequiresExactRetry;
    final canImport =
        !state.isBusy &&
        (state.retryKind == null ||
            state.retryKind == CalendarIntegrationRetryKind.import);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.calendarTodayOutlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(connection.sourceLabel,
                  style: Theme.of(context).textTheme.titleMedium)),
              _SourceControlsMenu(state: state, controller: controller,
                  connection: connection),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStatusPill(
            label: !connection.isConnected
                ? 'Disconnected'
                : connection.lastImport == null
                    ? 'No file imported'
                    : 'Imported · read-only',
            tone: !connection.isConnected
                ? AppStatusTone.attention
                : AppStatusTone.info,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('File import · No sync'),
          if (!connection.isConnected) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(connection.lastImport == null
                ? 'Imports off. Remove this empty source to add another.'
                : 'Imports off. Saved events may be out of date until deleted.'),
          ],
          if (connection.lastImport?.planningStatus ==
              CalendarImportPlanningStatus.profileTimezoneChanged) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Profile timezone changed. Re-import this file before Planner uses it as busy time.'),
          ],
          const SizedBox(height: AppSpacing.md),
          if (connection.isConnected) SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
            onPressed: locked ? null : controller.selectFile,
            icon: state.operation == CalendarIntegrationOperation.selectingFile
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.downloadOutlined),
            label: const Text('Choose .ics file'),
            ),
          ),
          if (file != null && connection.isConnected) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.descriptionOutlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${file.name} · ${_fileSizeLabel(file.byteLength)}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear selected file',
                    onPressed: locked ? null : controller.clearSelectedFile,
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Importing replaces the saved copy, not your original calendar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: canImport ? controller.importSelectedFile : null,
              icon: state.operation == CalendarIntegrationOperation.importing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.downloadOutlined),
              label: Text(
                state.operation == CalendarIntegrationOperation.importing
                    ? 'Importing…'
                    : state.retryKind == CalendarIntegrationRetryKind.import
                    ? 'Retry unchanged'
                    : 'Import selected file',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const AppInfoSectionDisclosure(
            heading: 'Original calendar unchanged',
            description: 'Choose one UTF-8 .ics file, up to 512 KiB. '
                'No live connection. Only essential event details are saved.',
            keyPrefix: 'calendar-info',
          ),
        ],
      ),
    );
  }
}

class _ImportedEventsCard extends StatelessWidget {
  const _ImportedEventsCard({required this.state, required this.controller});

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;

  @override
  Widget build(BuildContext context) {
    final connection = state.feed!.connection!;
    final hasImport = connection.lastImport != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Imported events',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!connection.isConnected) const AppStatusPill(
            label: 'Imported · read-only',
            tone: AppStatusTone.info,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.eventError != null) ...[
            const Text(
              'Imported events are unavailable. The connection status and the rest of the app remain unchanged.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : controller.load,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Reload imported events'),
            ),
          ] else if (!hasImport)
            const Text('No file has been imported yet.')
          else if (state.events.isEmpty)
            const Text('No events in this import window.')
          else ...[
            for (final event in state.events) ...[
              _ImportedEventTile(
                event: event,
                canPlanPreparation: connection.isConnected,
              ),
            ],
            if (state.nextCursor != null)
              OutlinedButton.icon(
                onPressed: state.isBusy ? null : controller.loadMoreEvents,
                icon:
                    state.operation == CalendarIntegrationOperation.loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.expandMore),
                label: const Text('Load more imported events'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ImportedEventTile extends StatelessWidget {
  const _ImportedEventTile({
    required this.event,
    required this.canPlanPreparation,
  });

  final CalendarImportedEvent event;
  final bool canPlanPreparation;

  @override
  Widget build(BuildContext context) {
    final preparationLocation = calendarPreparationPlanLocation(event);
    final canPlan = canPlanPreparation && preparationLocation != null;
    return ExpansionTile(
      key: ValueKey('calendar-event-${event.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      leading: const Icon(AppIcons.calendarTodayOutlined, size: 20),
      title: Text(event.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        '${event.displayDate} · ${event.displayTime}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${event.eventTimezone} · ${event.provenance.sourceLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (event.location != null)
              Text(
                event.location!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (canPlan) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'For an exam or assignment. Review a plan before scheduling.',
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: ValueKey('plan-preparation-${event.id}'),
                  onPressed: () {
                    context.push(preparationLocation.toString());
                  },
                  icon: const Icon(AppIcons.eventAvailableOutlined),
                  label: const Text('Plan study time'),
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                canPlanPreparation
                    ? 'Study planning is available for upcoming events only.'
                    : 'Import disconnected. Study planning is unavailable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

Uri? calendarPreparationPlanLocation(
  CalendarImportedEvent event, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (event.kind == CalendarEventKind.timed) {
    final deadline = DateTime.tryParse(event.startsAt ?? '');
    if (deadline == null || !deadline.isAfter(current)) return null;
    return Uri(
      path: AppRoutes.preparationPlans,
      queryParameters: {'calendar_event_id': event.id},
    );
  }
  final date = DateTime.tryParse(event.startsOn ?? '');
  if (date == null) return null;
  final today = DateTime(current.year, current.month, current.day);
  final sourceDate = DateTime(date.year, date.month, date.day);
  if (sourceDate.isBefore(today)) return null;
  return Uri(
    path: AppRoutes.preparationPlans,
    queryParameters: {'calendar_event_id': event.id},
  );
}

class _SourceControlsMenu extends StatelessWidget {
  const _SourceControlsMenu({
    required this.state,
    required this.controller,
    required this.connection,
  });

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;
  final CalendarConnection connection;

  @override
  Widget build(BuildContext context) {
    final emptySource = connection.lastImport == null;
    final retryKind = connection.isConnected
        ? CalendarIntegrationRetryKind.disconnect
        : CalendarIntegrationRetryKind.delete;
    final enabled =
        !state.isBusy &&
        (state.retryKind == null || state.retryKind == retryKind);
    final icon = connection.isConnected && !emptySource
        ? AppIcons.linkOff
        : AppIcons.deleteOutline;
    Future<void> act() async {
      if (emptySource) {
        if (await _confirmRemoveEmpty(context)) {
          await controller.removeEmptySource();
        }
      } else if (connection.isConnected) {
        if (await _confirmDisconnect(context)) await controller.disconnect();
      } else {
        if (await _confirmDelete(context)) {
          await controller.deleteImportedData();
        }
      }
    }

    if (state.retryKind == retryKind) {
      return TextButton(
        onPressed: enabled ? act : null,
        child: const Text('Retry unchanged'),
      );
    }
    return PopupMenuButton<bool>(
      tooltip: 'Source actions',
      enabled: enabled,
      icon: const Icon(AppIcons.moreHoriz),
      onSelected: (_) => act(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  emptySource
                      ? 'Remove source'
                      : connection.isConnected
                      ? 'Disconnect source'
                      : 'Delete imported data',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmDisconnect(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnect calendar source?'),
            content: const Text(
              'Further imports will stop. The saved read-only copy remains visible but may become out of date. The source calendar is not changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmRemoveEmpty(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove empty source?'),
            content: const Text(
              'No file was imported. Removes this source so you can add another. '
              'Your calendar and plans stay unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove source'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete imported calendar data?'),
            content: const Text(
              'This permanently clears any local imported events and import history and releases the disconnected source. Manual and Setup commitments remain unchanged, and no source calendar is contacted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete local imported data'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _OperationErrorCard extends StatelessWidget {
  const _OperationErrorCard({required this.state, required this.controller});

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;

  @override
  Widget build(BuildContext context) {
    final exact = state.operationRequiresExactRetry;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exact
                ? 'Could not confirm the calendar change'
                : 'Could not update the calendar copy',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            exact
                ? 'The result could not be confirmed. Your submitted values or file are still here. Retry unchanged or load the latest calendar state.'
                : _errorMessage(state.operationError!),
          ),
          if (exact) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : controller.load,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Load latest calendar state'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _errorMessage(Object error) => switch (error) {
  CalendarFileSelectionException(:final message) => message,
  CalendarIntegrationAccessException() =>
    'Your calendar session is no longer available. Load the latest calendar state and try again.',
  CalendarIntegrationContractException() =>
    'Calendar data could not be read safely. Load the latest calendar state before trying again.',
  _ =>
    'The operation could not be completed. Check the file or connection and try again.',
};

String _formatImportedAt(DateTime value) =>
    '${DateFormat.yMMMd().add_Hm().format(value.toLocal())} local time';

String _fileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kibibytes = bytes / 1024;
  final decimals = kibibytes >= 10 ? 0 : 1;
  return '${kibibytes.toStringAsFixed(decimals)} KiB';
}
