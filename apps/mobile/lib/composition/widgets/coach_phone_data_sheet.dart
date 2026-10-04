import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/utils/client_uuid.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_surface.dart';
import '../auth_providers.dart';

const coachPhoneDataVersion = 'coach-phone-data-v1';
const coachPhoneConsentVersion = 'coach-phone-consent-v1';

Future<void> showCoachPhoneData(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const CoachPhoneDataSheet(),
    );

class CoachPhoneDataSheet extends ConsumerStatefulWidget {
  const CoachPhoneDataSheet({super.key});
  @override
  ConsumerState<CoachPhoneDataSheet> createState() =>
      _CoachPhoneDataSheetState();
}

class _CoachPhoneDataSheetState extends ConsumerState<CoachPhoneDataSheet> {
  static const _channel = MethodChannel('com.mylifegraph.app/blocking_v2');
  Map<String, dynamic>? _state;
  bool _busy = false;
  bool _consentOpen = false;
  String? _error;
  late final String? _owner;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _sameOwner =>
      ref.read(authControllerProvider).valueOrNull?.profile.id == _owner;
  Map<String, String> _headers() {
    final session = ref.read(supabaseClientProvider)?.auth.currentSession;
    if (_owner == null || !_sameOwner || session?.user.id != _owner) {
      throw StateError('Account changed');
    }
    return {'Authorization': 'Bearer ${session!.accessToken}'};
  }

  @override
  void initState() {
    super.initState();
    _owner = ref.read(authControllerProvider).valueOrNull?.profile.id;
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || !_sameOwner || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && _sameOwner) {
        setState(() => _error = 'Could not confirm. Reload before retrying.');
      }
    } finally {
      if (mounted && _sameOwner) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final value = await ref
        .read(apiClientProvider)
        .getJson('/v1/coach/phone-data', headers: _headers());
    if (value['contract_version'] != coachPhoneDataVersion) {
      throw const FormatException('Unsupported phone data');
    }
    if (mounted && _sameOwner) setState(() => _state = value);
  });
  Future<void> _command(
    String operation, {
    String? device,
    Map? data,
    int? revision,
  }) async {
    final value = await ref
        .read(apiClientProvider)
        .postJson(
          '/v1/coach/phone-data',
          headers: _headers(),
          body: {
            'contract_version': coachPhoneDataVersion,
            'request_id': newClientUuid(),
            'expected_revision': revision ?? _state!['revision'],
            'command': operation,
            'device_id': device,
            'consent_version': operation == 'enable'
                ? coachPhoneConsentVersion
                : null,
            'data': data,
          },
        );
    if (value['contract_version'] != coachPhoneDataVersion) {
      throw const FormatException('Unsupported phone data');
    }
    if (mounted && _sameOwner) setState(() => _state = value);
  }

  Future<void> _toggle(bool value) async {
    if (_busy || _consentOpen || _error != null) return;
    if (!value) {
      await _run(() => _command('disable'));
      return;
    }
    _consentOpen = true;
    final bool? agree;
    try {
      agree = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share phone summaries?'),
          scrollable: true,
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('App time · Top apps · Blocking attempts'),
              SizedBox(height: 12),
              Text(
                'Saved in your cloud account for your selected Coach provider.',
              ),
              SizedBox(height: 12),
              Text(
                'Turning off deletes shared data, not earlier Coach replies.',
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Privacy details'),
                children: [
                  Text(
                    'No messages, notification content or browsing history. Optional and separate from local App Blocking.',
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agree'),
            ),
          ],
        ),
      );
    } finally {
      _consentOpen = false;
    }
    if (agree != true || !mounted || !_sameOwner) return;
    await _run(() async {
      final device = await _channel.invokeMapMethod<String, dynamic>(
        'phoneStatus',
      );
      if (!mounted || !_sameOwner) return;
      if (device?['granted'] != true) {
        await _channel.invokeMethod<void>('phonePermission');
        if (mounted) {
          setState(() => _error = 'Allow usage access, then reload.');
        }
        return;
      }
      await _command('enable', device: device!['device_id'] as String);
    });
    if (mounted && _state?['enabled'] == true && _error == null) await _sync();
  }

  Future<void> _sync() => _run(() async {
    final revision = _state!['revision'] as int;
    final timezone = _state!['timezone'] as String;
    final device = await _channel.invokeMapMethod<String, dynamic>(
      'phoneStatus',
    );
    if (!mounted || !_sameOwner) return;
    if (_state?['enabled'] != true ||
        device?['device_id'] != _state?['device_id']) {
      throw StateError('Reconnect this phone');
    }
    final sample = await _channel.invokeMapMethod<String, dynamic>(
      'phoneData',
      {'timezone': timezone, 'consented': true},
    );
    if (!mounted || !_sameOwner) return;
    await _command(
      'sync',
      device: device!['device_id'] as String,
      data: sample,
      revision: revision,
    );
  });
  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authControllerProvider).valueOrNull?.profile.id;
    if (owner != _owner) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Account changed. Reopen Coach data.'),
        ),
      );
    }
    final data = _state?['data'] as Map?;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(AppIcons.deviceMobile),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Coach data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            AppSurface(
              padding: const EdgeInsets.all(8),
              child: SwitchListTile.adaptive(
                title: const Text('Phone usage'),
                subtitle: const Text(
                  'Optional · No messages or browsing history',
                ),
                value: _state?['enabled'] == true,
                onChanged:
                    _busy ||
                        _state == null ||
                        _error != null ||
                        (!_android && _state?['enabled'] != true)
                    ? null
                    : _toggle,
              ),
            ),
            const SizedBox(height: 16),
            for (final (icon, label) in [
              (AppIcons.schedule, 'Daily app time'),
              (AppIcons.squaresFour, 'Top apps'),
              (AppIcons.shieldOutlined, 'Blocking attempts'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(label),
              ),
            if (data != null)
              ExpansionTile(
                title: const Text('Shared data'),
                children: [
                  Text('Updated: ${data['captured_at']}'),
                  for (final day in data['days'] as List? ?? const [])
                    ListTile(
                      title: Text('${day['date']}'),
                      trailing: Text('${day['minutes']}m'),
                    ),
                  for (final app in data['apps'] as List? ?? const [])
                    ListTile(
                      title: Text('${app['name']}'),
                      trailing: Text('${app['minutes']}m'),
                    ),
                  Text(
                    'Attempts today: ${data['attempts_today'] ?? 'Unavailable'}',
                  ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_android && _state?['enabled'] == true)
              TextButton.icon(
                onPressed: _busy || _error != null ? null : _sync,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Sync now'),
              ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Reload'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: 'Delete shared data',
                    child: TextButton(
                      onPressed: _busy || _state == null || _error != null
                          ? null
                          : () => _run(() => _command('delete')),
                      child: const Text('Delete'),
                    ),
                  ),
                ),
              ],
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
