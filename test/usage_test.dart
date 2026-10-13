import 'package:flutter/material.dart';
import 'package:llmquota/usage_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/usage.dart';

void main() {
  final now = DateTime(2026, 10, 8, 14);

  QuotaSnapshot snapshot({
    TokenUsage usage = const TokenUsage(),
    CreditBalance? credits,
    int? resetCredits,
  }) => QuotaSnapshot(
    provider: ProviderKind.codex,
    windows: [],
    observedAt: now,
    source: 'Fixture',
    status: QuotaStatus.live,
    tokenUsage: usage,
    creditBalance: credits,
    resetCredits: resetCredits,
  );

  for (final hud in [false, true]) {
    testWidgets('unknown usage rows leave no empty space with hud=$hud', (
      tester,
    ) async {
      final observation = snapshot(credits: const CreditBalance());
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(AppThemeMode.dark),
          home: Scaffold(
            body: UsageSummary(snapshot: observation, hud: hud),
          ),
        ),
      );
      expect(find.textContaining('tokens'), findsNothing);
      expect(find.text('Credits'), findsNothing);
      expect(find.textContaining('unavailable'), findsNothing);
      expect(UsageSummary.estimatedHeight(observation, hud: hud), 0);
      expect(tester.getSize(find.byType(UsageSummary)).height, 0);
    });

    testWidgets('zero usage and reset credits remain visible with hud=$hud', (
      tester,
    ) async {
      final observation = snapshot(
        usage: const TokenUsage(
          today: TokenCount(total: 0),
          lifetime: TokenCount(total: 1200),
        ),
        credits: const CreditBalance(balance: '0'),
        resetCredits: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(AppThemeMode.dark),
          home: Scaffold(
            body: UsageSummary(snapshot: observation, hud: hud),
          ),
        ),
      );
      expect(find.text('Today tokens'), findsOneWidget);
      expect(find.text('Session tokens'), findsNothing);
      expect(find.text('Lifetime tokens'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('1.2K'), findsOneWidget);
      expect(find.text('0 credits'), findsOneWidget);
      expect(find.text('Reset credits'), findsOneWidget);
      expect(
        UsageSummary.estimatedHeight(observation, hud: hud),
        8 + 4 * (hud ? 20 : 24),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit credit availability remains visible with hud=$hud', (
      tester,
    ) async {
      for (final available in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(AppThemeMode.dark),
            home: Scaffold(
              body: UsageSummary(
                snapshot: snapshot(
                  credits: CreditBalance(hasCredits: available),
                ),
                hud: hud,
              ),
            ),
          ),
        );
        expect(find.text('Credits'), findsOneWidget);
        expect(
          find.text(available ? 'Available' : 'No credits'),
          findsOneWidget,
        );
        expect(find.text('Balance unavailable'), findsNothing);
        expect(
          UsageSummary.estimatedHeight(
            snapshot(credits: CreditBalance(hasCredits: available)),
            hud: hud,
          ),
          8 + (hud ? 20 : 24),
        );
      }
    });
  }

  test('account usage reads today and lifetime independently', () {
    final usage = parseCodexTokenUsage({
      'result': {
        'summary': {'lifetimeTokens': 16808063757},
        'dailyUsageBuckets': [
          {'startDate': '2026-10-07', 'tokens': 200},
          {'startDate': '2026-10-08', 'tokens': 0},
        ],
      },
    }, now: now);
    expect(usage.today!.total, 0);
    expect(usage.lifetime!.total, 16808063757);
    expect(usage.session, isNull);
    expect(usage.note, contains('2026-10-08'));
  });

  test('missing or ambiguous daily bucket never becomes zero', () {
    for (final buckets in [
      null,
      [],
      [
        {'startDate': '2026-10-07', 'tokens': 400},
      ],
      [
        {'startDate': '2026-10-08', 'tokens': 100},
        {'startDate': '2026-10-08', 'tokens': 200},
      ],
    ]) {
      final usage = parseCodexTokenUsage({
        'summary': {'lifetimeTokens': 500},
        'dailyUsageBuckets': buckets,
      }, now: now);
      expect(usage.today, isNull);
      expect(usage.lifetime!.total, 500);
    }
  });

  test('invalid counts remain unknown instead of losing valid siblings', () {
    for (final invalid in [-1, 1.5, '25', true, double.infinity, null]) {
      final usage = parseCodexTokenUsage({
        'summary': {'lifetimeTokens': invalid},
        'dailyUsageBuckets': [
          {'startDate': '2026-10-08', 'tokens': 30},
        ],
      }, now: now);
      expect(usage.today!.total, 30);
      expect(usage.lifetime, isNull);
    }
  });

  test('thread groups sum explicit totals without double-counting cache', () {
    final usage = parseCodexTokenUsage(
      {
        'summary': {'lifetimeTokens': 10000},
      },
      now: now,
      sessionPayload: {
        'threadUsage': {
          'groups': [
            {
              'totalTokens': 120,
              'inputTokens': 100,
              'outputTokens': 20,
              'cachedInputTokens': 80,
            },
            {
              'totalTokens': 60,
              'inputTokens': 50,
              'outputTokens': 10,
              'cachedInputTokens': 40,
            },
          ],
        },
      },
    );
    expect(usage.session!.total, 180);
    expect(usage.session!.input, 150);
    expect(usage.session!.output, 30);
    expect(usage.session!.cachedInput, 120);
    expect(usage.lifetime!.total, 10000);
  });

  test('partial session groups cannot be presented as a complete total', () {
    final usage = parseCodexTokenUsage(
      {},
      sessionPayload: {
        'threadUsage': {
          'groups': [
            {'totalTokens': 100},
            {'totalTokens': null},
          ],
        },
      },
    );
    expect(usage.session, isNull);
    expect(usage.hasData, isFalse);
  });

  test('credit parsing preserves zero, decimal precision, and unlimited', () {
    expect(parseCreditBalance({'balance': '0'})!.balance, '0');
    expect(parseCreditBalance({'balance': '120.50'})!.balance, '120.50');
    expect(parseCreditBalance({'balance': 4.5})!.balance, '4.5');
    expect(parseCreditBalance({'unlimited': true})!.unlimited, isTrue);
    final available = parseCreditBalance({'hasCredits': true});
    expect(available!.hasCredits, isTrue);
    expect(available.balance, isNull);
  });

  test('invalid credit values are not converted into a balance', () {
    for (final value in [
      '-1',
      'NaN',
      'Infinity',
      '1e999',
      'USD 20',
      true,
      {},
      [],
    ]) {
      expect(parseCreditBalance({'balance': value}), isNull);
    }
    expect(parseCreditBalance(null), isNull);
  });

  test('Codex credits are account data and reset credits stay separate', () {
    final snapshot = parseCodexQuota({
      'rateLimits': {
        'credits': {'balance': '5.25', 'hasCredits': true},
      },
      'rateLimitsByLimitId': {
        'review': {
          'credits': {'balance': '999'},
        },
      },
      'rateLimitResetCredits': {'availableCount': 2},
    });
    expect(snapshot.creditBalance!.balance, '5.25');
    expect(snapshot.resetCredits, 2);
    expect(snapshot.windows, isEmpty);
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.status, QuotaStatus.live);
  });

  test('token-only observations become visible without inventing quota', () {
    final snapshot = parseCodexQuota(
      {},
    ).withUsage(tokenUsage: const TokenUsage(lifetime: TokenCount(total: 123)));
    expect(snapshot.windows, isEmpty);
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.message, isNull);
  });
}
