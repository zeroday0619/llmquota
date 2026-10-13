import 'dart:async';

class IntegrationDiagnostic {
  IntegrationDiagnostic({
    required this.stage,
    required this.outcome,
    required DateTime attemptedAt,
    required this.elapsed,
    String? errorType,
    Map<String, num> metrics = const {},
  })  : attemptedAt = attemptedAt.toUtc(),
        errorType = errorType == null ? null : _safeErrorType(errorType),
        metrics = Map.unmodifiable(metrics);

  final String stage;
  final String outcome;
  final DateTime attemptedAt;
  final Duration elapsed;
  final String? errorType;
  final Map<String, num> metrics;
}

final Object integrationDiagnosticSinkKey = Object();
typedef IntegrationDiagnosticSink = void Function(IntegrationDiagnostic);

String _safeErrorType(String value) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(value)
        ? value
        : 'Exception';

Future<T> integrationStep<T>(
  String stage,
  Future<T> Function() action, {
  bool Function(T)? available,
  Map<String, num> Function(T)? metrics,
}) async {
  final sink = Zone.current[integrationDiagnosticSinkKey];
  if (sink is! IntegrationDiagnosticSink) return action();
  final attemptedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  sink(IntegrationDiagnostic(
    stage: stage,
    outcome: 'running',
    attemptedAt: attemptedAt,
    elapsed: Duration.zero,
  ));
  try {
    final result = await action();
    stopwatch.stop();
    sink(IntegrationDiagnostic(
      stage: stage,
      outcome: available?.call(result) == false ? 'unavailable' : 'success',
      attemptedAt: attemptedAt,
      elapsed: stopwatch.elapsed,
      metrics: metrics?.call(result) ?? const {},
    ));
    return result;
  } on Object catch (error) {
    stopwatch.stop();
    sink(IntegrationDiagnostic(
      stage: stage,
      outcome: 'error',
      attemptedAt: attemptedAt,
      elapsed: stopwatch.elapsed,
      errorType: error.runtimeType.toString(),
    ));
    rethrow;
  }
}
