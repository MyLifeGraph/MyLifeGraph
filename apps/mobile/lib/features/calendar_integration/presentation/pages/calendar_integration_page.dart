import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
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
      subtitle: 'Optional, explicit, and read-only',
      actions: [
        IconButton(
          tooltip: 'Reload calendar state',
          onPressed: state.isBusy ? null : controller.load,
          icon: const Icon(Icons.refresh),
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
          icon: Icons.cloud_off_outlined,
          title: 'Calendar import unavailable',
          message:
              'The calendar status could not be read. It was not replaced with a disconnected or demo state.',
          actionLabel: 'Retry calendar status',
          onAction: controller.load,
        ),
      ];
    }
    final feed = state.feed!;
    if (feed.origin == CalendarIntegrationOrigin.localDemo) {
      return const [
        _MessageCard(
          icon: Icons.cloud_off_outlined,
          title: 'Calendar import unavailable in local demo',
          message:
              'Calendar import requires a synced account. Nothing was connected or imported, and the standalone app remains available.',
        ),
      ];
    }

    final connection = feed.connection;
    final deleted = connection?.importedDataDeleted == true;
    return [
      const _ReadOnlyPromiseCard(),
      if (connection == null)
        _ConnectionSetupCard(state: state, controller: controller)
      else if (deleted) ...[
        _MessageCard(
          icon: Icons.delete_outline,
          title: 'Imported data deleted',
          message:
              'Any local imported copy and import history were deleted. The original calendar was never changed.',
        ),
        _ConnectionSetupCard(state: state, controller: controller),
      ] else ...[
        _ConnectionStatusCard(connection: connection),
        if (connection.isConnected)
          _ImportFileCard(state: state, controller: controller),
        _ImportedEventsCard(state: state, controller: controller),
        _SourceControlsCard(
          state: state,
          controller: controller,
          connection: connection,
        ),
      ],
      if (state.operationError != null)
        _OperationErrorCard(state: state, controller: controller),
    ];
  }
}

