import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_visual_tokens.dart';

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
/// Every layout uses one 44 logical-pixel action and semantics target around a
/// consistent visible 24 logical-pixel frame.
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
  static const _controlSize = 44.0;
  static const _visibleFrameSize = 24.0;
  static const _iconSize = 20.0;

  bool _expanded = false;
  bool _focused = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(AppInfoDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic != widget.topic) _expanded = false;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motionTokens;
    final duration = motion.stateFor(context);
    final actionLabel =
        '${_expanded ? 'Hide' : 'Show'} information about ${widget.topic}';
    final infoButton = _button(context, actionLabel);

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

  Widget _button(BuildContext context, String actionLabel) {
    final tokens = context.visualTokens;
    return SizedBox.square(
      key: ValueKey('${widget.keyPrefix}-control-${widget.topic}'),
      dimension: _controlSize,
      child: Semantics(
        container: true,
        button: true,
        expanded: _expanded,
        label: actionLabel,
        onTap: _toggle,
        child: ExcludeSemantics(
          child: IconButton(
            tooltip: actionLabel,
            color: Theme.of(context).colorScheme.primary,
            onPressed: _toggle,
            focusNode: _focusNode,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: _controlSize,
              height: _controlSize,
            ),
            icon: AnimatedContainer(
              duration: context.motionTokens.stateFor(context),
              width: _visibleFrameSize,
              height: _visibleFrameSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(
                  color: _focused ? tokens.focus : tokens.outlineSoft,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Center(
                child: SizedBox.square(
                  key: ValueKey(
                    '${widget.keyPrefix}-icon-${widget.topic}',
                  ),
                  dimension: _iconSize,
                  child: const Icon(AppIcons.infoOutline, size: _iconSize),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  void _handleFocus() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }
}
