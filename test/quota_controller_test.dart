import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/quota_account.dart';
import 'package:llmquota/models/usage.dart';
import 'package:llmquota/services/quota_controller.dart';

QuotaSnapshot measurement(
  ProviderKind provider, {
  QuotaStatus status = QuotaStatus.live,
}) => QuotaSnapshot(
  provider: provider,
  windows: status == QuotaStatus.error
      ? []
      : [QuotaWindow(id: 'hour', label: 'Hour', usedPercent: 30)],
  observedAt: DateTime.utc(2026, 10, 8),
  source: 'Test',
  planName: status == QuotaStatus.error ? null : 'Plus',
  tokenUsage: status == QuotaStatus.error
      ? const TokenUsage()
      : const TokenUsage(lifetime: TokenCount(total: 1500)),
  creditBalance: status == QuotaStatus.error
      ? null
      : const CreditBalance(balance: '12.50'),
  resetCredits: status == QuotaStatus.error ? null : 2,
  status: status,
);

void main() {
  final work = QuotaAccount(
    id: 'work',
    provider: ProviderKind.codex,
    label: 'Work',
    configurationDirectory: '${Directory.systemTemp.path}/work',
  );
  final personal = QuotaAccount(
    id: 'personal',
    provider: ProviderKind.codex,
    label: 'Personal',
    configurationDirectory: '${Directory.systemTemp.path}/personal',
  );

  test(
    'debug diagnostics are opt-in, immutable, and cleared on disable',
    () async {
      final controller = QuotaController(
        accounts: [work],
        accountFetcher: (account) async => measurement(account.provider),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.diagnostics, isEmpty);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setDebugMode(true);
      expect(notifications, 1);
      final before = DateTime.now().toUtc();
      await controller.refresh();
      final diagnostic = controller.diagnostics['work']!;
      expect(diagnostic.attemptedAt.isBefore(before), isFalse);
      expect(diagnostic.elapsed, greaterThanOrEqualTo(Duration.zero));
      expect(diagnostic.status, QuotaStatus.live);
      expect(diagnostic.errorType, isNull);
      expect(diagnostic.retainedPrevious, isFalse);
      expect(() => controller.diagnostics.clear(), throwsUnsupportedError);
      controller.setDebugMode(false);
      expect(controller.diagnostics, isEmpty);
    },
  );

  test('debug errors retain raw status and only the exception type', () async {
    var failure = false;
    final controller = QuotaController(
      accounts: [work],
      debugMode: true,
      accountFetcher: (account) async {
        if (failure) throw StateError('credential=private-secret');
        return measurement(account.provider);
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    failure = true;
    await controller.refresh();
    final diagnostic = controller.diagnostics['work']!;
    expect(diagnostic.status, QuotaStatus.error);
    expect(diagnostic.errorType, 'StateError');
    expect(diagnostic.retainedPrevious, isTrue);
    expect(controller.snapshots['work']!.status, QuotaStatus.stale);
  });

  test('returned error status has no caught exception type', () async {
    final controller = QuotaController(
      accounts: [work],
      debugMode: true,
      accountFetcher: (account) async =>
          measurement(account.provider, status: QuotaStatus.error),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.diagnostics['work']!.status, QuotaStatus.error);
    expect(controller.diagnostics['work']!.errorType, isNull);
    expect(controller.diagnostics['work']!.retainedPrevious, isFalse);
  });

  test('pending refresh cannot capture after changing debug mode', () async {
    for (final initiallyEnabled in [false, true]) {
      final response = Completer<QuotaSnapshot>();
      final controller = QuotaController(
        accounts: [work],
        debugMode: initiallyEnabled,
        accountFetcher: (_) => response.future,
      );
      addTearDown(controller.dispose);
      final request = controller.refresh();
      if (initiallyEnabled) controller.setDebugMode(false);
      controller.setDebugMode(true);
      response.complete(measurement(work.provider));
      await request;
      expect(controller.diagnostics, isEmpty);
    }
  });

  test('account and demo generations discard old debug diagnostics', () async {
    final old = Completer<QuotaSnapshot>();
    final replacement = Completer<QuotaSnapshot>();
    final controller = QuotaController(
      accounts: [work],
      debugMode: true,
      accountFetcher: (account) =>
          account.id == work.id ? old.future : replacement.future,
    );
    addTearDown(controller.dispose);
    final request = controller.refresh();
    await controller.setAccounts([personal]);
    old.complete(measurement(work.provider));
    await request;
    expect(controller.diagnostics, isEmpty);
    replacement.complete(measurement(personal.provider));
    await Future<void>.delayed(Duration.zero);
    expect(controller.diagnostics.keys, ['personal']);
    controller.setDemo(true);
    expect(controller.diagnostics.containsKey('work'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(controller.diagnostics['personal']!.status, QuotaStatus.demo);
  });

  test(
    'same-provider accounts refresh concurrently and isolate failures',
    () async {
      var failure = false;
      final controller = QuotaController(
        accounts: [work, personal],
        accountFetcher: (account) async {
          if (failure && account.id == 'work') throw StateError('Unavailable');
          return measurement(account.provider);
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      failure = true;
      await controller.refresh();
      expect(controller.snapshots['work']!.status, QuotaStatus.stale);
      expect(controller.snapshots['personal']!.status, QuotaStatus.live);
      expect(
        controller.visibleSnapshots.map((snapshot) => snapshot.accountLabel),
        ['Work', 'Personal'],
      );
    },
  );

  test(
    'account edits discard old in-flight responses and deleted accounts',
    () async {
      final old = Completer<QuotaSnapshot>();
      final updated = Completer<QuotaSnapshot>();
      final controller = QuotaController(
        accounts: [work, personal],
        accountFetcher: (account) =>
            account.configurationDirectory == '${Directory.systemTemp.path}/new'
            ? updated.future
            : old.future,
      );
      addTearDown(controller.dispose);
      final request = controller.refresh();
      await controller.setAccounts([
        QuotaAccount(
          id: 'work',
          provider: ProviderKind.codex,
          label: 'New work',
          configurationDirectory: '${Directory.systemTemp.path}/new',
        ),
      ]);
      old.complete(measurement(ProviderKind.codex));
      await request;
      expect(controller.snapshots, isEmpty);
      updated.complete(measurement(ProviderKind.codex));
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshots.keys, ['work']);
      expect(controller.snapshots['work']!.accountLabel, 'New work');
    },
  );

  test('persistence failure preserves accounts and observations', () async {
    final controller = QuotaController(
      accounts: [work],
      accountFetcher: (account) async => measurement(account.provider),
      saveAccounts: (_) async => throw StateError('Read-only store'),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await expectLater(controller.setAccounts([personal]), throwsStateError);
    expect(controller.accounts.single.id, 'work');
    expect(controller.snapshots.keys, ['work']);
  });

  test(
    'renaming preserves stale data but changed connections do not',
    () async {
      var failure = false;
      final controller = QuotaController(
        accounts: [work],
        accountFetcher: (account) async {
          if (failure) throw StateError('Unavailable');
          return measurement(account.provider);
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      failure = true;
      await controller.setAccounts([
        QuotaAccount(
          id: 'work',
          provider: ProviderKind.codex,
          label: 'Renamed',
          configurationDirectory: '${Directory.systemTemp.path}/work',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshots['work']!.status, QuotaStatus.stale);
      expect(controller.snapshots['work']!.accountLabel, 'Renamed');
      await controller.setAccounts([
        QuotaAccount(
          id: 'work',
          provider: ProviderKind.codex,
          label: 'Other',
          configurationDirectory: '${Directory.systemTemp.path}/other',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshots['work']!.status, QuotaStatus.error);
      expect(controller.snapshots['work']!.hasUsage, isFalse);
    },
  );

  test(
    'a refresh failure retains the last observation and marks it stale',
    () async {
      var failure = false;
      final controller = QuotaController(
        fetcher: (provider) async => measurement(
          provider,
          status: failure ? QuotaStatus.error : QuotaStatus.live,
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.snapshots['codex']!.planName, 'Plus');
      failure = true;
      await controller.refresh();
      expect(controller.snapshots['codex']!.planName, 'Plus');
      expect(controller.snapshots['codex']!.tokenUsage.lifetime!.total, 1500);
      expect(controller.snapshots['codex']!.creditBalance!.balance, '12.50');
      expect(controller.snapshots['codex']!.resetCredits, 2);
      expect(controller.snapshots['codex']!.status, QuotaStatus.stale);
      expect(controller.snapshots['codex']!.windows.single.usedPercent, 30);
      expect(
        controller.snapshots['codex']!.observedAt,
        DateTime.utc(2026, 10, 8),
      );
    },
  );

  test('switching to demo discards in-flight real responses', () async {
    final completers = {
      for (final provider in ProviderKind.values)
        provider: Completer<QuotaSnapshot>(),
    };
    final controller = QuotaController(
      fetcher: (provider) => completers[provider]!.future,
    );
    addTearDown(controller.dispose);
    final request = controller.refresh();
    controller.setDemo(true);
    for (final provider in ProviderKind.values) {
      completers[provider]!.complete(measurement(provider));
    }
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == QuotaStatus.demo,
      ),
      isTrue,
    );
  });
}
