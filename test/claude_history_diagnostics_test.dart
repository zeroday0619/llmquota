import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/debug_report.dart';
import 'package:llmquota/models/integration_diagnostic.dart';
import 'package:llmquota/services/claude_usage.dart';

void main() {
  late Directory directory;
  late List<IntegrationDiagnostic> events;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('private-history-');
    events = [];
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> capture(Map<String, String> environment) async {
    await runZoned(
      () => readClaudeTokenUsage(environment: environment),
      zoneValues: {
        integrationDiagnosticSinkKey: (IntegrationDiagnostic event) =>
            events.add(event),
      },
    );
  }

  test('reports unavailable history without private configuration paths',
      () async {
    await capture({'CLAUDE_CONFIG_DIR': directory.path});
    expect(events.single.stage, 'claude.history.noHistory');
    expect(events.single.outcome, 'unavailable');
    expect(buildIntegrationDiagnosticLines(events).join('\n'),
        isNot(contains(directory.path)));
    events.clear();
    await capture({});
    expect(events.single.stage, 'claude.history.noHistory');
  });

  test('reports malformed transcript error type and scan counters', () async {
    final projects = await Directory('${directory.path}/projects').create();
    final transcript = File('${projects.path}/secret-transcript.jsonl');
    await transcript.writeAsString('{private malformed text');
    await capture({'CLAUDE_CONFIG_DIR': directory.path});
    final event = events.single;
    expect(event.stage, 'claude.history.scan.error');
    expect(event.outcome, 'error');
    expect(event.errorType, 'FormatException');
    expect(event.metrics['files'], 1);
    expect(event.metrics['bytes'], await transcript.length());
    expect(event.metrics['records'], 0);
    final report = buildIntegrationDiagnosticLines(events).join('\n');
    expect(report, isNot(contains(directory.path)));
    expect(report, isNot(contains('private malformed text')));
    expect(report, isNot(contains('secret-transcript')));
  });

  test('reports successful scan counters while preserving token totals',
      () async {
    final projects = await Directory('${directory.path}/projects').create();
    final transcript = File('${projects.path}/transcript.jsonl');
    await transcript.writeAsString(jsonEncode({
      'type': 'assistant',
      'timestamp': '2026-10-13T00:00:00Z',
      'message': {
        'id': 'private-message-id',
        'usage': {'input_tokens': 12, 'output_tokens': 3},
      },
    }));
    final usage = await runZoned(
      () => readClaudeTokenUsage(
          environment: {'CLAUDE_CONFIG_DIR': directory.path}),
      zoneValues: {
        integrationDiagnosticSinkKey: (IntegrationDiagnostic event) =>
            events.add(event),
      },
    );
    expect(usage.lifetime?.total, 15);
    final event = events.single;
    expect(event.stage, 'claude.history.scan.success');
    expect(event.outcome, 'success');
    expect(event.attemptedAt.isUtc, isTrue);
    expect(event.metrics,
        {'bytes': await transcript.length(), 'files': 1, 'records': 1});
    expect(buildIntegrationDiagnosticLines(events).join('\n'),
        isNot(contains('private-message-id')));
  });

  test('reports empty retained history', () async {
    await Directory('${directory.path}/projects').create();
    await capture({'CLAUDE_CONFIG_DIR': directory.path});
    expect(events.single.stage, 'claude.history.scan.empty');
    expect(events.single.metrics, {'bytes': 0, 'files': 0, 'records': 0});
  });
}
