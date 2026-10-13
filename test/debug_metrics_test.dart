import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/debug_dialog.dart';
import 'package:llmquota/debug_metrics.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/quota_account.dart';
import 'package:llmquota/models/usage.dart';
import 'package:llmquota/services/quota_controller.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13, 12);

  QuotaSnapshot snapshot({bool populated = true}) => QuotaSnapshot(
        provider: ProviderKind.codex,
        windows: [
          QuotaWindow(
            id: 'codex:primary',
            label: '5 hours',
            usedPercent: populated ? 12.345 : null,
            durationMinutes: populated ? 300 : null,
            resetsAt: populated ? now.add(const Duration(hours: 1)) : null,
          ),
        ],
        observedAt: now,
        source: 'test fixture',
        status: QuotaStatus.live,
        tokenUsage: populated
            ? const TokenUsage(
                today: TokenCount(
                  total: 123456789,
                  input: 100000000,
                  output: 23456789,
                  cachedInput: 98765432,
                  cachedCreationInput: 456789,
                ),
                session: TokenCount(total: 0),
                lifetime: TokenCount(total: 123456789),
              )
            : const TokenUsage(),
        creditBalance: populated
            ? const CreditBalance(balance: '12.50', hasCredits: true)
            : null,
        resetCredits: populated ? 2 : null,
      );

  Future<void> showMetrics(WidgetTester tester, QuotaSnapshot? value) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DebugMetrics(snapshot: value, now: now),
          ),
        ),
      ));

  List<String> lines(WidgetTester tester) => tester
      .widgetList<SelectableText>(find.descendant(
        of: find.byType(DebugMetrics),
        matching: find.byType(SelectableText),
      ))
      .expand((widget) => widget.data!.split('\n'))
      .toList();

  testWidgets('shows precise windows, token breakdowns, and credit fields',
      (tester) async {
    await showMetrics(tester, snapshot());
    for (final text in [
      'Used: 12.345%',
      'Remaining: 87.655%',
      'Duration: 300 minutes',
      'Today tokens',
      'Session tokens',
      'Lifetime tokens',
      'Input: 100000000',
      'Output: 23456789',
      'Cached input: 98765432',
      'Cache creation input: 456789',
      'Balance: 12.50',
      'Unlimited: false',
      'Has credits: true',
      'Reset credits: 2',
    ]) {
      expect(lines(tester), contains(text), reason: text);
    }
    expect(lines(tester).where((line) => line == 'Total: 123456789'),
        hasLength(2));
    expect(find.textContaining('2026-10-13T13:00:00.000Z'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('distinguishes unavailable values from real zero usage',
      (tester) async {
    await showMetrics(tester, snapshot(populated: false));
    for (final text in [
      'Used: Unavailable',
      'Remaining: Unavailable',
      'Duration: Unavailable',
      'Balance: Unavailable',
      'Unlimited: Unavailable',
      'Has credits: Unavailable',
      'Reset credits: Unavailable',
    ]) {
      expect(lines(tester), contains(text), reason: text);
    }
    expect(lines(tester).where((line) => line == 'Total: Unavailable'),
        hasLength(3));
    await showMetrics(tester, snapshot());
    expect(lines(tester), contains('Total: 0'));
    expect(lines(tester).where((line) => line == 'Input: Unavailable'),
        hasLength(2));
    expect(lines(tester), contains('Unlimited: false'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('metrics remain scrollable on a compact overlay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await showMetrics(tester, snapshot());
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
    expect(lines(tester), contains('Reset credits: 2'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling debug removes metric widgets from an open dialog',
      (tester) async {
    final controller = QuotaController(
      debugMode: true,
      accounts: const [
        QuotaAccount(
          id: 'codex',
          provider: ProviderKind.codex,
          label: 'Codex',
        ),
      ],
      accountFetcher: (_) async => snapshot(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DebugDialog(controller: controller)),
    ));
    expect(find.byType(DebugMetrics), findsOneWidget);
    controller.setDebugMode(false);
    await tester.pump();
    expect(find.byType(DebugMetrics), findsNothing);
    expect(find.text('Used: 12.345%'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
