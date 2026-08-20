import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../composition/auth_providers.dart';

class AccountDeletionRecoveryPage extends ConsumerStatefulWidget {
  const AccountDeletionRecoveryPage({super.key});

  @override
  ConsumerState<AccountDeletionRecoveryPage> createState() =>
      _AccountDeletionRecoveryPageState();
}

class _AccountDeletionRecoveryPageState
    extends ConsumerState<AccountDeletionRecoveryPage> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final recovery =
        ref.watch(authControllerProvider).valueOrNull?.deletionRecovery;
    final durable = recovery?.journalDurable == true;
    final completed = recovery?.isCompleted == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Account deletion')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              completed
                  ? 'Deletion completed'
                  : durable
                      ? 'Deletion safely recorded'
                      : 'Deletion needs another retry',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              completed
                  ? 'Your synced account data has been deleted. Finish signing out on this device.'
                  : durable
                      ? 'The off-site recovery journal is confirmed. The server will keep retrying until the account is removed.'
                      : 'The app kept the same deletion identity on this device. Retry while signed in; do not start a second deletion request.',
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : durable
                      ? _finishSignOut
                      : _retry,
              child: Text(
                _busy
                    ? 'Working…'
                    : durable
                        ? 'Finish sign-out'
                        : 'Retry deletion',
              ),
            ),
            if (!durable) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _signOutForLater,
                child: const Text('Sign out and retry later'),
              ),
              const SizedBox(height: 8),
              const Text(
                'The retry identity remains on this device. Sign in to the same account to continue.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final recovery = await ref
          .read(authControllerProvider.notifier)
          .retryAccountDeletion();
      if (!mounted) return;
      if (recovery?.journalDurable == true) {
        setState(() {
          _message = recovery?.isCompleted == true
              ? 'Deletion completed. Finish sign-out.'
              : 'Deletion is durably recorded. Finish sign-out while the server completes it.';
        });
      } else {
        setState(() {
          _message =
              'The recovery journal is not confirmed yet. The same request remains ready to retry.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Retry failed. The same request remains saved on this device.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishSignOut() async {
    setState(() => _busy = true);
    ref.read(authNoticeProvider.notifier).state = const AuthNotice(
      'Account deletion is safely recorded. The server will finish any remaining cleanup.',
    );
    try {
      await ref.read(authControllerProvider.notifier).finalizeDeletedAccount();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Local sign-out could not be confirmed. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutForLater() async {
    setState(() => _busy = true);
    ref.read(authNoticeProvider.notifier).state = const AuthNotice(
      'Deletion is not yet durably confirmed. Sign in to the same account to retry it.',
      isError: true,
    );
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not sign out. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
