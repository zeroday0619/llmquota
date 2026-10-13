import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';

import 'app_theme.dart';

import 'models/quota.dart';
import 'usage_summary.dart';
import 'services/quota_controller.dart';
import 'fluent_controls.dart';

class HudOverlay extends StatelessWidget {
  const HudOverlay({
    super.key,
    required this.controller,
    required this.resetLabel,
    required this.onDrag,
    required this.onClose,
    required this.onExit,
  });

  final QuotaController controller;
  final String Function(DateTime?, DateTime) resetLabel;
  final Future<void> Function() onDrag;
  final Future<void> Function() onClose;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => FluentContainer(
      color: Theme.of(context).colorScheme.surface,
      cornerRadius: FluentCornerRadius.large,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => unawaited(onDrag()),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: controller.demo
                                    ? warningColor(context)
                                    : providerAccent(
                                        context,
                                        ProviderKind.codex.index,
                                      ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                controller.demo
                                    ? 'Quota · Demo'
                                    : 'Quota · HUD',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  FluentActionButton(
                    tooltip: 'Return to window (Esc)',
                    onPressed: onExit,
                    icon: const Icon(
                      FluentIcons.arrow_expand_20_regular,
                      size: 20,
                    ),
                  ),
                  FluentActionButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(FluentIcons.dismiss_20_regular, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: controller.visibleSnapshots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        controller.refreshing
                            ? 'Checking connections…'
                            : 'No connected platforms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    children: [
                      for (final snapshot in controller.visibleSnapshots)
                        _HudAccount(snapshot: snapshot, resetLabel: resetLabel),
                    ],
                  ),
          ),
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.refreshing
                          ? 'Updating…'
                          : 'Refreshes every 60s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FluentActionButton(
                    tooltip: 'Refresh now',
                    icon: const Icon(
                      FluentIcons.arrow_sync_20_regular,
                      size: 20,
                    ),
                    onPressed: controller.refreshing
                        ? null
                        : controller.refresh,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HudAccount extends StatelessWidget {
  const _HudAccount({required this.snapshot, required this.resetLabel});
  final QuotaSnapshot snapshot;
  final String Function(DateTime?, DateTime) resetLabel;

  @override
  Widget build(BuildContext context) {
    final color = providerAccent(context, snapshot.provider.index);
    final stale =
        snapshot.status == QuotaStatus.stale ||
        (snapshot.status == QuotaStatus.live &&
            DateTime.now().difference(snapshot.observedAt).inMinutes >= 10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          [
                            'Codex',
                            'Claude',
                            'Antigravity',
                          ][snapshot.provider.index],
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (snapshot.planName != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Tooltip(
                            message: snapshot.planName!,
                            child: Text(
                              snapshot.planName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (stale)
                  Text(
                    'Stale',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: warningColor(context),
                    ),
                  ),
              ],
            ),
          ),
          if (snapshot.accountLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Tooltip(
                message: snapshot.accountLabel!,
                child: Text(
                  snapshot.accountLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (final window in snapshot.windows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          window.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          window.remainingPercent == null
                              ? 'Unknown'
                              : '${window.remainingPercent!.round()}% left',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (window.remainingPercent != null)
                    LinearProgressIndicator(
                      value: window.remainingPercent! / 100,
                      minHeight: 2,
                      color: color,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      semanticsLabel:
                          '${window.label}: ${window.remainingPercent!.round()} percent remaining',
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message:
                          window.resetsAt?.toLocal().toString() ??
                          'Reset time unavailable',
                      child: Text(
                        resetLabel(window.resetsAt, DateTime.now()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          UsageSummary(snapshot: snapshot, hud: true),
        ],
      ),
    );
  }
}
