import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/quota_account.dart';
import 'package:llmquota/services/quota_sources.dart';

void main() {
  late Directory directory;
  late File bridge;
  late Map<String, String> environment;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'claude-desktop-sources-',
    );
    bridge = File('${directory.path}/bridge.json');
    environment = {
      'HOME': directory.path,
      'USERPROFILE': directory.path,
      'PATH': directory.path,
      'CLAUDE_CONFIG_DIR': directory.path,
    };
    await bridge.writeAsString(
      jsonEncode({
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'five_hour': {'utilization': 31},
      }),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  QuotaSnapshot desktop({
    QuotaStatus status = QuotaStatus.live,
    bool windows = true,
  }) => QuotaSnapshot(
    provider: ProviderKind.claude,
    windows: windows
        ? [QuotaWindow(id: 'five_hour', label: '5 hours', usedPercent: 12)]
        : [],
    observedAt: DateTime.now(),
    source: 'Claude Desktop',
    status: status,
  );
  QuotaSources sources(Future<QuotaSnapshot?> Function() fetcher) =>
      QuotaSources(
        environment: environment,
        claudeSnapshotPath: bridge.path,
        claudeDesktopFetcher: fetcher,
      );

  test(
    'desktop observations take priority without merging Claude Code history',
    () async {
      final history = File('${directory.path}/projects/example/session.jsonl');
      await history.parent.create(recursive: true);
      await history.writeAsString(
        jsonEncode({
          'type': 'assistant',
          'sessionId': 'session',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'message': {
            'id': 'fixture',
            'usage': {'input_tokens': 20, 'output_tokens': 10},
          },
        }),
      );
      final expected = desktop();
      final actual = await sources(() async => expected).fetchClaude();
      expect(actual, same(expected));
      expect(actual.source, 'Claude Desktop');
      expect(actual.tokenUsage.hasData, false);
      expect(actual.windows.first.usedPercent, 12);
    },
  );

  test('stale desktop observation remains preferred', () async {
    final expected = desktop(status: QuotaStatus.stale);
    expect(await sources(() async => expected).fetchClaude(), same(expected));
  });

  for (final state in ['missing', 'unavailable', 'error']) {
    test('falls back to Claude Code bridge when desktop is $state', () async {
      final source = sources(() async {
        if (state == 'error') throw StateError('Fixture failure');
        return state == 'missing'
            ? null
            : desktop(status: QuotaStatus.unavailable, windows: false);
      });
      final actual = await source.fetchClaude();
      expect(actual.source, 'Claude Code status line');
      expect(actual.windows.first.usedPercent, 31);
      expect(actual.status, QuotaStatus.live);
    });
  }

  test('scoped account never reads global desktop session', () async {
    var desktopCalls = 0;
    final source = sources(() async {
      desktopCalls++;
      return desktop();
    });
    final account = QuotaAccount(
      id: 'claude-fixture',
      provider: ProviderKind.claude,
      label: 'Fixture',
      configurationDirectory: directory.path,
      snapshotPath: bridge.path,
    );
    final actual = await source.fetchAccount(account);
    expect(desktopCalls, 0);
    expect(actual.source, 'Claude Code status line');
    expect(actual.accountId, account.id);
    expect(actual.windows.first.usedPercent, 31);
  });

  test(
    'desktop failure without bridge reports actionable unavailable state',
    () async {
      await bridge.delete();
      final actual = await sources(
        () async => throw StateError('Fixture failure'),
      ).fetchClaude();
      expect(actual.status, QuotaStatus.error);
      expect(actual.windows, isEmpty);
      expect(actual.message, contains('Settings > Connect providers'));
    },
  );
}
