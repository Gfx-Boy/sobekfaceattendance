import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Explains why a workspace screen is empty instead of showing a bare "nothing
/// here", which round 5 established is the misleading version of this.
///
/// [reason] is the provider's `linkError`; the sentinel 'not-linked' means the
/// employee simply has no web session yet, which is not an error to apologise
/// for - it needs an administrator, not a retry.
class WorkspaceStateView extends StatelessWidget {
  final String? reason;
  final String emptyMessage;
  final VoidCallback? onRetry;

  const WorkspaceStateView({
    super.key,
    required this.reason,
    required this.emptyMessage,
    this.onRetry,
  });

  bool get _notLinked => reason == 'not-linked';

  bool get _offline =>
      reason != null && reason!.toLowerCase().contains('internet');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;

    final IconData icon;
    final String title;
    final String? detail;

    if (_notLinked) {
      icon = Icons.link_off;
      title = S.workspaceUnavailable;
      detail = S.workspaceNotLinked;
    } else if (_offline) {
      icon = Icons.wifi_off;
      title = S.errorNoInternet;
      detail = null;
    } else if (reason != null) {
      icon = Icons.error_outline;
      title = S.workspaceUnavailable;
      detail = reason;
    } else {
      icon = Icons.inbox_outlined;
      title = emptyMessage;
      detail = null;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            // A retry helps for a network blip; it cannot conjure an account.
            if (onRetry != null && !_notLinked) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(S.tryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
