import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/models/communication_diagnostic.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/quota_account.dart';
import 'package:llmquota/services/quota_controller.dart';

void main() {
  QuotaController makeController({int events = 1}) => QuotaController(
    debugMode: true,
    accountFetcher: (account) async {
      for (var index = 0; index < events; index++) {
        recordCommunication(
          'jsonrpc',
          'send',
          'request',
          payload: {'id': index},
        );
      }
      return QuotaSnapshot(
        provider: account.provider,
        windows: [],
        observedAt: DateTime.now(),
        source: 'Provider',
        status: QuotaStatus.unavailable,
      );
    },
  );
  test('logs combine lifecycle and communication in monotonic order', () async {
    final controller = makeController();
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.debugLogs.first.message, contains('refresh start'));
    expect(
      controller.debugLogs.any(
        (entry) => entry.message.contains('jsonrpc send'),
      ),
      isTrue,
    );
    expect(controller.debugLogs.last.message, contains('refresh end'));
    for (var index = 1; index < controller.debugLogs.length; index++) {
      expect(
        controller.debugLogs[index].elapsed >=
            controller.debugLogs[index - 1].elapsed,
        isTrue,
      );
    }
    expect(
      controller.debugLogs.first.formatted,
      matches(r'^\[\s*\d+\.\d{6}\] codex/account-1 '),
    );
    expect(() => controller.debugLogs.clear(), throwsUnsupportedError);
  });
  test('buffer cap counts evictions and clear resets counter', () async {
    final controller = makeController(events: 1100);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.debugLogs.length, 1000);
    expect(controller.droppedDebugLogCount, greaterThan(0));
    controller.clearDebugLogs();
    expect(controller.debugLogs, isEmpty);
    expect(controller.droppedDebugLogCount, 0);
    await controller.refresh();
    controller.setDebugMode(false);
    expect(controller.debugLogs, isEmpty);
  });
  test(
    'old communication callbacks cannot enter a new debug session',
    () async {
      final release = Completer<void>();
      final controller = QuotaController(
        debugMode: true,
        accounts: [QuotaAccount.defaults.first],
        accountFetcher: (account) async {
          recordCommunication(
            'JSON-RPC',
            'TX',
            'initialize',
            payload: {'id': 0},
          );
          await release.future;
          recordCommunication(
            'JSON-RPC',
            'RX',
            'initialize',
            payload: {'id': 0, 'result': {}},
          );
          return QuotaSnapshot(
            provider: account.provider,
            windows: [],
            observedAt: DateTime.now(),
            source: 'Fixture',
            status: QuotaStatus.unavailable,
          );
        },
      );
      addTearDown(controller.dispose);
      final request = controller.refresh();
      expect(controller.debugLogs, isNotEmpty);
      controller.setDebugMode(false);
      controller.setDebugMode(true);
      release.complete();
      await request;
      expect(controller.debugLogs, isEmpty);
      await controller.refresh();
      expect(
        controller.debugLogs.where(
          (entry) => entry.message.contains('JSON-RPC'),
        ),
        hasLength(2),
      );
      final observation = controller.snapshots.values.single;
      controller.clearDebugLogs();
      expect(controller.snapshots.values.single, same(observation));
      expect(controller.debugLogs, isEmpty);
    },
  );
}
