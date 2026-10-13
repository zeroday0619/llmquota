import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/integration_diagnostic.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/quota_controller.dart';

QuotaSnapshot snapshot(QuotaAccount account) => QuotaSnapshot(
      provider: account.provider,
      windows: const [],
      observedAt: DateTime.utc(2026, 10, 13),
      source: 'Fixture',
      status: QuotaStatus.unavailable,
    );

void main() {
  test('integration stages publish running and final metrics live', () async {
    final response = Completer<int>();
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        await integrationStep<int>('fixture.request', () => response.future,
            metrics: (value) => {'responseBytes': value});
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    final running = controller.integrationDiagnostics.values.single.single;
    expect(running.stage, 'fixture.request');
    expect(running.outcome, 'running');
    response.complete(42);
    await refresh;
    final completed = controller.integrationDiagnostics.values.single.last;
    expect(completed.outcome, 'success');
    expect(completed.metrics['responseBytes'], 42);
    expect(completed.elapsed.inMicroseconds, greaterThanOrEqualTo(0));
    expect(completed.attemptedAt.isUtc, isTrue);
    expect(() => controller.integrationDiagnostics.clear(),
        throwsUnsupportedError);
    expect(() => controller.integrationDiagnostics.values.single.clear(),
        throwsUnsupportedError);
    expect(() => completed.metrics.clear(), throwsUnsupportedError);
  });

  test('integration errors expose type without private exception contents',
      () async {
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        await integrationStep<void>('fixture.request', () async {
          throw StateError('secret-token private@example.com /private/path');
        });
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final error = controller.integrationDiagnostics.values.single.last;
    expect(error.outcome, 'error');
    expect(error.errorType, 'StateError');
    expect(error.metrics, isEmpty);
    expect(controller.snapshots.values.single.status, QuotaStatus.error);
  });

  test(
      'integration diagnostics isolate concurrent accounts and unavailable stages',
      () async {
    final accounts = [
      QuotaAccount(
          id: 'first',
          provider: ProviderKind.codex,
          label: 'First',
          configurationDirectory:
              '${Directory.systemTemp.path}${Platform.pathSeparator}first'),
      QuotaAccount(
          id: 'second',
          provider: ProviderKind.claude,
          label: 'Second',
          configurationDirectory:
              '${Directory.systemTemp.path}${Platform.pathSeparator}second',
          snapshotPath:
              '${Directory.systemTemp.path}${Platform.pathSeparator}second${Platform.pathSeparator}quota.json'),
    ];
    final controller = QuotaController(
      debugMode: true,
      accounts: accounts,
      accountFetcher: (account) async {
        await integrationStep<bool>('fixture.${account.id}', () async => false,
            available: (value) => value);
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    for (final account in accounts) {
      final events = controller.integrationDiagnostics[account.id]!;
      expect(events.every((event) => event.stage == 'fixture.${account.id}'),
          isTrue);
      expect(events.last.outcome, 'unavailable');
    }
  });

  test('disabled debug mode records no integration diagnostics', () async {
    var performed = false;
    final controller = QuotaController(
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        await integrationStep<void>('fixture.request', () async {
          performed = true;
        });
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(performed, isTrue);
    expect(controller.integrationDiagnostics, isEmpty);
  });

  test('disable and re-enable discards previous in-flight integration response',
      () async {
    final response = Completer<void>();
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        await integrationStep<void>('fixture.request', () => response.future);
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.integrationDiagnostics, isNotEmpty);
    controller.setDebugMode(false);
    controller.setDebugMode(true);
    response.complete();
    await refresh;
    expect(controller.integrationDiagnostics, isEmpty);
  });

  test('demo and account changes clear integration history', () async {
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        await integrationStep<void>('fixture.request', () async {});
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.integrationDiagnostics, isNotEmpty);
    controller.setDemo(true);
    await controller.refresh();
    expect(controller.integrationDiagnostics, isEmpty);
    controller.setDemo(false);
    while (controller.refreshing) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.integrationDiagnostics, isNotEmpty);
    await controller.setAccounts([]);
    expect(controller.integrationDiagnostics, isEmpty);
  });

  test('integration history stays bounded per account', () async {
    final controller = QuotaController(
      debugMode: true,
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async {
        for (var index = 0; index < 250; index++) {
          await integrationStep<void>('fixture.$index', () async {});
        }
        return snapshot(account);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final events = controller.integrationDiagnostics.values.single;
    expect(events.length, lessThanOrEqualTo(200));
    expect(events.last.stage, 'fixture.249');
    expect(events.last.outcome, 'success');
  });
}
