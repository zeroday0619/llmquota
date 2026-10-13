import 'dart:async';

import 'package:flutter/material.dart';

import 'services/quota_controller.dart';
import 'debug_metrics.dart';
import 'debug_report.dart';

class DebugDialog extends StatefulWidget {
  const DebugDialog({super.key, required this.controller});

  final QuotaController controller;

  @override
  State<DebugDialog> createState() => _DebugDialogState();
}

class _DebugDialogState extends State<DebugDialog> {
  Timer? _ticker;
  QuotaController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => AlertDialog(
          title: const Text('Debug diagnostics'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(controller.debugMode
                      ? 'Refresh diagnostics are kept in memory for this session. '
                          'Raw responses, account labels, connection paths, and '
                          'exception messages are excluded.'
                      : 'Debug mode is disabled. Diagnostics have been cleared.'),
                  const SizedBox(height: 12),
                  Text('Debug mode: ${controller.debugMode}'),
                  Text('Configured accounts: ${controller.accounts.length}'),
                  Text('Collected snapshots: ${controller.snapshots.length}'),
                  Text(
                      'Visible accounts: ${controller.visibleSnapshots.length}'),
                  Text(
                      'Recorded diagnostics: ${controller.diagnostics.length}'),
                  const Text('Auto-refresh interval: 60 seconds'),
                  Text('Data mode: ${controller.demo ? 'demo' : 'live'}'),
                  Text(
                      'Refresh: ${controller.refreshing ? 'in progress' : 'idle'}'),
                  for (final (index, account)
                      in controller.accounts.indexed) ...[
                    const Divider(),
                    Text('Account ${index + 1} · ${account.provider.name}'),
                    Text('Displayed status: '
                        '${controller.snapshots[account.id]?.status.name ?? 'pending'}'),
                    if (controller.diagnostics[account.id]
                        case final diagnostic?)
                      SelectableText(
                        'Last attempt: ${diagnostic.attemptedAt.toUtc().toIso8601String()}\n'
                        'Duration: ${diagnostic.elapsed.inMilliseconds} ms\n'
                        'Fetch status: ${diagnostic.status.name}\n'
                        'Previous data retained: ${diagnostic.retainedPrevious}\n'
                        'Error type: ${diagnostic.errorType ?? 'none'}',
                      )
                    else
                      const Text(
                          'No diagnostic recorded. Refresh to collect one.'),
                    if (controller.debugMode) ...[
                      const SizedBox(height: 12),
                      DebugMetrics(
                        snapshot: controller.snapshots[account.id],
                        now: DateTime.now(),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(buildIntegrationDiagnosticLines(
                        controller.integrationDiagnostics[account.id] ?? [],
                      ).join('\n')),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: controller.refreshing || !controller.debugMode
                  ? null
                  : controller.refresh,
              child: const Text('Refresh'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
}
