import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capabilities/app_surface_capabilities.dart';
import '../network/network_availability.dart';

class OfflineStatusBanner extends ConsumerWidget {
  const OfflineStatusBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(networkAvailableProvider).valueOrNull;
    final isLocalDemo = ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo;
    final semanticMessage = isLocalDemo
        ? 'No network interface detected. Local guest and demo data remains on this device.'
        : 'No network interface detected. Synced account changes are not queued. Retry after reconnecting.';
    final visibleMessage = isLocalDemo
        ? 'No network interface · local guest/demo saves remain on this device.'
        : 'No network interface · synced account changes are not queued. '
            'Keep drafts and retry after reconnecting.';
    return Column(
      children: [
        if (available == false)
          Semantics(
            liveRegion: true,
            container: true,
            label: semanticMessage,
            child: ExcludeSemantics(
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            visibleMessage,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}
