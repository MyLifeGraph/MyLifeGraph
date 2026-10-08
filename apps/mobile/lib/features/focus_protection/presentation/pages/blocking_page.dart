import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/blocking_website_icon.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/blocking_gateway.dart';
import '../../application/focus_protection_gateway.dart';
import '../../domain/blocking_plan.dart';
import '../../domain/blocking_usage_duration.dart';
import '../../domain/focus_protection.dart';
import 'focus_protection_settings_page.dart';
import '../widgets/strict_status_ring.dart';
import '../widgets/blocking_screen_preview.dart';
import '../widgets/blocking_custom_editor.dart';
import '../widgets/blocking_plan_summary.dart';
import '../widgets/blocking_reorder_handle.dart';

IconData blockingIcon(String name) => switch (name) {
  'work' => AppIcons.briefcaseOutlined,
  'games' => AppIcons.gameController,
  'social' => AppIcons.forumOutlined,
  'sleep' => AppIcons.bedtimeOutlined,
  'study' => AppIcons.schoolOutlined,
  _ => AppIcons.shieldOutlined,
};

class BlockingPage extends ConsumerStatefulWidget {
  const BlockingPage({super.key});
  @override
  ConsumerState<BlockingPage> createState() => _BlockingPageState();
}

class _BlockingPageState extends ConsumerState<BlockingPage>
    with WidgetsBindingObserver {
  static const _strictControlGap = AppSpacing.sm + AppSpacing.xs;
  static const _strictControlStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
      ),
    ),
  );
  BlockingSnapshot? _snapshot;
  final _timingLabels = Expando<(int, bool, String)>();

  String _timingLabel(BlockingPlan plan, bool usageGranted) {
    final now = DateTime.now();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    final cached = _timingLabels[plan];
    if (cached != null && cached.$1 == minute && cached.$2 == usageGranted) {
      return cached.$3;
    }
    final label = blockingPlanTiming(
      plan,
      now: now,
      usageGranted: usageGranted,
    );
    _timingLabels[plan] = (minute, usageGranted, label);
    return label;
  }

  FocusProtectionStatus? _legacy;
  String? _error;
  bool _busy = false, _editorOpen = false, _foreground = true;
  bool _reordering = false;
  Future<void>? _refreshFuture;
  int _tab = 0, _days = 7, _generation = 0, _usageGeneration = 0;
  Map? _insights;
  Timer? _timer;
  BlockingGateway? _sessionGateway;
  bool _routeVisible = true;
  bool _unlockDialog = false;
  bool _startingNfc = false;
  bool _strictPresent = true, _finishingUnlock = false;
  bool _requestingUnlock = false;
  BlockingGateway get _gateway => ref.read(blockingGatewayProvider);
  bool get _configurationLocked =>
      _snapshot?.locked == true || _legacy?.lease?.isActive == true;
  bool get _protectionReady =>
      _legacy?.configuration.enabled == true &&
      _legacy?.configuration.blockSelectedApps == true &&
      _legacy?.accessibilityEnabled == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionGateway = _gateway;
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_closeStrictSession());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _closeStrictSession() async {
    try {
      await _sessionGateway?.command('strictVisibility', {'visible': false});
    } catch (_) {
      /* No native session on unsupported hosts. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // A notification shade loses focus without leaving the app. Suspend UI
    // polling/completion but retain the native request; hidden/paused cancels it.
    if (state == AppLifecycleState.inactive) {
      ++_generation;
      _timer?.cancel();
      return;
    }
    _strictPresent = _foreground;
    if (_foreground) {
      unawaited(_resumeStrict());
    } else {
      unawaited(_syncStrictVisibility());
      _timer?.cancel();
    }
  }

  Future<void> _resumeStrict() async {
    await _syncStrictVisibility();
    if (mounted && _foreground) await _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (visible != _routeVisible) {
      _routeVisible = visible;
      unawaited(_syncStrictVisibility());
    }
  }

  Future<void> _syncStrictVisibility() async {
    final generation = ++_generation;
    try {
      final value = await _gateway.command('strictVisibility', {
        'visible':
            _strictPresent && (_routeVisible || _unlockDialog) && _tab == 1,
      });
      if (!mounted || generation != _generation) return;
      setState(() => _snapshot = value);
      _pollUnlock(value);
    } catch (_) {
      // Unsupported/web hosts have no native Strict session. Explicit unlock
      // remains guarded by the native bridge and reports any real failure.
    }
  }

  Future<void> _refresh() {
    if (_busy || _editorOpen || _reordering || !_foreground || !_routeVisible) {
      return Future<void>.value();
    }
    return _refreshFuture ??= _refreshCurrentTab().whenComplete(
      () => _refreshFuture = null,
    );
  }

  Future<void> _refreshCurrentTab() async {
    final tab = _tab;
    await _load();
    if (mounted && _error == null && _tab == tab && tab == 2 && !_busy) {
      await _usage();
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    final generation = ++_generation;
    try {
      final legacy = await ref
          .read(focusProtectionGatewayProvider)
          .readStatus();
      final value = await _gateway.command('status');
      if (!mounted || generation != _generation) return;
      setState(() {
        _legacy = legacy;
        _snapshot = value;
        _error = null;
        if (!value.usageGranted) {
          ++_usageGeneration;
          _insights = null;
        }
      });
      _pollUnlock(value);
      unawaited(_completeUnlockIfReady());
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(e));
        if (_snapshot case final current?) _pollUnlock(current);
      }
    }
  }

  String _message(Object e) {
    if (e is PlatformException) {
      return switch (e.message) {
        'Enable app blocking first.' || 'Enable Android protection first.' =>
          'Set up app blocking in Permissions & limits.',
        _ =>
          e.message?.trim().isNotEmpty == true
              ? e.message!.trim()
              : 'Could not complete. Try again.',
      };
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  void _pollUnlock(BlockingSnapshot value) {
    _timer?.cancel();
    if (!_foreground || (!_routeVisible && !_unlockDialog)) return;
    final delays = <int>[];
    if (_tab == 1 && value.locked && value.unlockStarted) {
      delays.add(1000);
    }
    if (value.releaseRemainingMs > 0) {
      delays.add(value.releaseRemainingMs + 50);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final plan in value.plans.where((p) => p.enabled)) {
      for (final instant in [plan.until, plan.pausedUntil]) {
        if (instant > now) delays.add(instant - now + 50);
      }
      if (plan.windows.isNotEmpty || plan.focus) delays.add(60000);
      if (plan.budget > 0 && value.usageGranted) delays.add(5000);
    }
    if (delays.isNotEmpty) {
      delays.sort();
      _timer = Timer(
        Duration(milliseconds: delays.first),
        () => unawaited(_load()),
      );
    }
  }

  Future<void> _completeUnlockIfReady() async {
    final s = _snapshot;
    if (!mounted ||
        !_foreground ||
        !_routeVisible ||
        _unlockDialog ||
        _tab != 1 ||
        _busy ||
        _finishingUnlock ||
        s == null ||
        !s.locked ||
        !s.unlockStarted ||
        s.remainingMs > 0) {
      return;
    }
    _finishingUnlock = true;
    try {
      // Native authority rechecks visibility, charger/Wi-Fi/NFC and intent.
      // Unmet conditions return the unchanged snapshot, not a success/error loop.
      await _perform(() => _gateway.command('tryFinishUnlock'));
    } finally {
      _finishingUnlock = false;
    }
  }

  Future<void> _requestUnlock() async {
    if (_busy ||
        _editorOpen ||
        _requestingUnlock ||
        _snapshot?.locked != true) {
      return;
    }
    _requestingUnlock = true;
    try {
      _editorOpen = true;
      String? mode;
      try {
        mode = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            titlePadding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            title: const Text('Unlock'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  style: _strictControlStyle,
                  onPressed: () => Navigator.pop(ctx, 'temporary'),
                  child: const Text('15 minutes'),
                ),
                const SizedBox(height: _strictControlGap),
                OutlinedButton(
                  style: _strictControlStyle,
                  onPressed: () => Navigator.pop(ctx, 'off'),
                  child: const Text('Turn off Strict'),
                ),
              ],
            ),
          ),
        );
      } finally {
        _editorOpen = false;
      }
      if (!mounted ||
          mode == null ||
          !_foreground ||
          _tab != 1 ||
          _snapshot?.locked != true) {
        return;
      }
      _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
      await _syncStrictVisibility();
      if (!mounted || !_foreground || _tab != 1) return;
      await _perform(() => _gateway.command('requestUnlock', {'mode': mode!}));
      await _completeUnlockIfReady();
    } finally {
      _requestingUnlock = false;
    }
  }

  Future<bool> _perform(Future<BlockingSnapshot> Function() action) async {
    if (_busy) return false;
    final generation = ++_generation;
    ++_usageGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await action();
      if (mounted && generation == _generation) {
        setState(() => _snapshot = value);
        _pollUnlock(value);
      }
      return true;
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(e));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Leaving Strict can cancel a native request before its earlier reply
        // reaches Flutter. Re-read authority rather than restoring that reply.
        if (generation != _generation) {
          await _load();
        } else if (_snapshot case final value?) {
          _pollUnlock(value);
        }
      }
    }
  }

  Future<bool> _save(
    List<BlockingPlan> plans, {
    Map<String, Object>? custom,
    int? expectedRevision,
  }) async {
    final s = _snapshot!;
    return _perform(
      () => _gateway.command('save', {
        'revision': expectedRevision ?? s.revision,
        'plans': plans.map((p) => p.toMap()).toList(),
        'custom': custom ?? s.custom,
      }),
    );
  }

  Future<bool> _reorder(List<BlockingPlan> plans, int revision) => _perform(
    () => _gateway.command('reorder', {
      'revision': revision,
      'ids': plans.map((p) => p.id).toList(),
    }),
  );

  Future<bool> _disclose(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
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
      ) ??
      false;
  Future<void> _consent(String kind) async {
    if (_busy || _configurationLocked) return;
    final accepted = await _disclose(
      kind == 'website' ? 'Website protection' : 'Usage access',
      kind == 'website'
          ? 'Read only the address bar in supported browsers to block selected domains. No page content or browsing data is uploaded. Hidden address bars and other browsers may not be detected.'
          : 'Use Android app-usage history for daily budgets and charts. It stays on this device.',
    );
    if (!accepted || !mounted || _busy || _configurationLocked) return;
    final saved = await _perform(
      () => _gateway.command('consent', {'kind': kind}),
    );
    if (saved && kind == 'usage' && mounted) await _enableUsage();
  }

  Future<void> _revoke(String kind) async {
    if (!await _disclose(
          kind == 'website' ? 'Disable websites?' : 'Disable usage access?',
          kind == 'website'
              ? 'Website rules stop. App rules stay unchanged.'
              : 'Daily budgets and usage charts stop. Other rules stay unchanged.',
        ) ||
        !mounted) {
      return;
    }
    await _perform(
      () => _gateway.command('consent', {'kind': kind, 'allowed': false}),
    );
    if (mounted && kind == 'usage') setState(() => _insights = null);
  }

  Future<void> _enableUsage() async {
    if (_busy || _configurationLocked) return;
    if (_snapshot?.usageConsent != true) {
      await _consent('usage');
      return;
    }
    try {
      await _gateway.open('usageSettings');
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<List<Map>?> _catalog() async {
    final configuration = _legacy!.configuration;
    if (!configuration.hasConsent(focusProtectionAppCatalogConsent)) {
      if (!await _disclose(
        'Choose apps',
        'Read installed launchable app names and icons. The list stays on this device.',
      )) {
        return null;
      }
      try {
        final value = await ref
            .read(focusProtectionGatewayProvider)
            .saveConfiguration(
              configuration.copyWith(
                consentVersions: {
                  ...configuration.consentVersions,
                  focusProtectionAppCatalogConsent:
                      focusProtectionConsentVersion,
                },
              ),
            );
        if (mounted) setState(() => _legacy = value);
      } catch (e) {
        if (mounted) setState(() => _error = _message(e));
        return null;
      }
    }
    try {
      return await _gateway.catalog();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
      return null;
    }
  }

  void _tapPlan(BlockingPlan plan) {
    if (_busy || _editorOpen || _reordering) return;
    if (_configurationLocked) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _snapshot?.locked == true
                ? 'Unlock Strict to edit.'
                : 'End Focus to edit.',
          ),
        ),
      );
      return;
    }
    unawaited(_edit(plan));
  }

  Future<void> _edit([BlockingPlan? plan, bool quick = false]) async {
    if (_snapshot == null || _configurationLocked || _busy || _editorOpen) {
      return;
    }
    setState(() => _editorOpen = true);
    try {
      final editorBase = _snapshot!;
      // A detail sheet may outlive a foreground refresh. Never pair its old
      // definition with the new revision, or resurrect a removed plan.
      if (plan != null) {
        final current = editorBase.plans.where((p) => p.id == plan!.id);
        if (current.isEmpty) {
          setState(() => _error = 'Plan changed. Reload and try again.');
          return;
        }
        plan = current.single;
      }
      final catalog = await _catalog();
      if (catalog == null || !mounted || _configurationLocked) return;
      await showModalBottomSheet<BlockingPlan>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        builder: (ctx) => BlockingPlanEditor(
          plan: plan,
          catalog: catalog,
          usageGranted: editorBase.usageGranted,
          websiteAllowed: editorBase.websiteConsent,
          quick: quick,
          onSave: (result) async {
            final saved = await _save([
              for (final p in editorBase.plans)
                if (p.id == result.id) result else p,
              if (!editorBase.plans.any((p) => p.id == result.id)) result,
            ], expectedRevision: editorBase.revision);
            if (!saved) {
              throw StateError(_error ?? 'Could not save. Try again.');
            }
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  Future<void> _menu(BlockingPlan plan, String action) async {
    if (_busy ||
        _editorOpen ||
        (_configurationLocked &&
            action != 'up' &&
            action != 'down' &&
            action != 'details')) {
      return;
    }
    if (action == 'details') {
      await _detail(plan);
      return;
    }
    if (action == 'edit') {
      await _edit(plan);
      return;
    }
    if (action == 'delete' &&
        !await _disclose(
          'Delete plan?',
          'Other plans and Focus history stay unchanged.',
        )) {
      return;
    }
    if (!mounted) return;
    final others = _snapshot!.plans.where((p) => p.id != plan.id).toList();
    List<BlockingPlan> replace(BlockingPlan value) => _snapshot!.plans
        .map((item) => item.id == value.id ? value : item)
        .toList();
    switch (action) {
      case 'up':
      case 'down':
        final ordered = [..._snapshot!.plans];
        final from = ordered.indexWhere((item) => item.id == plan.id);
        final to = from + (action == 'up' ? -1 : 1);
        if (from >= 0 && to >= 0 && to < ordered.length) {
          ordered.insert(to, ordered.removeAt(from));
          await _reorder(ordered, _snapshot!.revision);
        }
      case 'delete':
        await _save(others);
      case 'duplicate':
        await _save([
          ..._snapshot!.plans,
          plan.copyWith(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name:
                '${plan.name.substring(0, plan.name.length.clamp(0, 53))} copy',
          ),
        ]);
      case 'pause':
        await _save(replace(plan.copyWith(enabled: false)));
      case 'resume':
        await _save(replace(plan.copyWith(enabled: true, pausedUntil: 0)));
      case '10m':
        await _save(
          replace(
            plan.copyWith(
              pausedUntil: DateTime.now()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
            ),
          ),
        );
    }
  }

  Future<void> _permissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const FocusProtectionSettingsPage(permissionsOnly: true),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _usage() async {
    if (_snapshot == null || _busy) return;
    if (!_snapshot!.usageGranted) {
      setState(() => _insights = null);
      return;
    }
    final generation = ++_usageGeneration;
    setState(() => _error = null);
    try {
      final value = await _gateway.insights(_days);
      if (mounted && generation == _usageGeneration) {
        setState(() => _insights = value);
      }
    } catch (e) {
      if (mounted && generation == _usageGeneration) {
        setState(() => _error = _message(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return AppPage(
      title: 'App blocking',
      compactHeader: true,
      backFallback: AppRoutes.settings,
      maxWidth: 720,
      actions: [
        IconButton(
          tooltip: 'Permissions & limits',
          onPressed: _busy ? null : _permissions,
          icon: const Icon(AppIcons.settingsOutlined),
        ),
      ],
      viewportBody: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: s == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                  )
                : RefreshIndicator(
                    key: const ValueKey('blocking-pull-refresh'),
                    onRefresh: _refresh,
                    notificationPredicate: (notification) =>
                        notification.depth == 0 &&
                        !_busy &&
                        !_editorOpen &&
                        !_reordering,
                    child: _tab == 0
                        ? CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              for (final section in _plans(s))
                                if (section is SliverReorderableList)
                                  section
                                else
                                  SliverToBoxAdapter(child: section),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: AppSpacing.md),
                              ),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            children: switch (_tab) {
                              0 => _plans(s),
                              1 => _strict(s),
                              2 => _charts(s),
                              _ => _custom(s),
                            },
                          ),
                  ),
          ),
          AppSurface(
            variant: AppSurfaceVariant.raised,
            radius: AppRadii.pill,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = MediaQuery.textScalerOf(context).scale(12) >= 18
                    ? 2
                    : 4;
                return Wrap(
                  children: [
                    for (final (index, label, icon) in [
                      (0, 'Plans', AppIcons.shieldOutlined),
                      (1, 'Strict', AppIcons.lockOutline),
                      (2, 'Insights', AppIcons.autoGraph),
                      (3, 'Customize', AppIcons.tuneOutlined),
                    ])
                      SizedBox(
                        width: constraints.maxWidth / columns,
                        child: Semantics(
                          selected: _tab == index,
                          child: TextButton(
                            onPressed: s == null
                                ? null
                                : () {
                                    setState(() => _tab = index);
                                    unawaited(_syncStrictVisibility());
                                    _pollUnlock(s);
                                    if (index == 2) unawaited(_usage());
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: _tab == index
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              foregroundColor: _tab == index
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon),
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: _tab == index
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      children: const [],
    );
  }

  List<Widget> _plans(BlockingSnapshot s) => [
    if (_legacy?.configuration.enabled != true ||
        _legacy?.accessibilityEnabled != true)
      AppSurface(
        variant: AppSurfaceVariant.warning,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable protection'),
          trailing: const Icon(AppIcons.arrowForward),
          onTap: _permissions,
        ),
      ),
    const SizedBox(height: AppSpacing.sm),
    AppSurface(
      variant: AppSurfaceVariant.subtle,
      child: Row(
        children: [
          const Icon(AppIcons.playArrow),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Quick Block',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: _configurationLocked || _busy || _editorOpen
                ? null
                : () => _edit(null, true),
            child: const Text('Start'),
          ),
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    Row(
      children: [
        Expanded(
          child: Text('Plans', style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton.icon(
          onPressed: _configurationLocked || _busy || _editorOpen
              ? null
              : () => _edit(),
          icon: const Icon(AppIcons.add),
          label: const Text('Add'),
        ),
      ],
    ),
    if (s.plans.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text('No plans yet.'),
      ),
    SliverReorderableList(
      itemCount: s.plans.length,
      onReorderStart: (_) => _reordering = true,
      onReorderEnd: (_) => _reordering = false,
      onReorderItem: (oldIndex, newIndex) {
        if (_busy || _editorOpen) return;
        final plans = [...s.plans];
        if (oldIndex == newIndex) return;
        plans.insert(newIndex, plans.removeAt(oldIndex));
        unawaited(_reorder(plans, s.revision));
      },
      itemBuilder: (context, index) {
        final plan = s.plans[index];
        final timing = _timingLabel(plan, s.usageGranted);
        final editable = !_configurationLocked && !_busy && !_editorOpen;
        final palette = Theme.of(context).colorScheme;
        return Padding(
          key: ValueKey(plan.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppSurface(
            variant: AppSurfaceVariant.interactive,
            selected: plan.active,
            onTap: () => _tapPlan(plan),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        (plan.active
                                ? palette.primary
                                : palette.onSurfaceVariant)
                            .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    blockingIcon(plan.icon),
                    size: 28,
                    color: plan.active
                        ? palette.primary
                        : palette.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppStatusPill(
                        icon: plan.active
                            ? AppIcons.shieldOutlined
                            : AppIcons.schedule,
                        tone: plan.active
                            ? AppStatusTone.success
                            : AppStatusTone.neutral,
                        label: plan.paused
                            ? 'Paused'
                            : plan.active
                            ? 'Active'
                            : plan.expired
                            ? 'Expired'
                            : 'Scheduled',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        plan.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        blockingPlanKinds(plan, DateTime.now()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!const [
                        'Active',
                        'Paused',
                        'Expired',
                        'Scheduled',
                      ].contains(timing))
                        Text(
                          timing,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(AppIcons.squaresFour, size: 16),
                              const SizedBox(width: 4),
                              Flexible(child: Text('${plan.apps.length} apps')),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(AppIcons.publicOutlined, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text('${plan.sites.length} sites'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Plan options',
                        enabled: !_busy && !_editorOpen,
                        icon: const Icon(AppIcons.moreHoriz, size: 20),
                        onSelected: (value) => unawaited(_menu(plan, value)),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'details',
                            child: Text('Details'),
                          ),
                          PopupMenuItem(
                            enabled: editable,
                            value: 'edit',
                            child: const Text('Edit'),
                          ),
                          PopupMenuItem(
                            enabled: editable,
                            value: 'duplicate',
                            child: const Text('Duplicate'),
                          ),
                          PopupMenuItem(
                            enabled: editable,
                            value: plan.paused ? 'resume' : 'pause',
                            child: Text(plan.paused ? 'Resume' : 'Pause'),
                          ),
                          PopupMenuItem(
                            enabled: editable,
                            value: '10m',
                            child: const Text('Pause 10m'),
                          ),
                          PopupMenuItem(
                            enabled: editable,
                            value: 'delete',
                            child: const Text('Delete'),
                          ),
                          if (index > 0)
                            const PopupMenuItem(
                              value: 'up',
                              child: Text('Move up'),
                            ),
                          if (index < s.plans.length - 1)
                            const PopupMenuItem(
                              value: 'down',
                              child: Text('Move down'),
                            ),
                        ],
                      ),
                      BlockingReorderHandle(
                        index: index,
                        enabled: !_busy && !_editorOpen,
                        child: Semantics(
                          label: 'Reorder ${plan.name}',
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: List.generate(
                                    6,
                                    (_) => Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: palette.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
    Wrap(
      spacing: AppSpacing.xs,
      children: [
        ActionChip(
          avatar: const Icon(AppIcons.publicOutlined),
          label: Text(
            s.websiteConsent ? 'Websites allowed' : 'Enable websites',
          ),
          onPressed: _configurationLocked || _busy
              ? null
              : () =>
                    s.websiteConsent ? _revoke('website') : _consent('website'),
        ),
        ActionChip(
          avatar: const Icon(AppIcons.autoGraph),
          label: Text(s.usageGranted ? 'Usage allowed' : 'Enable budgets'),
          onPressed: _configurationLocked || _busy
              ? null
              : () => s.usageGranted ? _revoke('usage') : _enableUsage(),
        ),
        if (s.usageConsent && !s.usageGranted)
          IconButton(
            tooltip: 'Disable usage access',
            onPressed: _configurationLocked || _busy
                ? null
                : () => _revoke('usage'),
            icon: const Icon(AppIcons.close),
          ),
      ],
    ),
  ];
  Future<void> _detail(BlockingPlan plan) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(blockingIcon(plan.icon), size: 56),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  plan.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                AppSurface(
                  variant: AppSurfaceVariant.accent,
                  child: Column(
                    children: [
                      Text(plan.summary),
                      const SizedBox(height: AppSpacing.sm),
                      if (plan.budget > 0)
                        LinearProgressIndicator(
                          value: (plan.usedMs / (plan.budget * 60000)).clamp(
                            0,
                            1,
                          ),
                        ),
                      Text(
                        '${plan.apps.length} apps · ${plan.sites.length} sites',
                      ),
                    ],
                  ),
                ),
                for (final window in plan.windows)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(_windowSummary(window)),
                  ),
                if (plan.windows.isNotEmpty) const Text('Device time'),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _configurationLocked
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          unawaited(_edit(plan));
                        },
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _clock(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
  String _windowSummary(BlockingWindow window) {
    final days = window.days.toList()..sort();
    return '${days.map((d) => _dayNames[d - 1]).join(' ')} · ${_clock(window.start)}–${_clock(window.end)}${window.end < window.start ? ' (+1 day)' : ''}';
  }

  static const _dayNames = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  List<Widget> _strict(BlockingSnapshot s) => [
    const SizedBox(height: AppSpacing.lg),
    Center(child: StrictStatusRing(locked: s.locked)),
    const SizedBox(height: AppSpacing.md),
    Text(
      s.locked
          ? 'Active'
          : s.strict['enabled'] == true
          ? 'Unlocked · 15m'
          : 'Off',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: AppSpacing.lg),
    AppSurface(
      variant: AppSurfaceVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.timerOutlined),
            title: const Text('Unlock method'),
            subtitle: Text(_strictSummary(s)),
            trailing: const Icon(AppIcons.expandMore),
            onTap: _configurationLocked || _busy
                ? null
                : () => _strictOptions(s),
          ),
          const SizedBox(height: _strictControlGap),
          if (s.locked) ...[
            if (s.unlockStarted && s.remainingMs > 0)
              Text(
                '${(s.remainingMs + 999) ~/ 1000}s',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            if (!s.unlockStarted)
              FilledButton(
                style: _strictControlStyle,
                onPressed: _busy ? null : _requestUnlock,
                child: const Text('Unblock'),
              ),
            if (s.unlockStarted && s.strict['nfc'] == true) ...[
              if (s.remainingMs > 0) const SizedBox(height: _strictControlGap),
              OutlinedButton.icon(
                style: _strictControlStyle,
                icon: const Icon(AppIcons.devicesOutlined),
                onPressed: _busy ? null : () => _scan(false),
                label: const Text('Scan tag'),
              ),
            ],
            if (s.unlockStarted &&
                (s.remainingMs > 0 || s.strict['nfc'] == true))
              const SizedBox(height: _strictControlGap),
            if (s.unlockStarted)
              Text(
                s.remainingMs > 0
                    ? (s.unlockMode == 'off'
                          ? 'Turning off Strict…'
                          : 'Unlocking for 15m…')
                    : 'Waiting for conditions',
                textAlign: TextAlign.center,
              ),
          ] else ...[
            if (s.strict['enabled'] == true) ...[
              FilledButton(
                style: _strictControlStyle,
                onPressed: _busy
                    ? null
                    : () => _perform(() => _gateway.command('relock')),
                child: const Text('Lock now'),
              ),
              const SizedBox(height: _strictControlGap),
              OutlinedButton(
                style: _strictControlStyle,
                onPressed: _busy || _configurationLocked
                    ? null
                    : () => _strictOptions(s),
                child: const Text('Configure'),
              ),
            ] else
              FilledButton(
                style: _strictControlStyle,
                onPressed: _busy || _configurationLocked
                    ? null
                    : () => _strictOptions(s),
                child: const Text('Enable Strict'),
              ),
          ],
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    ExpansionTile(
      title: const Text('Limits'),
      children: const [
        Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Locks plan changes inside MyLifeGraph. Android Settings, emergency calls and uninstallation remain available. Wi-Fi names and NFC tags are self-control checks, not secure authentication.',
          ),
        ),
      ],
    ),
  ];
  String _strictSummary(BlockingSnapshot s) => [
    _waitLabel(s.strict['waitSeconds'] as int? ?? 180),
    if (s.strict['power'] == true) 'Charger',
    if (s.strict['wifi'] == true) 'Wi-Fi',
    if (s.strict['nfc'] == true) 'NFC',
  ].join(' + ');
  String _waitLabel(int seconds) => seconds == 0
      ? 'Immediate'
      : seconds < 60
      ? '${seconds}s'
      : seconds % 60 == 0
      ? '${seconds ~/ 60}m'
      : '${seconds ~/ 60}m ${seconds % 60}s';
  Future<BlockingSnapshot?> _scan(
    bool enroll, {
    String? name,
    int? revision,
  }) async {
    if (_busy || _startingNfc) return null;
    _startingNfc = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Hold your NFC tag nearby'),
          content: Text(
            enroll
                ? 'Scan twice. Remove the tag between scans.'
                : 'Use your saved tag.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await _gateway.open('cancelNfc');
                } catch (e) {
                  if (mounted) setState(() => _error = _message(e));
                }
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    // Enrollment is also an in-app scan, not a Strict-screen exit. Keep native
    // visibility established before starting reader mode (including queued
    // route-visibility commands from the setup sheet).
    _unlockDialog = true;
    await _syncStrictVisibility();
    _startingNfc = false;
    if (!mounted) {
      _unlockDialog = false;
      return null;
    }
    unawaited(navigator.push(route));
    final saved = await _perform(
      () => _gateway.command('nfc', {
        'enroll': enroll,
        if (name != null) 'name': name,
        if (revision != null) 'revision': revision,
      }),
    );
    if (route.isActive) navigator.removeRoute(route);
    _unlockDialog = false;
    if (mounted) _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    unawaited(_syncStrictVisibility());
    return saved ? _snapshot : null;
  }

  Future<void> _strictOptions(BlockingSnapshot s) async {
    if (_busy || _configurationLocked) return;
    var wait = (s.strict['waitSeconds'] as int?) ?? 180;
    var power = s.strict['power'] == true,
        wifi = s.strict['wifi'] == true,
        nfc = s.strict['nfc'] == true;
    var saving = false;
    var expectedRevision = s.revision;
    String? saveError;
    Future<void> save(
      bool enabled,
      BuildContext ctx,
      StateSetter update,
    ) async {
      if (saving || _busy) return;
      update(() {
        saving = true;
        saveError = null;
      });
      final saved = await _perform(
        () => _gateway.command('strict', {
          'enabled': enabled,
          'waitSeconds': wait,
          'power': power,
          'wifi': wifi,
          'nfc': nfc,
          'revision': expectedRevision,
        }),
      );
      if (!ctx.mounted) return;
      if (saved) {
        Navigator.pop(ctx);
      } else {
        update(() {
          saving = false;
          saveError = _error ?? 'Could not save. Try again.';
        });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !saving,
          child: SafeArea(
            child: AbsorbPointer(
              absorbing: saving,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Unlock method',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: wait,
                        decoration: const InputDecoration(labelText: 'Wait'),
                        items: [
                          for (final seconds in [
                            0,
                            10,
                            30,
                            60,
                            180,
                            300,
                            600,
                            900,
                          ])
                            DropdownMenuItem(
                              value: seconds,
                              child: Text(
                                seconds == 0
                                    ? 'Immediately'
                                    : seconds < 60
                                    ? '${seconds}s'
                                    : '${seconds ~/ 60}m',
                              ),
                            ),
                        ],
                        onChanged: (value) => update(() => wait = value!),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Charger connected'),
                        value: power,
                        onChanged: (v) => update(() => power = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Current Wi-Fi'),
                        value: wifi,
                        onChanged: wifi || _snapshot!.wifiReady
                            ? (v) => update(() => wifi = v)
                            : null,
                      ),
                      if (!_snapshot!.wifiReady)
                        TextButton(
                          onPressed: () async {
                            if (saving || _busy) return;
                            update(() => saving = true);
                            try {
                              final next = await _gateway.command(
                                'wifiPermission',
                              );
                              if (mounted) setState(() => _snapshot = next);
                              expectedRevision = next.revision;
                            } catch (e) {
                              if (ctx.mounted) {
                                update(() => saveError = _message(e));
                              }
                            } finally {
                              if (ctx.mounted) update(() => saving = false);
                            }
                          },
                          child: const Text('Set up Wi-Fi'),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('NFC tag'),
                        value: nfc,
                        onChanged: _snapshot!.nfcEnrolled
                            ? (v) => update(() => nfc = v)
                            : null,
                      ),
                      for (final tag in _snapshot!.nfcTags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppSurface(
                            variant: AppSurfaceVariant.subtle,
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              leading: const Icon(AppIcons.nfc),
                              title: Text(tag['name']!),
                              trailing: IconButton(
                                tooltip: 'Remove chip',
                                icon: const Icon(AppIcons.deleteOutline),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dialog) => AlertDialog(
                                      title: const Text('Remove chip?'),
                                      content: Text(tag['name']!),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !ctx.mounted) return;
                                  update(() => saving = true);
                                  final saved = await _perform(
                                    () => _gateway.command('removeNfcTag', {
                                      'id': tag['id']!,
                                      'revision': expectedRevision,
                                    }),
                                  );
                                  if (saved) {
                                    expectedRevision = _snapshot!.revision;
                                    if (!_snapshot!.nfcEnrolled) nfc = false;
                                  }
                                  if (ctx.mounted) {
                                    update(() {
                                      saving = false;
                                      saveError = _error;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      if (_snapshot!.nfcAvailable)
                        TextButton(
                          onPressed: () async {
                            if (saving || _busy) return;
                            update(() => saving = true);
                            final chipName = await showDialog<String>(
                              context: ctx,
                              builder: (_) => _NfcChipNameDialog(
                                initialName: _snapshot!.nfcEnrolled
                                    ? 'Backup chip'
                                    : 'Main chip',
                              ),
                            );
                            if (!ctx.mounted) return;
                            if (chipName == null) {
                              update(() => saving = false);
                              return;
                            }
                            final next = await _scan(
                              true,
                              name: chipName,
                              revision: expectedRevision,
                            );
                            if (next != null) expectedRevision = next.revision;
                            if (ctx.mounted) {
                              update(() {
                                saving = false;
                                saveError = _error;
                              });
                            }
                          },
                          child: Text(
                            _snapshot!.nfcEnrolled
                                ? '+ Add chip'
                                : 'Set up tag',
                          ),
                        ),
                      const Text('All selected conditions must be met.'),
                      const SizedBox(height: AppSpacing.md),
                      if (saveError != null)
                        Semantics(liveRegion: true, child: Text(saveError!)),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!_protectionReady) {
                                  update(() => saving = true);
                                  try {
                                    await _permissions();
                                  } finally {
                                    if (ctx.mounted) {
                                      update(() => saving = false);
                                    }
                                  }
                                  return;
                                }
                                await save(true, ctx, update);
                              },
                        child: saving
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _protectionReady
                                    ? 'Enable'
                                    : 'Set up protection',
                              ),
                      ),
                      if (s.strict['enabled'] == true)
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => save(false, ctx, update),
                          child: const Text('Turn off'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _charts(BlockingSnapshot s) => [
    Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final (days, label) in [(1, 'Today'), (7, 'Week'), (30, 'Month')])
          ChoiceChip(
            label: Text(label),
            selected: _days == days,
            onSelected: _busy
                ? null
                : (_) {
                    setState(() => _days = days);
                    unawaited(_usage());
                  },
          ),
      ],
    ),
    const SizedBox(height: AppSpacing.md),
    AppSurface(
      variant: AppSurfaceVariant.subtle,
      child: Row(
        children: [
          Expanded(child: _metric('${s.attemptsToday}', 'Attempts today')),
          Expanded(child: _metric('${s.attemptsTotal}', 'Total')),
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    if (!s.usageGranted)
      OutlinedButton(
        onPressed: _busy || _configurationLocked ? null : _enableUsage,
        child: const Text('Allow usage access'),
      )
    else if (_insights?['available'] == false)
      OutlinedButton(
        onPressed: _busy || _configurationLocked ? null : _enableUsage,
        child: const Text('Usage unavailable'),
      )
    else if (_insights == null)
      TextButton(
        onPressed: _busy ? null : _usage,
        child: const Text('Load usage'),
      )
    else ...[
      AppSurface(
        variant: AppSurfaceVariant.subtle,
        child: _UsageBars(
          values: (_insights!['daily'] as List? ?? const []).cast<Map>(),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Time spent', style: Theme.of(context).textTheme.titleMedium),
      for (final app in (_insights!['apps'] as List? ?? const []))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _usageAppIcon(app as Map),
          title: Text(app['label'] as String),
          trailing: Text(
            formatBlockingUsageDuration(app['milliseconds'] as int),
          ),
        ),
      if ((_insights!['apps'] as List? ?? const []).isEmpty)
        const Text('No usage available.'),
    ],
  ];
  Widget _usageAppIcon(Map app) {
    const fallback = Icon(AppIcons.devicesOutlined);
    final encoded = app['icon'];
    if (encoded is! String || encoded.isEmpty) return fallback;
    try {
      final size = IconTheme.of(context).size ?? 24;
      return Image.memory(
        base64Decode(encoded),
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      );
    } on FormatException {
      return fallback;
    }
  }

  Widget _metric(String value, String label) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
      Text(label, textAlign: TextAlign.center),
    ],
  );
  bool get _hasNativePreview =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _legacy?.platformSupported == true;

  List<Widget> _custom(BlockingSnapshot s) => [
    if (_hasNativePreview) ...[
      _customizeAction(s),
      const SizedBox(height: AppSpacing.md),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: BlockingScreenPreview(
                custom: s.custom,
                counters: {'today': s.attemptsToday, 'total': s.attemptsTotal},
                strictLocked: s.strict['enabled'] == true,
              ),
            ),
          ),
        ),
      ),
    ] else ...[
      Text(
        'Approximate preview · native on Android',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Theme(
        data: AppTheme.resolve(switch (s.custom['tone']) {
          'light' => AppThemeId.light,
          'dark' => AppThemeId.dark,
          'space' => AppThemeId.space,
          _ => AppThemeId.liquidGlass,
        }),
        child: Builder(
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Column(
              children: [
                Icon(
                  blockingIcon(s.custom['icon'] as String? ?? 'shield'),
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  s.custom['title'] as String? ?? 'Stay focused',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  s.custom['message'] as String? ??
                      'Take a breath. Choose your next step.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${s.attemptsToday} today · ${s.attemptsTotal} total',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 286,
                    minHeight: 48,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: null,
                      child: Text(
                        (s.custom['waitSeconds'] as int? ?? 0) == 0
                            ? 'Return to MyLifeGraph'
                            : 'Return in ${s.custom['waitSeconds']}s',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _customizeAction(s),
    ],
  ];

  Widget _customizeAction(BlockingSnapshot s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 286, minHeight: 48),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _configurationLocked || _busy
                ? null
                : () => _customize(s),
            icon: const Icon(AppIcons.tuneOutlined),
            label: const Text('Customize'),
          ),
        ),
      ),
    ),
  );
  Future<void> _customize(BlockingSnapshot s) async {
    if (_busy || _configurationLocked) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      builder: (_) => BlockingCustomEditor(
        custom: s.custom,
        iconBuilder: blockingIcon,
        strictEnabled: s.strict['enabled'] == true,
        error: () => _error,
        onSave: (custom) =>
            _save(s.plans, custom: custom, expectedRevision: s.revision),
      ),
    );
  }
}

class _NfcChipNameDialog extends StatefulWidget {
  const _NfcChipNameDialog({required this.initialName});
  final String initialName;
  @override
  State<_NfcChipNameDialog> createState() => _NfcChipNameDialogState();
}

class _NfcChipNameDialogState extends State<_NfcChipNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add chip'),
    content: TextField(
      controller: _controller,
      maxLength: 40,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (_controller.text.trim().isNotEmpty) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Scan'),
      ),
    ],
  );
}

const _iconNames = ['shield', 'work', 'games', 'social', 'sleep', 'study'];

class BlockingPlanEditor extends StatefulWidget {
  const BlockingPlanEditor({
    required this.catalog,
    required this.usageGranted,
    required this.websiteAllowed,
    this.plan,
    this.quick = false,
    this.onSave,
    super.key,
  });
  final List<Map> catalog;
  final bool usageGranted, websiteAllowed, quick;
  final BlockingPlan? plan;
  final Future<void> Function(BlockingPlan)? onSave;
  @override
  State<BlockingPlanEditor> createState() => _BlockingPlanEditorState();
}

class _BlockingPlanEditorState extends State<BlockingPlanEditor> {
  late final TextEditingController _name;
  final _domain = TextEditingController();
  final _appScroll = ScrollController();
  final _appsKey = GlobalKey();
  String _icon = 'shield', _search = '';
  String? _error;
  bool _saving = false;
  bool _focus = true, _always = false, _appsExpanded = true;
  bool _windowsEnabled = false, _budgetEnabled = false;
  late final List<Map> _orderedCatalog;
  String? _firstUnselectedApp;
  final Set<String> _siteChoices = {};
  String _siteCategory = 'Social media';
  int _budget = 0, _until = 0;
  Set<String> _apps = {}, _sites = {};
  List<BlockingWindow> _windows = [];
  final Map<String, Uint8List> _icons = {};
  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _name = TextEditingController(
      text: p?.name ?? (widget.quick ? 'Quick Block' : ''),
    );
    if (p != null) {
      _icon = p.icon;
      _focus = p.focus;
      _always = p.always;
      _budget = p.budget;
      _until = p.until;
      _apps = {...p.apps};
      _sites = {...p.sites};
      _windows = [...p.windows];
    } else if (widget.quick) {
      _focus = false;
      _until = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
    }
    _windowsEnabled = _windows.isNotEmpty;
    _budgetEnabled = _budget > 0;
    _siteChoices.addAll(_sites);
    // Snapshot the opening selection: checking a row must not move it away
    // from the user's finger. Reopening applies the new selection order.
    _orderedCatalog = [
      ...widget.catalog.where((a) => _apps.contains(a['packageName'])),
      ...widget.catalog.where((a) => !_apps.contains(a['packageName'])),
    ];
    if (_orderedCatalog.any((a) => _apps.contains(a['packageName']))) {
      for (final app in _orderedCatalog) {
        if (!_apps.contains(app['packageName'])) {
          _firstUnselectedApp = app['packageName'] as String;
          break;
        }
      }
    }
    for (final app in widget.catalog) {
      final data = app['icon'] as String? ?? '';
      if (data.isNotEmpty) {
        try {
          _icons[app['packageName'] as String] = base64Decode(data);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    _appScroll.dispose();
    super.dispose();
  }

  void _toggleApps({bool reveal = false}) {
    if (_saving) return;
    setState(() => _appsExpanded = !_appsExpanded);
    if (reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _appsKey.currentContext == null) return;
        Scrollable.ensureVisible(_appsKey.currentContext!);
      });
    }
  }

  Set<String> _presetApps(bool games) => widget.catalog
      .where(
        (app) => games
            ? app['category'] == 'Games'
            : _socialPackages.contains(app['packageName']),
      )
      .map((app) => app['packageName'] as String)
      .toSet();

  Widget _presetChip(String label, Set<String> packages) => FilterChip(
    label: Text(label),
    selected: packages.isNotEmpty && _apps.containsAll(packages),
    onSelected: _saving || packages.isEmpty
        ? null
        : (_) => setState(() => _apps.addAll(packages)),
  );

  Future<void> _finish() async {
    if (_saving) return;
    final p = BlockingPlan(
      id: widget.plan?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      icon: _icon,
      apps: _apps,
      sites: _sites,
      focus: _focus,
      always: _always,
      budget: _budgetEnabled ? _budget : 0,
      until: _until,
      windows: _windowsEnabled ? _windows : const [],
      enabled: widget.plan?.enabled ?? true,
      pausedUntil: widget.plan?.pausedUntil ?? 0,
    );
    if (p.name.isEmpty || p.apps.isEmpty && p.sites.isEmpty || !p.hasRule) {
      setState(() => _error = 'Add a name, a target and a rule.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await widget.onSave?.call(p);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _window([int? index]) async {
    final old = index == null ? const BlockingWindow() : _windows[index];
    var start = old.start, end = old.end;
    final days = {...old.days};
    final result = await showModalBottomSheet<BlockingWindow>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Active time',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_BlockingPageState._dayNames[day - 1]),
                          selected: days.contains(day),
                          onSelected: (v) => update(
                            () => v ? days.add(day) : days.remove(day),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final isStart in [true, false])
                        OutlinedButton(
                          onPressed: () async {
                            final current = isStart ? start : end;
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay(
                                hour: current ~/ 60,
                                minute: current % 60,
                              ),
                            );
                            if (picked != null && ctx.mounted) {
                              update(() {
                                if (isStart) {
                                  start = picked.hour * 60 + picked.minute;
                                } else {
                                  end = picked.hour * 60 + picked.minute;
                                }
                              });
                            }
                          },
                          child: Text(
                            '${isStart ? 'From' : 'Until'} ${TimeOfDay(hour: (isStart ? start : end) ~/ 60, minute: (isStart ? start : end) % 60).format(ctx)}',
                          ),
                        ),
                    ],
                  ),
                  Text(end < start ? 'Next day · Device time' : 'Device time'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: days.isEmpty || start == end
                        ? null
                        : () => Navigator.pop(
                            ctx,
                            BlockingWindow(days: days, start: start, end: end),
                          ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          _windows.add(result);
        } else {
          _windows[index] = result;
        }
      });
    }
  }

  void _addDomain() {
    final raw = _domain.text.trim();
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ?? '';
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        !RegExp(
          r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
        ).hasMatch(host)) {
      setState(() => _error = 'Enter a domain, e.g. instagram.com');
      return;
    }
    setState(() {
      _sites.add(host);
      _siteChoices.add(host);
      _domain.clear();
      _error = null;
    });
  }

  Future<void> _customMinutes(bool budget) async {
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => _MinutesDialog(
        title: budget ? 'Daily budget' : 'Block now',
        maximum: budget && !widget.usageGranted ? widget.plan!.budget : 1440,
      ),
    );
    if (value != null && mounted) {
      if (budget &&
          !widget.usageGranted &&
          value > (widget.plan?.budget ?? 0)) {
        return;
      }
      setState(() {
        if (budget) {
          _budget = value;
        } else {
          _until = DateTime.now()
              .add(Duration(minutes: value))
              .millisecondsSinceEpoch;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: DraggableScrollableSheet(
      initialChildSize: .92,
      minChildSize: .6,
      maxChildSize: .96,
      expand: false,
      builder: (ctx, controller) => SafeArea(
        child: ExcludeFocus(
          excluding: _saving,
          child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: const ValueKey('blocking-editor-scroll'),
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      MediaQuery.viewInsetsOf(ctx).bottom + AppSpacing.lg,
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.plan == null ? 'New plan' : 'Edit plan',
                              style: Theme.of(ctx).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(ctx),
                            icon: const Icon(AppIcons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(child: Icon(blockingIcon(_icon), size: 48)),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _name,
                        readOnly: _saving,
                        maxLength: 60,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final name in _iconNames)
                            IconButton(
                              tooltip: name,
                              isSelected: _icon == name,
                              onPressed: () => setState(() => _icon = name),
                              icon: Icon(blockingIcon(name)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppSurface(
                        key: const ValueKey('blocking-rules'),
                        variant: AppSurfaceVariant.subtle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Rules',
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(AppIcons.timerOutlined),
                              title: const Text('Focus session'),
                              value: _focus,
                              onChanged: (v) => setState(() => _focus = v),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(AppIcons.shieldOutlined),
                              title: const Text('Always'),
                              value: _always,
                              onChanged: (v) => setState(() => _always = v),
                            ),
                            SwitchListTile(
                              key: const ValueKey('blocking-windows-toggle'),
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(AppIcons.schedule),
                              title: const Text('Time windows'),
                              value: _windowsEnabled,
                              onChanged: (v) =>
                                  setState(() => _windowsEnabled = v),
                            ),
                            if (_windowsEnabled) ...[
                              for (
                                var index = 0;
                                index < _windows.length;
                                index++
                              )
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${_clock(_windows[index].start)}–${_clock(_windows[index].end)}',
                                  ),
                                  subtitle: Text(
                                    _windows[index].days
                                        .map(
                                          (d) =>
                                              _BlockingPageState._dayNames[d -
                                                  1],
                                        )
                                        .join(' '),
                                  ),
                                  onTap: () => _window(index),
                                  trailing: IconButton(
                                    tooltip: 'Remove time',
                                    icon: const Icon(AppIcons.close),
                                    onPressed: () => setState(
                                      () => _windows.removeAt(index),
                                    ),
                                  ),
                                ),
                              TextButton.icon(
                                onPressed: _windows.length < 12
                                    ? _window
                                    : null,
                                icon: const Icon(AppIcons.schedule),
                                label: const Text('Add time'),
                              ),
                            ],
                            SwitchListTile(
                              key: const ValueKey('blocking-budget-toggle'),
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(AppIcons.hourglass),
                              title: const Text('Shared daily budget'),
                              value: _budgetEnabled,
                              onChanged:
                                  widget.usageGranted ||
                                      (widget.plan?.budget ?? 0) > 0
                                  ? (v) => setState(() {
                                      _budgetEnabled = v;
                                      if (v && _budget == 0) {
                                        _budget = widget.usageGranted
                                            ? 45
                                            : widget.plan!.budget;
                                      }
                                    })
                                  : null,
                            ),
                            if (_budgetEnabled) ...[
                              DropdownButtonFormField<int>(
                                key: ValueKey('budget-$_budget'),
                                initialValue: _budget,
                                decoration: const InputDecoration(
                                  labelText: 'Daily budget',
                                ),
                                items: [
                                  for (final minutes
                                      in ({
                                            15,
                                            30,
                                            45,
                                            60,
                                            90,
                                            120,
                                            180,
                                            240,
                                            _budget,
                                          }
                                          .where(
                                            (v) =>
                                                widget.usageGranted ||
                                                v <= (widget.plan?.budget ?? 0),
                                          )
                                          .toList()
                                        ..sort()))
                                    DropdownMenuItem(
                                      value: minutes,
                                      child: Text(
                                        minutes == 0 ? 'Off' : '${minutes}m',
                                      ),
                                    ),
                                ],
                                onChanged:
                                    widget.usageGranted ||
                                        (widget.plan?.budget ?? 0) > 0
                                    ? (v) => setState(() => _budget = v!)
                                    : null,
                              ),
                              if (widget.usageGranted ||
                                  (widget.plan?.budget ?? 0) > 0)
                                TextButton(
                                  onPressed: () => _customMinutes(true),
                                  child: const Text('Custom budget'),
                                ),
                              if (!widget.usageGranted)
                                const Text('Enable budgets on Plans first.'),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            const Divider(),
                            Text(
                              'Block now',
                              style: Theme.of(ctx).textTheme.titleSmall,
                            ),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                for (final minutes in [15, 60, 120])
                                  ActionChip(
                                    label: Text(
                                      minutes == 15
                                          ? '15m'
                                          : '${minutes ~/ 60}h',
                                    ),
                                    onPressed: () => setState(
                                      () => _until = DateTime.now()
                                          .add(Duration(minutes: minutes))
                                          .millisecondsSinceEpoch,
                                    ),
                                  ),
                                if (_until > 0)
                                  ActionChip(
                                    label: const Text('Clear timer'),
                                    onPressed: () => setState(() => _until = 0),
                                  ),
                                ActionChip(
                                  label: const Text('Custom'),
                                  onPressed: () => _customMinutes(false),
                                ),
                              ],
                            ),
                            if (_until > DateTime.now().millisecondsSinceEpoch)
                              Text(
                                'Until ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(_until)).format(ctx)}',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppSurface(
                        key: _appsKey,
                        variant: AppSurfaceVariant.subtle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Apps · ${_apps.length}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_appsExpanded)
                                    for (final package in _apps.take(4))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: AppSpacing.xs,
                                        ),
                                        child: Tooltip(
                                          message: package,
                                          child: _icons[package] == null
                                              ? const Icon(
                                                  AppIcons.devicesOutlined,
                                                  size: 16,
                                                )
                                              : Image.memory(
                                                  _icons[package]!,
                                                  width: 16,
                                                  height: 16,
                                                ),
                                        ),
                                      ),
                                  Icon(
                                    _appsExpanded
                                        ? AppIcons.expandLess
                                        : AppIcons.expandMore,
                                  ),
                                ],
                              ),
                              onTap: _toggleApps,
                            ),
                            if (_appsExpanded) ...[
                              TextField(
                                readOnly: _saving,
                                decoration: const InputDecoration(
                                  labelText: 'Search apps',
                                ),
                                onChanged: (v) =>
                                    setState(() => _search = v.toLowerCase()),
                              ),
                              Wrap(
                                spacing: AppSpacing.sm,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _apps.clear()),
                                    child: const Text('Clear'),
                                  ),
                                  _presetChip(
                                    'Social media',
                                    _presetApps(false),
                                  ),
                                  _presetChip('Games', _presetApps(true)),
                                ],
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      (MediaQuery.sizeOf(ctx).height * .35)
                                          .clamp(128.0, 300.0),
                                ),
                                child: Scrollbar(
                                  controller: _appScroll,
                                  thumbVisibility: true,
                                  child: ListView(
                                    key: const ValueKey('blocking-app-list'),
                                    controller: _appScroll,
                                    primary: false,
                                    shrinkWrap: true,
                                    children: [
                                      for (final app in _orderedCatalog.where(
                                        (a) =>
                                            '${a['label']} ${a['packageName']}'
                                                .toLowerCase()
                                                .contains(_search),
                                      )) ...[
                                        if (_search.isEmpty &&
                                            app['packageName'] ==
                                                _firstUnselectedApp)
                                          const Divider(height: 1),
                                        CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Tooltip(
                                            message:
                                                app['packageName'] as String,
                                            child: Text(app['label'] as String),
                                          ),
                                          secondary:
                                              _icons[app['packageName']] == null
                                              ? const Icon(
                                                  AppIcons.devicesOutlined,
                                                )
                                              : Image.memory(
                                                  _icons[app['packageName']]!,
                                                  width: 32,
                                                  height: 32,
                                                ),
                                          value: _apps.contains(
                                            app['packageName'],
                                          ),
                                          checkboxScaleFactor: 1.25,
                                          activeColor: Theme.of(
                                            ctx,
                                          ).colorScheme.primary,
                                          checkColor: Theme.of(
                                            ctx,
                                          ).colorScheme.onPrimary,
                                          side: BorderSide(
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.outline,
                                            width: 2,
                                          ),
                                          onChanged: (v) => setState(
                                            () => v!
                                                ? _apps.add(
                                                    app['packageName']
                                                        as String,
                                                  )
                                                : _apps.remove(
                                                    app['packageName'],
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppSurface(
                        variant: AppSurfaceVariant.subtle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Websites · ${_sites.length}',
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                            if (!widget.websiteAllowed)
                              const Text('Enable websites on Plans first.')
                            else ...[
                              TextField(
                                controller: _domain,
                                readOnly: _saving,
                                decoration: InputDecoration(
                                  labelText: 'Search or add domain',
                                  suffixIcon: IconButton(
                                    tooltip: 'Add website',
                                    onPressed: _addDomain,
                                    icon: const Icon(AppIcons.add),
                                  ),
                                ),
                                onSubmitted: (_) => _addDomain(),
                                onChanged: (_) => setState(() {}),
                              ),
                              Wrap(
                                spacing: AppSpacing.sm,
                                children: [
                                  for (final category in [
                                    'Social media',
                                    'Video',
                                  ])
                                    FilterChip(
                                      label: Text(category),
                                      selected: _siteCategory == category,
                                      onSelected: (_) => setState(
                                        () => _siteCategory = category,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const Divider(),
                            for (final domain
                                in <String>{
                                  ...?widget.plan?.sites,
                                  ..._siteChoices,
                                  if (widget.websiteAllowed)
                                    ...(_siteCategory == 'Video'
                                        ? ['youtube.com', 'twitch.tv']
                                        : [
                                            'instagram.com',
                                            'reddit.com',
                                            'x.com',
                                            'facebook.com',
                                          ]),
                                }.where(
                                  (d) =>
                                      _domain.text.isEmpty ||
                                      d.contains(_domain.text.toLowerCase()) ||
                                      _sites.contains(d),
                                ))
                              CheckboxListTile(
                                key: ValueKey('blocking-site-$domain'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(domain),
                                secondary: blockingWebsiteIcon(domain),
                                value: _sites.contains(domain),
                                checkboxScaleFactor: 1.25,
                                onChanged:
                                    widget.websiteAllowed ||
                                        (widget.plan?.sites.contains(domain) ??
                                            false)
                                    ? (v) => setState(
                                        () => v!
                                            ? _sites.add(domain)
                                            : _sites.remove(domain),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
                Padding(
                  key: const ValueKey('blocking-save-footer'),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    MediaQuery.viewInsetsOf(ctx).bottom + AppSpacing.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Text(
                              _error!,
                              style: Theme.of(ctx).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(ctx).colorScheme.error,
                                  ),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Semantics(
                            expanded: _appsExpanded,
                            child: IconButton(
                              key: const ValueKey(
                                'blocking-footer-apps-toggle',
                              ),
                              onPressed: () => _toggleApps(reveal: true),
                              tooltip: _appsExpanded
                                  ? 'Collapse apps'
                                  : 'Expand apps',
                              icon: Icon(
                                _appsExpanded
                                    ? AppIcons.expandLess
                                    : AppIcons.expandMore,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${_apps.length} apps · ${_sites.length} sites',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton(
                            onPressed: _saving ? null : _finish,
                            child: _saving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  String _clock(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
}

class _MinutesDialog extends StatefulWidget {
  const _MinutesDialog({required this.title, this.maximum = 1440});
  final String title;
  final int maximum;
  @override
  State<_MinutesDialog> createState() => _MinutesDialogState();
}

class _MinutesDialogState extends State<_MinutesDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(controller.text);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Minutes',
          helperText: '1–${widget.maximum}',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              minutes != null && minutes >= 1 && minutes <= widget.maximum
              ? () => Navigator.pop(context, minutes)
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

const _socialPackages = {
  'com.instagram.android',
  'com.twitter.android',
  'com.facebook.katana',
  'com.zhiliaoapp.musically',
  'com.snapchat.android',
  'com.reddit.frontpage',
  'com.google.android.youtube',
  'com.instagram.barcelona',
  'com.linkedin.android',
  'com.pinterest',
};

class _UsageBars extends StatelessWidget {
  const _UsageBars({required this.values});
  final List<Map> values;
  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(
      0,
      (a, v) => (v['milliseconds'] as int) > a ? v['milliseconds'] as int : a,
    );
    final total = values.fold<int>(
      0,
      (sum, value) => sum + (value['milliseconds'] as int),
    );
    final labelsAbove =
        values.length <= 7 &&
        MediaQuery.textScalerOf(context).scale(12) < 18 &&
        values.every((v) => _usageLabel(v['milliseconds'] as int).length <= 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text('Daily usage', style: Theme.of(context).textTheme.titleMedium),
            Text('Total ${_usageLabel(total)}'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (values.length > 7)
          Text(
            'Peak ${_usageLabel(maximum)}',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final value in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message:
                          '${_dateLabel(context, value)} · ${_usageLabel(value['milliseconds'] as int)}',
                      child: Semantics(
                        label:
                            '${_dateLabel(context, value)} · ${_usageLabel(value['milliseconds'] as int)}',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (labelsAbove) ...[
                              Text(
                                _usageLabel(value['milliseconds'] as int),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                            ],
                            SizedBox(
                              height:
                                  ((value['milliseconds'] as int) /
                                          (maximum == 0 ? 1 : maximum))
                                      .clamp(.015, 1) *
                                  (labelsAbove ? 116 : 140),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.sm,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (values.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          if (values.length <= 7 && !labelsAbove)
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(12) >= 18;
                if (largeText) {
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final value in values)
                        Text(
                          '${_dateLabel(context, value)}: ${_usageLabel(value['milliseconds'] as int)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final value in values)
                      Expanded(
                        child: Text(
                          _usageLabel(value['milliseconds'] as int),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                );
              },
            ),
          if (values.length <= 7 && !labelsAbove)
            const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final value in [
                values.first,
                if (values.length > 2) values[values.length ~/ 2],
                if (values.length > 1) values.last,
              ])
                Flexible(
                  child: Text(
                    MaterialLocalizations.of(context).formatShortMonthDay(
                      DateTime.fromMillisecondsSinceEpoch(
                        value['dateEpochMs'] as int,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _dateLabel(BuildContext context, Map value) =>
      MaterialLocalizations.of(context).formatShortMonthDay(
        DateTime.fromMillisecondsSinceEpoch(value['dateEpochMs'] as int),
      );

  String _usageLabel(int milliseconds) {
    return formatBlockingUsageDuration(milliseconds);
  }
}
