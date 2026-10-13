import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/debug_report.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/quota_controller.dart';
import 'package:llmqueta/services/quota_sources.dart';

void main() {
  test('Antigravity traces failed HTTP status and successful fallback metrics',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const privateToken = 'private-integration-token';
    final payload = jsonEncode({
      'userStatus': {
        'cascadeModelConfigData': {
          'clientModelConfigs': [
            {
              'label': 'Gemini',
              'modelOrAlias': {'model': 'gemini-test'},
              'quotaInfo': {
                'remainingFraction': 0.7,
                'resetTime': '2030-01-01T00:00:00Z',
              },
            },
          ],
        },
      },
    });
    server.listen((request) async {
      expect(request.headers.value('X-Codeium-Csrf-Token'), privateToken);
      await request.drain<void>();
      if (request.uri.path.endsWith('/RetrieveUserQuotaSummary')) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(payload);
      }
      await request.response.close();
    });
    final sources = QuotaSources(environment: {
      'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:${server.port}',
      'LLMQUETA_ANTIGRAVITY_CSRF_TOKEN': privateToken,
    });
    final controller = QuotaController(
      debugMode: true,
      accounts: const [
        QuotaAccount(
            id: 'antigravity',
            provider: ProviderKind.antigravity,
            label: 'Private account'),
      ],
      accountFetcher: sources.fetchAccount,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.snapshots['antigravity']!.status, QuotaStatus.live);
    final events = controller.integrationDiagnostics['antigravity']!;
    final rejected = events.singleWhere((event) =>
        event.stage == 'antigravity.http.RetrieveUserQuotaSummary.response' &&
        event.outcome != 'running');
    expect(rejected.outcome, 'unavailable');
    expect(rejected.metrics['statusCode'], HttpStatus.notFound);
    final failure = events.singleWhere((event) =>
        event.stage == 'antigravity.http.RetrieveUserQuotaSummary' &&
        event.outcome == 'error');
    expect(failure.errorType, 'HttpException');
    final success = events.singleWhere((event) =>
        event.stage == 'antigravity.http.GetUserStatus' &&
        event.outcome == 'success');
    expect(success.metrics['statusCode'], HttpStatus.ok);
    expect(success.metrics['bytes'], utf8.encode(payload).length);
    for (final event in events) {
      final trace =
          '${event.stage} ${event.outcome} ${event.errorType} ${event.metrics}';
      expect(trace, isNot(contains(privateToken)));
      expect(trace, isNot(contains('Private account')));
      expect(trace, isNot(contains('127.0.0.1')));
      expect(trace, isNot(contains('gemini-test')));
    }
  });

  test('Codex traces RPC error codes and preserves usage without raw details',
      () async {
    final temporary = await Directory.systemTemp.createTemp('llmqueta-trace-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/mock-codex');
    await executable.writeAsString(r'''#!/bin/sh
IFS= read -r initialization
printf '%s\n' '{"id":0,"result":{}}'
IFS= read -r initialized
IFS= read -r quota
printf '%s\n' '{"id":1,"error":{"code":-32001,"message":"private-rpc-token"}}'
IFS= read -r usage
printf '%s\n' '{"id":2,"result":{"summary":{"lifetimeTokens":15000},"dailyUsageBuckets":[]}}'
while :; do :; done
''');
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final sources = QuotaSources(environment: {
      'LLMQUETA_CODEX_EXECUTABLE': executable.path,
    });
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: sources.fetchAccount,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final snapshot = controller.snapshots['codex']!;
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.tokenUsage.lifetime?.total, 15000);
    final events = controller.integrationDiagnostics['codex']!;
    final rejected = events.singleWhere((event) =>
        event.stage == 'codex.rpc.account/rateLimits/read' &&
        event.outcome != 'running');
    expect(rejected.outcome, 'unavailable');
    expect(rejected.metrics['rpcErrorCode'], -32001);
    expect(
        events.any((event) =>
            event.stage == 'codex.tokens.parse' && event.outcome == 'success'),
        isTrue);
    final report = buildDebugReport(controller, DateTime.now()).join('\n');
    expect(report, contains('rpcErrorCode: -32001'));
    for (final privateValue in ['private-rpc-token', executable.path]) {
      expect(report, isNot(contains(privateValue)));
      for (final event in events) {
        expect('${event.stage} ${event.errorType} ${event.metrics}',
            isNot(contains(privateValue)));
      }
    }
  }, skip: Platform.isWindows);
}
