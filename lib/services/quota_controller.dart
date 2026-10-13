import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/integration_diagnostic.dart';
import '../models/communication_diagnostic.dart';
import '../models/quota.dart';
import '../models/quota_account.dart';
import '../models/usage.dart';
import 'quota_sources.dart';

typedef QuotaFetcher = Future<QuotaSnapshot> Function(ProviderKind provider);

typedef AccountQuotaFetcher =
    Future<QuotaSnapshot> Function(QuotaAccount account);

@immutable
class RefreshDiagnostic {
  const RefreshDiagnostic({
    required this.attemptedAt,
    required this.elapsed,
    required this.status,
    required this.retainedPrevious,
    this.errorType,
  });

  final DateTime attemptedAt;
  final Duration elapsed;
  final QuotaStatus status;
  final String? errorType;
  final bool retainedPrevious;
}

class QuotaController extends ChangeNotifier {
  QuotaController({
    QuotaFetcher? fetcher,
    List<QuotaAccount>? accounts,
    AccountQuotaFetcher? accountFetcher,
    Future<void> Function(List<QuotaAccount>)? saveAccounts,
    bool debugMode = false,
  }) : _debugMode = debugMode,
       _accounts = List.unmodifiable(accounts ?? QuotaAccount.defaults),
       _fetcher =
           accountFetcher ??
           (fetcher == null
               ? QuotaSources().fetchAccount
               : (account) => fetcher(account.provider)),
       _saveAccounts = saveAccounts {
    validateAccounts(_accounts);
    if (_debugMode) _debugClock.start();
  }

  final AccountQuotaFetcher _fetcher;
  final Future<void> Function(List<QuotaAccount>)? _saveAccounts;
  List<QuotaAccount> _accounts;
  List<QuotaAccount> get accounts => _accounts;
  final Map<String, QuotaSnapshot> snapshots = {};
  bool _saving = false;
  bool _debugMode;
  bool get debugMode => _debugMode;
  int _debugGeneration = 0;
  final Map<String, RefreshDiagnostic> _diagnostics = {};
  Map<String, RefreshDiagnostic> get diagnostics =>
      Map.unmodifiable(_diagnostics);

  final Map<String, List<IntegrationDiagnostic>> _integrationDiagnostics = {};
  Map<String, List<IntegrationDiagnostic>> get integrationDiagnostics =>
      Map.unmodifiable({
        for (final entry in _integrationDiagnostics.entries)
          entry.key: List<IntegrationDiagnostic>.unmodifiable(entry.value),
      });

  final Stopwatch _debugClock = Stopwatch();
  final List<DebugLogEntry> _debugLogs = [];
  List<DebugLogEntry> get debugLogs => List.unmodifiable(_debugLogs);
  int _droppedDebugLogCount = 0;
  int get droppedDebugLogCount => _droppedDebugLogCount;

  void clearDebugLogs() {
    if (_disposed) return;
    _debugLogs.clear();
    _droppedDebugLogCount = 0;
    notifyListeners();
  }

  void _log(QuotaAccount account, String message) {
    if (!_debugMode || _disposed) return;
    final index = _accounts.indexWhere((item) => item.id == account.id);
    if (index < 0) return;
    _debugLogs.add(
      DebugLogEntry(
        elapsed: _debugClock.elapsed,
        provider: account.provider,
        accountNumber: index + 1,
        message: message,
      ),
    );
    if (_debugLogs.length > 1000) {
      _debugLogs.removeAt(0);
      _droppedDebugLogCount++;
    }
  }

  void setDebugMode(bool enabled) {
    if (_disposed || _debugMode == enabled) return;
    _debugMode = enabled;
    _debugGeneration++;
    _debugClock..reset();
    if (enabled)
      _debugClock.start();
    else
      _debugClock.stop();
    if (!enabled) {
      _diagnostics.clear();
      _integrationDiagnostics.clear();
      _debugLogs.clear();
      _droppedDebugLogCount = 0;
    }
    notifyListeners();
  }

