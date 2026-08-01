import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../application/focus_protection_gateway.dart';
import '../../domain/focus_protection.dart';

class FocusProtectionSettingsPage extends ConsumerStatefulWidget {
  const FocusProtectionSettingsPage({super.key});

  @override
  ConsumerState<FocusProtectionSettingsPage> createState() =>
      _FocusProtectionSettingsPageState();
}

class _FocusProtectionSettingsPageState
    extends ConsumerState<FocusProtectionSettingsPage>
    with WidgetsBindingObserver {
  FocusProtectionStatus? _status;
  List<InstalledLaunchableApp>? _apps;
  String _query = '';
  bool _busy = true;
  String? _error;
  int _operationGeneration = 0;

  bool get _configurationLocked => _status?.lease?.isActive == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _operationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final configuration = status?.configuration;
    final enabled = configuration?.enabled == true;
    final controlsEnabled = !_busy && !_configurationLocked;
    final apps = (_apps ?? const <InstalledLaunchableApp>[])
        .where(
          (app) =>
              _query.isEmpty ||
              app.label.toLowerCase().contains(_query.toLowerCase()) ||
              app.packageName.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);

    return AppPage(
      title: 'Focus protection',
      subtitle: 'Optional device-only protection for synced Focus sessions',
      backFallback: AppRoutes.settings,
      actions: [
        IconButton(
          tooltip: 'Refresh protection status',
          onPressed: _busy ? null : _load,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: [
        if (_busy && status == null)
          const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (_error != null && status == null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protection status unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(_error!),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        else if (configuration != null) ...[
          if (_configurationLocked)
            const AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.lockOutline),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'A protected Focus session is active. Finish, abandon, wait for its planned end, or use the emergency release before changing these settings.',
                    ),
                  ),
                ],
              ),
            ),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('focus-protection-master-switch'),
              value: configuration.enabled,
              onChanged: controlsEnabled
                  ? (value) => _save(configuration.copyWith(enabled: value))
                  : null,
              secondary: const Icon(AppIcons.lockOutline),
              title: const Text('Protect new Focus sessions'),
              subtitle: const Text(
                'Off by default. When on, available protection starts after a synced Focus session is confirmed.',
              ),
            ),
          ),
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: configuration.blockSelectedApps,
                  onChanged: controlsEnabled && enabled
                      ? (value) => _save(
                            configuration.copyWith(blockSelectedApps: value),
                          )
                      : null,
                  title: const Text('Block selected apps'),
                  subtitle: const Text(
                    'Shows a full-screen local block page. Browsers can only be blocked as whole apps.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: configuration.silenceNotifications,
                  onChanged: controlsEnabled && enabled
                      ? (value) => _save(
                            configuration.copyWith(
                              silenceNotifications: value,
                            ),
                          )
                      : null,
                  title: const Text('Silence normal notifications'),
                  subtitle: const Text(
                    'Uses one MyLifeGraph Focus rule. Alarms, favorite callers, repeated callers, and media stay allowed.',
                  ),
                ),
              ],
            ),
          ),
          _PermissionCard(
            title: 'Accessibility access',
            description: status!.accessibilityEnabled
                ? 'Allowed. Only foreground package changes are observed.'
                : 'Needed only to recognize and cover selected apps.',
            granted: status.accessibilityEnabled,
            enabled: !_busy,
            onPressed: _openAccessibilitySettings,
          ),
          _PermissionCard(
            title: 'Do Not Disturb access',
            description: status.notificationPolicyGranted
                ? 'Allowed for the MyLifeGraph Focus rule.'
                : 'Needed only for notification silencing.',
            granted: status.notificationPolicyGranted,
            enabled: !_busy,
            onPressed: _openNotificationPolicySettings,
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Apps to block',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text('${configuration.selectedPackages.length} selected'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Only package names are saved on this device. The app list and your choices are never uploaded.',
                ),
                const SizedBox(height: AppSpacing.md),
                if (_apps == null)
                  OutlinedButton(
                    key: const ValueKey('load-focus-protection-apps'),
                    onPressed: controlsEnabled && enabled
                        ? _loadAppsWithDisclosure
                        : null,
                    child: const Text('Choose apps'),
                  )
                else ...[
                  TextField(
                    enabled: controlsEnabled && enabled,
                    decoration: const InputDecoration(
                      labelText: 'Search installed apps',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (apps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No matching selectable apps.'),
                    )
                  else
                    for (final app in apps)
                      CheckboxListTile(
                        key: ValueKey('focus-app-${app.packageName}'),
                        contentPadding: EdgeInsets.zero,
                        value: configuration.selectedPackages.contains(
                          app.packageName,
                        ),
                        onChanged: controlsEnabled && enabled
                            ? (selected) => _toggleApp(
                                  configuration,
                                  app.packageName,
                                  selected == true,
                                )
                            : null,
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                ],
              ],
            ),
          ),
          if (status.warnings.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current limitations',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final warning in status.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text('• ${focusProtectionWarningText(warning)}'),
                    ),
                ],
              ),
            ),
          const AppCard(
            child: Text(
              'Focus protection does not read messages, page text, clicks, or window content. It does not filter URLs, suspend packages, protect a computer, or prevent uninstalling MyLifeGraph. Settings and essential phone/alarm functions remain reachable.',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_operationGeneration;
    bool isCurrent() => mounted && generation == _operationGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status =
          await ref.read(focusProtectionGatewayProvider).readStatus();
      if (!isCurrent()) return;
      setState(() => _status = status);
    } catch (_) {
      if (!isCurrent()) return;
      setState(() => _error = 'Could not read this device setting.');
    } finally {
      if (isCurrent()) setState(() => _busy = false);
    }
  }

  Future<bool> _save(FocusProtectionConfiguration configuration) async {
    if (_busy || _configurationLocked) return false;
    final generation = ++_operationGeneration;
    bool isCurrent() => mounted && generation == _operationGeneration;
    setState(() => _busy = true);
    try {
      final status = await ref
          .read(focusProtectionGatewayProvider)
          .saveConfiguration(configuration);
      if (!isCurrent()) return false;
      setState(() => _status = status);
      return true;
    } catch (_) {
      if (isCurrent()) {
        _showMessage('Could not save Focus protection on this device.');
      }
      return false;
    } finally {
      if (isCurrent()) setState(() => _busy = false);
    }
  }

  Future<void> _loadAppsWithDisclosure() async {
    var configuration = _status!.configuration;
    if (!configuration.hasConsent(focusProtectionAppCatalogConsent)) {
      final agreed = await _showDisclosure(
        title: 'Allow installed-app lookup?',
        body:
            'MyLifeGraph will ask Android only for launchable apps so you can choose which ones to block. It saves selected package names locally and uploads nothing.',
        agreeLabel: 'Agree and show apps',
      );
      if (agreed != true || !mounted) return;
      configuration = _withConsent(
        configuration,
        focusProtectionAppCatalogConsent,
      );
      final saved = await _save(configuration);
      if (!saved || !mounted || _status == null) return;
    }
    final generation = ++_operationGeneration;
    bool isCurrent() => mounted && generation == _operationGeneration;
    setState(() => _busy = true);
    try {
      final apps =
          await ref.read(focusProtectionGatewayProvider).listLaunchableApps();
      if (!isCurrent()) return;
      setState(() => _apps = apps);
    } catch (_) {
      if (isCurrent()) {
        _showMessage('Could not load launchable apps on this device.');
      }
    } finally {
      if (isCurrent()) setState(() => _busy = false);
    }
  }

  Future<void> _openAccessibilitySettings() async {
    var configuration = _status!.configuration;
    if (!configuration.hasConsent(focusProtectionAccessibilityConsent)) {
      final agreed = await _showDisclosure(
        title: 'Allow app blocking?',
        body:
            'Android Accessibility access lets MyLifeGraph see only which app moves to the foreground and show its own block page. MyLifeGraph does not retrieve window content, text, messages, or clicks.',
        agreeLabel: 'Agree and open settings',
      );
      if (agreed != true || !mounted) return;
      configuration = _withConsent(
        configuration,
        focusProtectionAccessibilityConsent,
      );
      final saved = await _save(configuration);
      if (!saved || !mounted) return;
    }
    try {
      await ref
          .read(focusProtectionGatewayProvider)
          .openAccessibilitySettings();
    } catch (_) {
      _showMessage('Could not open Android Accessibility settings.');
    }
  }

  Future<void> _openNotificationPolicySettings() async {
    var configuration = _status!.configuration;
    if (!configuration.hasConsent(
      focusProtectionNotificationPolicyConsent,
    )) {
      final agreed = await _showDisclosure(
        title: 'Allow notification silencing?',
        body:
            'Do Not Disturb access lets MyLifeGraph control one rule during a protected Focus session. It does not read or delete notifications and does not change other apps’ rules.',
        agreeLabel: 'Agree and open settings',
      );
      if (agreed != true || !mounted) return;
      configuration = _withConsent(
        configuration,
        focusProtectionNotificationPolicyConsent,
      );
      final saved = await _save(configuration);
      if (!saved || !mounted) return;
    }
    try {
      await ref
          .read(focusProtectionGatewayProvider)
          .openNotificationPolicySettings();
    } catch (_) {
      _showMessage('Could not open Android Do Not Disturb settings.');
    }
  }

  FocusProtectionConfiguration _withConsent(
    FocusProtectionConfiguration configuration,
    String kind,
  ) {
    return configuration.copyWith(
      consentVersions: {
        ...configuration.consentVersions,
        kind: focusProtectionConsentVersion,
      },
    );
  }

  Future<bool?> _showDisclosure({
    required String title,
    required String body,
    required String agreeLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(agreeLabel),
          ),
        ],
      ),
    );
  }

  void _toggleApp(
    FocusProtectionConfiguration configuration,
    String packageName,
    bool selected,
  ) {
    final packages = configuration.selectedPackages.toSet();
    selected ? packages.add(packageName) : packages.remove(packageName);
    _save(configuration.copyWith(selectedPackages: packages));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.description,
    required this.granted,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String description;
  final bool granted;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          granted ? AppIcons.checkCircleOutline : AppIcons.warningAmberOutlined,
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(AppIcons.settingsOutlined),
        onTap: enabled ? onPressed : null,
      ),
    );
  }
}

String focusProtectionWarningText(FocusProtectionWarning warning) {
  return switch (warning) {
    FocusProtectionWarning.accessibilityDisabled =>
      'App blocking is unavailable until Accessibility access is enabled.',
    FocusProtectionWarning.notificationPolicyMissing =>
      'Notifications cannot be silenced until Do Not Disturb access is enabled.',
    FocusProtectionWarning.dndUnsupported =>
      'Notification silencing requires Android 10 or newer.',
    FocusProtectionWarning.noAppsSelected =>
      'App blocking is on, but no apps are selected.',
    FocusProtectionWarning.zenRuleMissingOrOverridden =>
      'Android could not confirm the MyLifeGraph Focus rule, or it was disabled, removed, or overridden.',
    FocusProtectionWarning.nativeFailure =>
      'Android protection status could not be confirmed. The Focus session continues.',
  };
}
