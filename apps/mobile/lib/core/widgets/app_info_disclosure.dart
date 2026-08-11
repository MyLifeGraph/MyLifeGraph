import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion_tokens.dart';

typedef AppInfoHeaderBuilder = Widget Function(
  BuildContext context,
  Widget infoButton,
);

enum AppInfoDisclosureLayout { standard, compact }

/// Standard section heading with the shared 44-pixel information control.
class AppInfoSectionDisclosure extends StatelessWidget {
  const AppInfoSectionDisclosure({
    required this.heading,
    required this.description,
    this.headingStyle,
    this.compactHeading = false,
    this.descriptionStyle,
    this.keyPrefix = 'app-info',
    super.key,
  });

  final String heading;
  final String description;
  final TextStyle? headingStyle;
  final bool compactHeading;
  final TextStyle? descriptionStyle;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return AppInfoDisclosure(
      topic: heading,
      description: description,
      descriptionStyle: descriptionStyle,
      keyPrefix: keyPrefix,
      headerBuilder: (context, infoButton) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                heading,
                style: headingStyle ??
                    (compactHeading
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge),
              ),
            ),
          ),
          infoButton,
        ],
      ),
    );
  }
}

/// Shared, non-persisted disclosure for optional explanatory copy.
///
/// Standard controls use the product-wide 44 logical-pixel action target.
/// The compact layout is reserved for Today headers: its visible control is
/// 24 logical pixels inside a 44-pixel-tall layout slot.
class AppInfoDisclosure extends StatefulWidget {
  const AppInfoDisclosure({
    required this.topic,
    required this.description,
    required this.headerBuilder,
    this.descriptionStyle,
    this.layout = AppInfoDisclosureLayout.standard,
    this.keyPrefix = 'app-info',
    super.key,
  });

  final String topic;
  final String description;
  final AppInfoHeaderBuilder headerBuilder;
  final TextStyle? descriptionStyle;
  final AppInfoDisclosureLayout layout;
  final String keyPrefix;

  @override
  State<AppInfoDisclosure> createState() => _AppInfoDisclosureState();
}

class _AppInfoDisclosureState extends State<AppInfoDisclosure> {
  static const _standardControlSize = 44.0;
  static const _compactControlSize = 24.0;
  static const _iconSize = 20.0;
  static const _compactVerticalLayoutPadding = 10.0;

  bool _expanded = false;

  @override
  void didUpdateWidget(AppInfoDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic != widget.topic) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motionTokens;
    final duration = motion.stateFor(context);
    final actionLabel =
        '${_expanded ? 'Hide' : 'Show'} information about ${widget.topic}';
    final infoButton = switch (widget.layout) {
      AppInfoDisclosureLayout.standard => _standardButton(
          context,
          actionLabel,
        ),
      AppInfoDisclosureLayout.compact => _compactButton(
          context,
          actionLabel,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.headerBuilder(context, infoButton),
        ExcludeSemantics(
          excluding: !_expanded,
          child: AnimatedSwitcher(
            duration: duration,
            reverseDuration: duration,
            switchInCurve: motion.curve,
            switchOutCurve: motion.curve,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: motion.curve,
                reverseCurve: motion.curve,
              );
              return SizeTransition(
                sizeFactor: curved,
                alignment: AlignmentDirectional.topStart,
                child: FadeTransition(opacity: curved, child: child),
              );
            },
            child: _expanded
                ? Padding(
                    key: ValueKey(
                      '${widget.keyPrefix}-description-${widget.topic}',
                    ),
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      widget.description,
                      style: widget.descriptionStyle ??
                          Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : SizedBox(
                    key: ValueKey(
                      '${widget.keyPrefix}-description-closed-${widget.topic}',
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _standardButton(BuildContext context, String actionLabel) {
    return SizedBox.square(
      key: ValueKey('${widget.keyPrefix}-control-${widget.topic}'),
      dimension: _standardControlSize,
      child: _button(context, actionLabel),
    );
  }

  Widget _compactButton(BuildContext context, String actionLabel) {
    final inheritedStyle = IconButtonTheme.of(context).style;
    final compactStyle = (inheritedStyle ?? const ButtonStyle()).copyWith(
      minimumSize: const WidgetStatePropertyAll(
        Size.square(_compactControlSize),
      ),
      fixedSize: const WidgetStatePropertyAll(
        Size.square(_compactControlSize),
      ),
      maximumSize: const WidgetStatePropertyAll(
        Size.square(_compactControlSize),
      ),
      iconSize: const WidgetStatePropertyAll(_iconSize),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      key: ValueKey('${widget.keyPrefix}-layout-${widget.topic}'),
      padding: const EdgeInsets.symmetric(
        vertical: _compactVerticalLayoutPadding,
      ),
      child: SizedBox.square(
        key: ValueKey('${widget.keyPrefix}-control-${widget.topic}'),
        dimension: _compactControlSize,
        child: IconButtonTheme(
          data: IconButtonThemeData(style: compactStyle),
          child: _button(context, actionLabel),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String actionLabel) {
    return Semantics(
      button: true,
      expanded: _expanded,
      label: actionLabel,
      onTap: _toggle,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: actionLabel,
          color: Theme.of(context).colorScheme.primary,
          onPressed: _toggle,
          icon: const Icon(AppIcons.infoOutline, size: _iconSize),
        ),
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}