  Future<void> setAccounts(List<QuotaAccount> accounts) async {
    if (_disposed) return;
    if (_saving) throw StateError('An account update is already in progress.');
    final next = List<QuotaAccount>.unmodifiable(accounts);
    validateAccounts(next);
    _saving = true;
    try {
      await _saveAccounts?.call(next);
      if (_disposed) return;
      final previousAccounts = {
        for (final account in _accounts) account.id: account,
      };
      _generation++;
      _diagnostics.clear();
      _integrationDiagnostics.clear();
      _debugLogs.clear();
      _droppedDebugLogCount = 0;
      refreshing = false;
      snapshots.removeWhere(
        (id, snapshot) => !next.any(
          (account) =>
              account.id == id &&
              previousAccounts[id] != null &&
              account.hasSameConnection(previousAccounts[id]!),
        ),
      );
      _accounts = next;
      for (final account in next) {
        final snapshot = snapshots[account.id];
        if (snapshot != null)
          snapshots[account.id] = snapshot.withAccount(account);
      }
      notifyListeners();
      unawaited(refresh());
    } finally {
      _saving = false;
    }
  }

  List<QuotaSnapshot> get visibleSnapshots => [
    for (final account in accounts)
      if (snapshots[account.id] case final snapshot?)
        if (snapshot.hasUsage &&
            {
              QuotaStatus.live,
              QuotaStatus.stale,
              QuotaStatus.demo,
            }.contains(snapshot.status))
          snapshot,
  ];
  Timer? _timer;
  bool refreshing = false;
  bool demo = false;
  bool _disposed = false;
  int _generation = 0;

  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refresh()),
    );
  }

  void setDemo(bool enabled) {
    if (_disposed) return;
    demo = enabled;
    _debugLogs.clear();
    _droppedDebugLogCount = 0;
    _generation++;
    refreshing = false;
    snapshots.clear();
    _diagnostics.clear();
    _integrationDiagnostics.clear();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (refreshing || _disposed) return;
    final generation = _generation;
    final captureDiagnostics = _debugMode;
    final debugGeneration = _debugGeneration;
    refreshing = true;
    notifyListeners();
    await Future.wait(
      accounts.map((account) async {
        final provider = account.provider;
        final attemptedAt = captureDiagnostics ? DateTime.now().toUtc() : null;
        final stopwatch = captureDiagnostics ? (Stopwatch()..start()) : null;
        if (captureDiagnostics)
          _log(account, 'refresh start mode=${demo ? 'demo' : 'live'}');
        String? errorType;
        QuotaSnapshot snapshot;
        try {
          if (demo) {
            snapshot = _demo(provider);
          } else if (captureDiagnostics) {
            snapshot = await runZoned(
              () => _fetcher(account),
              zoneValues: {
                communicationDiagnosticSinkKey: (CommunicationDiagnostic diagnostic) {
                  if (_disposed ||
                      generation != _generation ||
                      !_debugMode ||
                      debugGeneration != _debugGeneration)
                    return;
                  _log(
                    account,
                    '${diagnostic.protocol} ${diagnostic.direction} ${diagnostic.operation}'
                    '${diagnostic.statusCode == null ? '' : ' status=${diagnostic.statusCode}'}'
                    '${diagnostic.bytes == null ? '' : ' bytes=${diagnostic.bytes}'} ${diagnostic.detail}',
                  );
                  notifyListeners();
                },
                integrationDiagnosticSinkKey: (IntegrationDiagnostic diagnostic) {
                  if (_disposed ||
                      generation != _generation ||
                      !_debugMode ||
                      debugGeneration != _debugGeneration)
                    return;
                  final events = _integrationDiagnostics.putIfAbsent(
                    account.id,
                    () => <IntegrationDiagnostic>[],
                  );
                  events.add(diagnostic);
                  _log(
                    account,
                    'integration ${diagnostic.stage} ${diagnostic.outcome} duration_us=${diagnostic.elapsed.inMicroseconds}'
                    '${diagnostic.errorType == null ? '' : ' error=${diagnostic.errorType}'}'
                    '${diagnostic.metrics.entries.map((entry) => ' ${entry.key}=${entry.value}').join()}',
                  );
                  if (events.length > 200) {
                    events.removeRange(0, events.length - 200);
                  }
                  notifyListeners();
                },
              },
            );
          } else {
            snapshot = await _fetcher(account);
          }
        } on Object catch (error) {
          if (captureDiagnostics) {
            final type = error.runtimeType.toString();
            errorType = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(type)
                ? type
                : 'Exception';
          }
          snapshot = QuotaSnapshot(
            provider: provider,
            windows: [],
            observedAt: DateTime.now(),
            source: 'Provider',
            status: QuotaStatus.error,
            message: 'Could not refresh. Check the connection and retry.',
          );
        }
        stopwatch?.stop();
        if (_disposed || generation != _generation) return;
        final resultStatus = snapshot.status;
        final previous = snapshots[account.id];
        final retainedPrevious =
            snapshot.status == QuotaStatus.error &&
            !snapshot.discardPreviousData &&
            previous != null &&
            previous.hasUsage;
        if (retainedPrevious) {
          snapshot = QuotaSnapshot(
            provider: provider,
            windows: previous.windows,
            observedAt: previous.observedAt,
            source: previous.source,
            planName: previous.planName,
            tokenUsage: previous.tokenUsage,
            creditBalance: previous.creditBalance,
            resetCredits: previous.resetCredits,
            status: QuotaStatus.stale,
            message: snapshot.message,
          );
        }
        if (captureDiagnostics &&
            _debugMode &&
            debugGeneration == _debugGeneration) {
          _log(
            account,
            'refresh end status=${resultStatus.name} retained_previous=$retainedPrevious duration_us=${stopwatch!.elapsed.inMicroseconds}${errorType == null ? '' : ' error=$errorType'}',
          );
          _diagnostics[account.id] = RefreshDiagnostic(
            attemptedAt: attemptedAt!,
            elapsed: stopwatch.elapsed,
            status: resultStatus,
            errorType: errorType,
            retainedPrevious: retainedPrevious,
          );
        }
        snapshots[account.id] = snapshot.withAccount(account);
        notifyListeners();
      }),
    );
    if (_disposed || generation != _generation) return;
    refreshing = false;
    notifyListeners();
  }

  QuotaSnapshot _demo(ProviderKind provider) {
    final now = DateTime.now().toUtc();
    return QuotaSnapshot(
      provider: provider,
      observedAt: now,
      source: 'Sample data',
      status: QuotaStatus.demo,
      tokenUsage: const TokenUsage(
        today: TokenCount(total: 125000, input: 100000, output: 25000),
        session: TokenCount(
          total: 32000,
          input: 27000,
          output: 5000,
          cachedInput: 16000,
        ),
        lifetime: TokenCount(total: 4200000),
        note: 'Sample token counts.',
      ),
      creditBalance: provider == ProviderKind.codex
          ? const CreditBalance(balance: '120.50', hasCredits: true)
          : null,
      windows: [
        QuotaWindow(
          id: 'primary',
          label: provider == ProviderKind.antigravity
              ? 'Gemini Pro'
              : '5 hours',
          usedPercent: [28.0, 64.0, 12.0][provider.index],
          resetsAt: now.add(const Duration(hours: 2, minutes: 18)),
        ),
        QuotaWindow(
          id: 'secondary',
          label: provider == ProviderKind.antigravity
              ? 'Claude Sonnet'
              : '7 days',
          usedPercent: [43.0, 21.0, 36.0][provider.index],
          resetsAt: now.add(const Duration(days: 3, hours: 7)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _debugClock.stop();
    super.dispose();
  }
}
