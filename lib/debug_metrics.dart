import 'package:flutter/material.dart';

import 'models/quota.dart';
import 'models/usage.dart';

String _value(Object? value) => value?.toString() ?? 'Unavailable';
String _timestamp(DateTime? value) =>
    value?.toUtc().toIso8601String() ?? 'Unavailable';

List<String> _tokens(String heading, String? label, TokenCount? count) => [
  heading,
  'Label: ${_value(label)}',
  'Total: ${_value(count?.total)}',
  'Input: ${_value(count?.input)}',
  'Output: ${_value(count?.output)}',
  'Cached input: ${_value(count?.cachedInput)}',
  'Cache creation input: ${_value(count?.cachedCreationInput)}',
];

List<String> buildDebugMetricLines(QuotaSnapshot? snapshot, DateTime now) {
  final observation = snapshot;
  final age = observation == null
      ? null
      : now.toUtc().difference(observation.observedAt);
  final stale = observation == null
      ? null
      : observation.status == QuotaStatus.stale ||
            (observation.status == QuotaStatus.live && age!.inMinutes >= 10);
  final usage = observation?.tokenUsage;
  final credits = observation?.creditBalance;
  return <String>[
    'Observation metrics',
    'Observed at: ${_timestamp(observation?.observedAt)}',
    'Observation age: ${age == null ? 'Unavailable' : '${age.inMilliseconds} ms'}',
    'Stale: ${_value(stale)}',
    'Plan: ${_value(observation?.planName)}',
    'Has usage: ${_value(observation?.hasUsage)}',
    'Quota windows: ${_value(observation?.windows.length)}',
    'Token data available: ${_value(usage?.hasData)}',
    '',
    if (observation == null || observation.windows.isEmpty)
      'Quota window metrics: Unavailable',
    for (final (index, window)
        in (observation?.windows ?? <QuotaWindow>[]).indexed) ...[
      'Quota window ${index + 1}',
      'ID: ${window.id}',
      'Label: ${window.label}',
      'Used: ${window.usedPercent == null ? 'Unavailable' : '${window.usedPercent}%'}',
      'Remaining: ${window.remainingPercent == null ? 'Unavailable' : '${window.remainingPercent}%'}',
      'Duration: ${window.durationMinutes == null ? 'Unavailable' : '${window.durationMinutes} minutes'}',
      'Resets at: ${_timestamp(window.resetsAt)}',
      'Time until reset: ${window.resetsAt == null ? 'Unavailable' : '${window.resetsAt!.difference(now.toUtc()).inMilliseconds} ms'}',
      'Reset due: ${_value(window.resetsAt == null ? null : !window.resetsAt!.isAfter(now.toUtc()))}',
      '',
    ],
    ..._tokens('Today tokens', usage?.todayLabel, usage?.today),
    '',
    ..._tokens('Session tokens', usage?.sessionLabel, usage?.session),
    '',
    ..._tokens('Lifetime tokens', usage?.lifetimeLabel, usage?.lifetime),
    '',
    'Credits',
    'Credit data available: ${_value(observation == null ? null : credits != null)}',
    'Balance: ${_value(credits?.balance)}',
    'Unlimited: ${_value(credits?.unlimited)}',
    'Has credits: ${_value(credits?.hasCredits)}',
    'Reset credits: ${_value(observation?.resetCredits)}',
  ];
}

class DebugMetrics extends StatelessWidget {
  const DebugMetrics({super.key, required this.snapshot, required this.now});

  final QuotaSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final lines = buildDebugMetricLines(snapshot, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          if (line.isEmpty)
            const SizedBox(height: 12)
          else
            SelectableText(line),
      ],
    );
  }
}
