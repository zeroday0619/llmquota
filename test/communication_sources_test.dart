import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/models/communication_diagnostic.dart';
import 'package:llmquota/services/quota_sources.dart';

void main() {
  test('HTTP logs requests and failed and malformed responses without secrets',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      await request.drain<void>();
      requests++;
      request.response.statusCode = requests == 1 ? 404 : 200;
      request.response.write('private-response-not-json');
      await request.response.close();
    });
    final events = <CommunicationDiagnostic>[];
    await runZoned(
      () => QuotaSources(environment: {
        'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:${server.port}',
        'LLMQUETA_ANTIGRAVITY_CSRF_TOKEN': 'private-csrf',
      }).fetchAntigravity(),
      zoneValues: {communicationDiagnosticSinkKey: events.add},
    );
    expect(events.where((event) => event.direction == 'TX'), isNotEmpty);
    final responses = events.where((event) => event.direction == 'RX').toList();
    expect(responses.first.statusCode, 404);
    expect(responses.first.bytes, isNull);
    expect(responses.last.statusCode, 200);
    expect(responses.last.bytes, 'private-response-not-json'.length);
    final details = events.map((event) => event.detail).join();
    expect(details, isNot(contains('private-csrf')));
    expect(details, isNot(contains('private-response-not-json')));
    expect(details, isNot(contains('127.0.0.1')));
  });

  test('JSON-RPC logs correlated replies and notifications before parsing',
      () async {
    final temporary = await Directory.systemTemp.createTemp('quota-log-rpc-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/mock-codex');
    await executable.writeAsString(r'''#!/bin/sh
IFS= read -r initialization
printf '%s\n' '{"id":0,"result":{}}'
IFS= read -r initialized
IFS= read -r request
printf '%s\n' 'private-invalid-json'
printf '%s\n' '{"method":"account/rateLimits/updated","params":{"email":"private@example.com"}}'
printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000}}}}'
IFS= read -r usage
printf '%s\n' '{"id":2,"result":{"summary":{"lifetimeTokens":15000},"dailyUsageBuckets":[]}}'
while :; do :; done
''');
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final events = <CommunicationDiagnostic>[];
    await runZoned(
      () => QuotaSources(environment: {
        'LLMQUETA_CODEX_EXECUTABLE': executable.path,
      }).fetchCodex(),
      zoneValues: {communicationDiagnosticSinkKey: events.add},
    );
    expect(
      events
          .where((event) => event.direction == 'TX')
          .map((event) => event.operation),
      [
        'initialize',
        'initialized',
        'account/rateLimits/read',
        'account/usage/read'
      ],
    );
    final replies = events.where((event) => event.direction == 'RX').toList();
    expect(replies.map((event) => event.operation), [
      'initialize',
      'invalidMessage',
      'account/rateLimits/updated',
      'account/rateLimits/read',
      'account/usage/read',
    ]);
    expect(replies[1].bytes, utf8.encode('private-invalid-json').length);
    final details = events.map((event) => event.detail).join();
    expect(details, contains('usedPercent'));
    expect(details, isNot(contains('private@example.com')));
    expect(details, isNot(contains('private-invalid-json')));
  }, skip: Platform.isWindows);
}
