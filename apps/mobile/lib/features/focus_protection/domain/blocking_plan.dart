import 'package:flutter/foundation.dart';

@immutable
class BlockingWindow {
  const BlockingWindow({
    this.days = const {1, 2, 3, 4, 5},
    this.start = 540,
    this.end = 1080,
  });
  final Set<int> days;
  final int start, end;
  factory BlockingWindow.fromMap(Map map) => BlockingWindow(
    days: (map['weekdays'] as List).cast<int>().toSet(),
    start: map['startMinute'] as int,
    end: map['endMinute'] as int,
  );
  Map<String, Object> toMap() => {
    'weekdays': days.toList()..sort(),
    'startMinute': start,
    'endMinute': end,
  };
}

@immutable
class BlockingPlan {
  const BlockingPlan({
    required this.id,
    required this.name,
    this.icon = 'shield',
    this.apps = const {},
    this.sites = const {},
    this.focus = false,
    this.always = false,
    this.windows = const [],
    this.until = 0,
    this.budget = 0,
    this.enabled = true,
    this.pausedUntil = 0,
    this.active = false,
    this.usedMs = 0,
  });
  final String id, name, icon;
  final Set<String> apps, sites;
  final bool focus, always, enabled, active;
  final List<BlockingWindow> windows;
  final int until, budget, pausedUntil, usedMs;
  factory BlockingPlan.fromMap(Map map) => BlockingPlan(
    id: map['id'] as String,
    name: map['name'] as String,
    icon: map['icon'] as String,
    apps: (map['apps'] as List).cast<String>().toSet(),
    sites: (map['sites'] as List).cast<String>().toSet(),
    focus: map['focus'] as bool,
    always: map['always'] as bool,
    windows: (map['windows'] as List)
        .map((v) => BlockingWindow.fromMap(v as Map))
        .toList(),
    until: map['untilEpochMs'] as int,
    budget: map['budgetMinutes'] as int,
    enabled: map['enabled'] as bool,
    pausedUntil: map['pausedUntil'] as int,
    active: map['active'] as bool? ?? false,
    usedMs: map['usedMs'] as int? ?? 0,
  );
  Map<String, Object> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'apps': apps.toList()..sort(),
    'sites': sites.toList()..sort(),
    'focus': focus,
    'always': always,
    'windows': windows.map((w) => w.toMap()).toList(),
    'untilEpochMs': until,
    'budgetMinutes': budget,
    'enabled': enabled,
    'pausedUntil': pausedUntil,
  };
  BlockingPlan copyWith({
    String? id,
    String? name,
    bool? enabled,
    int? pausedUntil,
  }) => BlockingPlan(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon,
    apps: apps,
    sites: sites,
    focus: focus,
    always: always,
    windows: windows,
    until: until,
    budget: budget,
    enabled: enabled ?? this.enabled,
    pausedUntil: pausedUntil ?? this.pausedUntil,
  );
  bool get paused =>
      !enabled || pausedUntil > DateTime.now().millisecondsSinceEpoch;
  bool get hasRule =>
      focus || always || windows.isNotEmpty || budget > 0 || until > 0;
  bool get expired =>
      until > 0 &&
      until <= DateTime.now().millisecondsSinceEpoch &&
      !focus &&
      !always &&
      windows.isEmpty &&
      budget == 0;
  String get summary => [
    if (focus) 'Focus',
    if (windows.isNotEmpty) 'Weekly',
    if (always) 'Always',
    if (until > DateTime.now().millisecondsSinceEpoch) 'Timer',
    if (budget > 0)
      '${((budget * 60000 - usedMs).clamp(0, budget * 60000)) ~/ 60000}m left / ${budget}m',
  ].join(' · ');
}
