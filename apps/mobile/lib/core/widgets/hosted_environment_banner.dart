import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

class HostedEnvironmentBanner extends StatelessWidget {
  const HostedEnvironmentBanner({
    required this.environment,
    required this.child,
    super.key,
  });

  final String environment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (environment.trim().toLowerCase() != 'staging') return child;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: colors.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              container: true,
              label: 'Staging · Test data',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Center(
                    child: Text(
                      'Staging · Test data',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colors.onTertiaryContainer,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
