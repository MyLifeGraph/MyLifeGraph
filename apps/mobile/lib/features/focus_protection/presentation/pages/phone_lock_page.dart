import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/phone_lock_gateway.dart';
import '../../application/blocking_gateway.dart';
import '../../application/focus_protection_gateway.dart';
import '../../domain/focus_protection.dart';
import '../../domain/phone_lock.dart';
import '../widgets/strict_status_ring.dart';

class PhoneLockRoutePage extends Page<Object?> {
  const PhoneLockRoutePage({super.key, this.launch});
  final PhoneLockLaunch? launch;
  @override
  Route<Object?> createRoute(BuildContext context) =>
      ModalBottomSheetRoute<Object?>(
        settings: this,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (_) => FractionallySizedBox(
          heightFactor: .92,
          child: PhoneLockPage(launch: launch),
        ),
      );
}

class PhoneLockPage extends ConsumerStatefulWidget {
  const PhoneLockPage({super.key, this.launch});
  final PhoneLockLaunch? launch;
  @override
  ConsumerState<PhoneLockPage> createState() => _PhoneLockPageState();
}

class _PhoneLockPageState extends ConsumerState<PhoneLockPage>
    with WidgetsBindingObserver {
  late PhoneLockOptions _options;
  PhoneLockStatus? _status;
  bool _busy = false, _reading = false, _foreground = true;
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _options = (widget.launch?.options ?? PhoneLockOptions()).copyWith(
      minutes: widget.launch?.focusMinutes ?? 45,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_load());
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _load({bool preserveError = false}) async {
    if (_reading || _busy || !_foreground) return;
    _reading = true;
    try {
      final status = await ref.read(phoneLockGatewayProvider).status();
      if (!mounted) return;
      setState(() {
        _status = status;
        if (!preserveError || status.active) _error = null;
      });
      _timer?.cancel();
      if (status.active && _foreground) {
        _timer = Timer(const Duration(seconds: 1), () => unawaited(_load()));
      }
    } catch (e) {
      if (mounted) setState(() => _error = phoneLockError(e));
    } finally {
      _reading = false;
    }
  }

  Future<void> _review() async {
    if (_busy ||
        _reading ||
        _status?.ready != true ||
        _status?.active == true) {
      return;
    }
    setState(() => _busy = true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ready to lock?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('All other apps and Home are blocked.'),
              const SizedBox(height: AppSpacing.md),
              AppSurface(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.lockOutline),
                      title: const Text('Unlock with'),
                      subtitle: Text(
                        _options.mode == 'nfc'
                            ? 'Saved NFC chip'
                            : '${_options.minutes} min timer',
                      ),
                    ),
                    if (_options.mode == 'nfc') ...[
                      const Divider(),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(AppIcons.hourglass),
                        title: Text('Recovery'),
                        subtitle: Text(
                          'Saved backup chip or 15-minute recovery wait',
                        ),
                      ),
                    ],
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.squaresFour),
                      title: const Text('Allowed apps'),
                      subtitle: Text(
                        'Phone, alarms + ${_options.allowedApps.length}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Calls and essential Android functions remain available. Protection depends on Android permissions.',
              ),
              if (_options.mode == 'nfc') ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Recovery continues in the background. New chips cannot replace this lock’s saved chips.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              widget.launch == null ? 'Start phone lock' : 'Use with Focus',
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      setState(() => _busy = false);
      return;
    }
    if (widget.launch != null) {
      Navigator.pop(context, _options);
      return;
    }
    try {
      final result = await ref
          .read(phoneLockGatewayProvider)
          .start(_options, 'manual-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        setState(() {
          _status = result;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = phoneLockError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_load(preserveError: true));
      }
    }
  }

  Future<void> _apps() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final device = await ref
          .read(focusProtectionGatewayProvider)
          .readStatus();
      if (!device.configuration.hasConsent(focusProtectionAppCatalogConsent)) {
        throw const FormatException(
          'Allow the installed-app list in Permissions & limits first.',
        );
      }
      final apps = await ref.read(blockingGatewayProvider).catalog();
      if (!mounted) return;
      final selected = {..._options.allowedApps};
      final result = await showDialog<Set<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, change) => AlertDialog(
            title: const Text('Allowed apps'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    leading: Icon(AppIcons.lockOutline),
                    title: Text('Phone and emergency calls'),
                    subtitle: Text('Always available'),
                  ),
                  const Divider(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final app in apps)
                          CheckboxListTile(
                            value: selected.contains(app['packageName']),
                            secondary: _appIcon(app['icon']),
                            title: Text(app['label'] as String),
                            onChanged: (checked) => change(() {
                              if (checked == true) {
                                selected.add(app['packageName'] as String);
                              } else {
                                selected.remove(app['packageName']);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (mounted && result != null) {
        setState(() => _options = _options.copyWith(allowedApps: result));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException ? e.message : phoneLockError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _appIcon(Object? encoded) {
    try {
      if (encoded is String && encoded.isNotEmpty) {
        return Image.memory(
          base64Decode(encoded),
          width: 28,
          height: 28,
          errorBuilder: (_, _, _) => const Icon(AppIcons.deviceMobile),
        );
      }
    } catch (_) {
      /* Safe local fallback. */
    }
    return const Icon(AppIcons.deviceMobile);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final active = status?.active == true;
    return PopScope(
      canPop: !_busy,
      child: AppPage(
        key: ValueKey('phone-lock-$active'),
        title: 'Phone lock',
        subtitle: active ? null : 'Choose how to unlock.',
        children: [
          if (_error != null)
            AppSurface(
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (status == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (active) ...[
            if (!status!.ready)
              const Text(
                'Protection interrupted. Re-enable app protection and Accessibility in Permissions & limits.',
              ),
            const Center(child: StrictStatusRing(locked: true)),
            if (status.mode == 'timer' || status.recoveryStarted)
              Center(
                child: Text(
                  phoneLockTime(
                    status.recoveryStarted
                        ? status.recoveryRemainingMs
                        : status.remainingMs,
                  ),
                  style: Theme.of(context).textTheme.displayLarge,
                ),
              ),
            Center(
              child: Text(
                status.mode == 'timer' ? 'Time to focus' : 'Phone lock is on',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Center(
              child: Text(
                status.recoveryStarted
                    ? 'Recovery continues in the background.'
                    : status.mode == 'timer'
                    ? 'Unlocks when your timer ends.'
                    : 'Scan a saved chip to unlock.',
              ),
            ),
            if (status.mode == 'nfc')
              FilledButton(
                onPressed: _busy ? null : () => _control(scan: true),
                child: const Text('Scan NFC chip'),
              ),
            OutlinedButton(
              onPressed: () => ref.read(phoneLockGatewayProvider).phone(),
              child: const Text('Phone / Emergency'),
            ),
            TextButton(
              onPressed: _busy ? null : _control,
              child: const Text('Allowed apps & recovery'),
            ),
          ] else if (status != null) ...[
            AppSurface(
              child: Column(
                children: [
                  RadioGroup<String>(
                    groupValue: _options.mode,
                    onChanged: (value) {
                      if (!_busy && value != null) {
                        setState(
                          () => _options = _options.copyWith(mode: value),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          controlAffinity: ListTileControlAffinity.trailing,
                          value: 'timer',
                          title: const Text('Timer'),
                          subtitle: const Text('Until the timer ends'),
                          secondary: const Icon(AppIcons.timerOutlined),
                        ),
                        const Divider(),
                        RadioListTile<String>(
                          controlAffinity: ListTileControlAffinity.trailing,
                          value: 'nfc',
                          title: const Text('NFC chip'),
                          subtitle: const Text('Until you scan a saved chip'),
                          secondary: const Icon(AppIcons.nfc),
                        ),
                      ],
                    ),
                  ),
                  if (_options.mode == 'timer') ...[
                    const SizedBox(height: AppSpacing.md),
                    if (widget.launch != null)
                      Text(
                        '${widget.launch!.focusMinutes} min · Focus session timer',
                      )
                    else
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final minutes in [25, 45, 60, 90, 120, 240])
                            ChoiceChip(
                              label: Text('$minutes min'),
                              selected: _options.minutes == minutes,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(
                                      () => _options = _options.copyWith(
                                        minutes: minutes,
                                      ),
                                    ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            AppSurface(
              child: ListTile(
                leading: const Icon(AppIcons.squaresFour),
                title: const Text('Allowed apps'),
                subtitle: Text(
                  'Phone, alarms + ${_options.allowedApps.length}',
                ),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: _busy ? null : _apps,
              ),
            ),
            if (!status.ready)
              const Text(
                'Enable app protection and Accessibility in Permissions & limits first.',
              ),
            if (_options.mode == 'nfc' &&
                (!status.nfcAvailable || !status.nfcEnrolled))
              const Text(
                'Enable NFC and save a chip in Discipline → Unlock settings first.',
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: const StadiumBorder(),
                ),
                onPressed:
                    _busy ||
                        !status.ready ||
                        (_options.mode == 'nfc' &&
                            (!status.nfcAvailable || !status.nfcEnrolled))
                    ? null
                    : _review,
                child: Text(
                  widget.launch == null ? 'Review lock' : 'Use with Focus',
                ),
              ),
            ),
            if (widget.launch != null)
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Leave Phone lock off'),
              ),
            const Text(
              'Calls, alarms and essential Android functions stay available.',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _control({bool scan = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(phoneLockGatewayProvider).control(scan: scan);
    } catch (e) {
      if (mounted) setState(() => _error = phoneLockError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
