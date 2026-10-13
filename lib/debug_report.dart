import 'debug_metrics.dart';
import 'models/integration_diagnostic.dart';
import 'services/quota_controller.dart';

List<String> buildDebugReport(QuotaController controller, DateTime now) => [
  'Debug diagnostics',
  controller.debugMode
      ? 'Refresh diagnostics are kept in memory for this session. '
            'Raw responses, account labels, connection paths, and '
            'exception messages are excluded.'
      : 'Debug mode is disabled. Diagnostics have been cleared.',
  'Debug mode: ${controller.debugMode}',
  'Configured accounts: ${controller.accounts.length}',
  'Collected snapshots: ${controller.snapshots.length}',
  'Visible accounts: ${controller.visibleSnapshots.length}',
  'Recorded diagnostics: ${controller.diagnostics.length}',
  'Buffered log entries: ${controller.debugLogs.length} / 1000',
  'Evicted log entries: ${controller.droppedDebugLogCount}',
  'Recorded integration events: ${controller.integrationDiagnostics.values.fold<int>(0, (count, events) => count + events.length)}',
  'Auto-refresh interval: 60 seconds',
  'Data mode: ${controller.demo ? 'demo' : 'live'}',
  'Refresh: ${controller.refreshing ? 'in progress' : 'idle'}',
  for (final (index, account) in controller.accounts.indexed) ...[
    '',
    'Account ${index + 1} · ${account.provider.name}',
    'Displayed status: '
        '${controller.snapshots[account.id]?.status.name ?? 'pending'}',
    if (controller.diagnostics[account.id] case final diagnostic?) ...[
      'Last attempt: ${diagnostic.attemptedAt.toUtc().toIso8601String()}',
      'Duration: ${diagnostic.elapsed.inMilliseconds} ms',
      'Fetch status: ${diagnostic.status.name}',
      'Previous data retained: ${diagnostic.retainedPrevious}',
      'Error type: ${diagnostic.errorType ?? 'none'}',
    ] else
      'No diagnostic recorded. Refresh to collect one.',
    if (controller.debugMode) ...[
      '',
      ...buildDebugMetricLines(controller.snapshots[account.id], now),
      '',
      ...buildIntegrationDiagnosticLines(
        controller.integrationDiagnostics[account.id] ?? [],
      ),
    ],
  ],
];

List<String> buildIntegrationDiagnosticLines(
  List<IntegrationDiagnostic> events,
) => [
  'Integration diagnostics',
  if (events.isEmpty)
    'No integration diagnostic recorded. Refresh to collect one.',
  for (final event in events) ...[
    '${event.attemptedAt.toUtc().toIso8601String()} · ${event.stage} · ${event.outcome}',
    'Duration: ${event.elapsed.inMilliseconds} ms',
    'Error type: ${event.errorType ?? 'none'}',
    for (final metric in event.metrics.entries)
      '${metric.key}: ${metric.value}',
  ],
];

List<String> buildDebugLogLines(QuotaController controller) => [
  for (final entry in controller.debugLogs) entry.formatted,
];