class _ReadOnlyPromiseCard extends StatelessWidget {
  const _ReadOnlyPromiseCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Read-only import',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'You choose one UTF-8 .ics file. MyLifeGraph stores only bounded event basics, never writes to a calendar provider, and never sends imported content to an LLM.',
          ),
        ],
      ),
    );
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
    final canCreate = !state.isBusy &&
        (state.retryKind == null ||
            state.retryKind == CalendarIntegrationRetryKind.create) &&
        state.consentAccepted &&
        label.isNotEmpty &&
        label.runes.length <= 80;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect an import source',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Creating this source records consent only. No file is read until you deliberately choose and import one.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('calendar-source-label'),
            initialValue: state.sourceLabel,
            enabled: !fieldsLocked,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Source label',
              hintText: 'Work calendar',
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
              'Read calendar events and store event basics only. Provider writes and LLM processing remain off.',
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
                : const Icon(Icons.add_link),
            label: Text(
              state.operation == CalendarIntegrationOperation.creating
                  ? 'Creating…'
                  : state.retryKind == CalendarIntegrationRetryKind.create
                      ? 'Retry exact connection'
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
    final connected = connection.isConnected;
    final lastImport = connection.lastImport;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  connection.sourceLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _StatusPill(
                label: connected
                    ? 'Connected'
                    : lastImport == null
                        ? 'Disconnected'
                        : 'Disconnected · stale',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            connected
                ? 'This file source accepts deliberate imports. It has no live provider access.'
                : lastImport == null
                    ? 'Further imports are disabled. No file was imported; clear this empty source before creating another.'
                    : 'Further imports are disabled. The retained local copy remains read-only and stale until you delete it.',
          ),
          if (lastImport != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Last import: ${lastImport.importedAt.toUtc().toIso8601String()} · '
              '${lastImport.window.startsOn} to before ${lastImport.window.endsBefore} · '
              '${lastImport.window.timezone}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${lastImport.counts.accepted} accepted · '
              '${lastImport.counts.cancelled} cancelled · '
              '${lastImport.counts.outOfWindow} outside window · '
              '${lastImport.counts.unsupportedRecurring} recurring unsupported · '
              '${lastImport.counts.invalid} invalid',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            const Text('No file has been imported yet.'),
          ],
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
    final locked = state.isBusy || state.operationRequiresExactRetry;
    final canImport = !state.isBusy &&
        (state.retryKind == null ||
            state.retryKind == CalendarIntegrationRetryKind.import);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import a file', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Maximum 512 KiB. A complete valid import atomically replaces the current bounded imported copy.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: locked ? null : controller.selectFile,
            icon: state.operation == CalendarIntegrationOperation.selectingFile
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_open_outlined),
            label: const Text('Choose .ics file'),
          ),
          if (file != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('${file.name} · ${file.byteLength} bytes'),
                  ),
                  IconButton(
                    tooltip: 'Clear selected file',
                    onPressed: locked ? null : controller.clearSelectedFile,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: canImport ? controller.importSelectedFile : null,
              icon: state.operation == CalendarIntegrationOperation.importing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(
                state.operation == CalendarIntegrationOperation.importing
                    ? 'Importing…'
                    : state.retryKind == CalendarIntegrationRetryKind.import
                        ? 'Retry exact import'
                        : 'Import selected file',
              ),
            ),
          ],
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
          Text(
            'Imported events',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Context only. These are not commitments or plan items.'),
          const SizedBox(height: AppSpacing.md),
          if (state.eventError != null) ...[
            const Text(
              'Imported events are unavailable. The connection status and the rest of the app remain unchanged.',
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload imported events'),
            ),
          ] else if (!hasImport)
            const Text('No file has been imported yet.')
          else if (state.events.isEmpty)
            const Text('No events in this import window.')
          else ...[
            for (final event in state.events) ...[
              _ImportedEventTile(event: event),
              const Divider(),
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
                        : const Icon(Icons.expand_more),
                label: const Text('Load more imported events'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ImportedEventTile extends StatelessWidget {
  const _ImportedEventTile({required this.event});

  final CalendarImportedEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatusPill(label: 'Imported · read-only'),
          const SizedBox(height: AppSpacing.xs),
          Text(event.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('${event.displayDate} · ${event.displayTime}'),
          Text('${event.eventTimezone} · ${event.provenance.sourceLabel}'),
          if (event.location != null) Text(event.location!),
        ],
      ),
    );
  }
}

class _SourceControlsCard extends StatelessWidget {
  const _SourceControlsCard({
    required this.state,
    required this.controller,
    required this.connection,
  });

  final CalendarIntegrationState state;
  final CalendarIntegrationController controller;
  final CalendarConnection connection;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Source controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (connection.isConnected)
            OutlinedButton.icon(
              onPressed: state.isBusy ||
                      state.retryKind != null &&
                          state.retryKind !=
                              CalendarIntegrationRetryKind.disconnect
                  ? null
                  : () async {
                      final confirmed = await _confirmDisconnect(context);
                      if (confirmed) await controller.disconnect();
                    },
              icon: const Icon(Icons.link_off),
              label: Text(
                state.retryKind == CalendarIntegrationRetryKind.disconnect
                    ? 'Retry exact disconnect'
                    : 'Disconnect source',
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: state.isBusy ||
                      state.retryKind != null &&
                          state.retryKind != CalendarIntegrationRetryKind.delete
                  ? null
                  : () async {
                      final confirmed = await _confirmDelete(context);
                      if (confirmed) await controller.deleteImportedData();
                    },
              icon: const Icon(Icons.delete_outline),
              label: Text(
                state.retryKind == CalendarIntegrationRetryKind.delete
                    ? 'Retry exact deletion'
                    : 'Delete imported data',
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmDisconnect(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnect calendar source?'),
            content: const Text(
              'Further imports will stop. The imported local copy remains visible as stale, and the source calendar is not changed.',
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
                ? 'Calendar operation result uncertain'
                : 'Calendar operation failed',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            exact
                ? 'Retry the exact unchanged request or reload server state. Submitted values or file, where applicable, and the request identity were retained.'
                : _errorMessage(state.operationError!),
          ),
          if (exact) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload server state'),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String _errorMessage(Object error) => switch (error) {
      CalendarFileSelectionException(:final message) => message,
      CalendarIntegrationAccessException(:final message) => message,
      CalendarIntegrationContractException(:final message) => message,
      _ =>
        'The operation could not be completed. Check the file or connection and try again.',
    };
