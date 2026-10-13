import 'package:flutter/material.dart';

import 'models/quota.dart';
import 'models/usage.dart';

class UsageSummary extends StatelessWidget {
  const UsageSummary({super.key, required this.snapshot, this.hud = false});

  final QuotaSnapshot snapshot;
  final bool hud;

  static bool _hasCreditData(CreditBalance? credits) =>
      credits != null &&
      (credits.unlimited ||
          credits.balance != null ||
          credits.hasCredits != null);

  static int _visibleRows(QuotaSnapshot snapshot) =>
      [
        snapshot.tokenUsage.today,
        snapshot.tokenUsage.session,
        snapshot.tokenUsage.lifetime,
      ].whereType<TokenCount>().length +
      (_hasCreditData(snapshot.creditBalance) ? 1 : 0) +
      (snapshot.resetCredits != null ? 1 : 0);

  static double estimatedHeight(QuotaSnapshot snapshot, {bool hud = false}) {
    final rows = _visibleRows(snapshot);
    return rows == 0 ? 0 : 8 + rows * (hud ? 20 : 24);
  }

  Widget _row(
    BuildContext context,
    String label,
    String value,
    String tooltip,
  ) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Tooltip(
      message: tooltip,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: hud ? 12 : 14),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tokens(BuildContext context, String label, TokenCount count) {
    final details = [
      '${count.total} tokens',
      if (count.input != null) 'Input: ${count.input}',
      if (count.output != null) 'Output: ${count.output}',
      if (count.cachedInput != null)
        'Cached input: ${count.cachedInput} (included in input)',
    ].join('\n');
    return _row(
      context,
      '$label tokens',
      _format(count.total),
      '$details${snapshot.tokenUsage.note == null ? '' : '\n${snapshot.tokenUsage.note}'}',
    );
  }

  static String _format(int count) {
    for (final unit in [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')]) {
      if (count >= unit.$1) {
        final value = (count / unit.$1).toStringAsFixed(1);
        return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}${unit.$2}';
      }
    }
    return '$count';
  }

  static String _wholeCredits(String balance) {
    final parts = balance.toLowerCase().split('e');
    final decimal = parts.first.split('.');
    final digits = decimal.join();
    final exponent = parts.length == 1 ? 0 : int.tryParse(parts.last);
    if (exponent == null) return '0';
    final point = decimal.first.length + exponent;
    if (point <= 0) return '0';
    final whole = point < digits.length
        ? digits.substring(0, point)
        : digits.padRight(point, '0');
    return BigInt.parse(whole).toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_visibleRows(snapshot) == 0) return const SizedBox.shrink();
    final usage = snapshot.tokenUsage;
    final credits = snapshot.creditBalance;
    final balance = credits == null
        ? ''
        : credits.unlimited
        ? 'Unlimited'
        : credits.balance != null
        ? '${_wholeCredits(credits.balance!)} credits'
        : credits.hasCredits == true
        ? 'Available'
        : credits.hasCredits == false
        ? 'No credits'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          if (usage.today != null)
            _tokens(context, usage.todayLabel, usage.today!),
          if (usage.session != null)
            _tokens(context, usage.sessionLabel, usage.session!),
          if (usage.lifetime != null)
            _tokens(context, usage.lifetimeLabel, usage.lifetime!),
          if (_hasCreditData(credits))
            _row(
              context,
              'Credits',
              balance,
              'Provider-reported credit balance: ${credits!.unlimited || credits.balance == null ? balance : '${credits.balance} credits'}',
            ),
          if (snapshot.resetCredits != null)
            _row(
              context,
              'Reset credits',
              '${snapshot.resetCredits}',
              'Provider-reported reset credits: ${snapshot.resetCredits}',
            ),
        ],
      ),
    );
  }
}
