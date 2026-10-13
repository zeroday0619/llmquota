import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/integration_diagnostic.dart';
import '../models/usage.dart';

/// Reads retained local API usage rather than live context occupancy.
Future<TokenUsage> readClaudeTokenUsage({
  required Map<String, String> environment,
  String? sessionId,
  String? transcriptPath,
  DateTime? now,
}) async {
  final candidateSink = Zone.current[integrationDiagnosticSinkKey];
  final sink = candidateSink is IntegrationDiagnosticSink
      ? candidateSink
      : null;
  final attemptedAt = sink == null ? null : DateTime.now().toUtc();
  final stopwatch = sink == null ? null : (Stopwatch()..start());
  final records = <String, _UsageRecord>{};
  var bytes = 0;
  var files = 0;
  void emit(String stage, String outcome, [Object? error]) {
    if (sink == null) return;
    sink(
      IntegrationDiagnostic(
        stage: stage,
        outcome: outcome,
        attemptedAt: attemptedAt!,
        elapsed: stopwatch!.elapsed,
        errorType: error?.runtimeType.toString(),
        metrics: {'bytes': bytes, 'files': files, 'records': records.length},
      ),
    );
  }

  TokenUsage unavailable(String reason) => TokenUsage(
    todayLabel: 'Today (local)',
    lifetimeLabel: 'Local total',
    note: reason,
  );
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  final config =
      environment['CLAUDE_CONFIG_DIR'] ??
      (home == null ? null : '$home/.claude');
  if (config == null) {
    emit('claude.history.noHistory', 'unavailable');
    return unavailable('Claude local history is unavailable.');
  }
  final directory = Directory('$config/projects');
  if (!await directory.exists()) {
    emit('claude.history.noHistory', 'unavailable');
    return unavailable('Claude local history is unavailable.');
  }
  try {
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
      var isActiveTranscript = false;
      if (transcriptPath != null) {
        try {
          // Filesystem identity handles native separators and relative paths.
          isActiveTranscript = await FileSystemEntity.identical(
            entry.path,
            transcriptPath,
          );
        } on FileSystemException {
          // A stale transcript path must not hide retained history totals.
        }
      }
      final length = await entry.length();
      bytes += length;
      files++;
      if (length > 64 * 1024 * 1024 ||
          bytes > 256 * 1024 * 1024 ||
          files > 10000) {
        emit('claude.history.scanLimit', 'unavailable');
        return unavailable('Claude history exceeds the local scan limit.');
      }
      await for (final line
          in entry
              .openRead(0, length)
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! Map) throw const FormatException();
        if (decoded['type'] != 'assistant') continue;
        final message = decoded['message'];
        if (message is! Map || message['usage'] is! Map) continue;
        final usage = message['usage'] as Map;
        final identifier = message['id'];
        final timestamp = decoded['timestamp'];
        final date = timestamp is String ? DateTime.tryParse(timestamp) : null;
        if (identifier is! String || identifier.isEmpty || date == null) {
          throw const FormatException();
        }
        int? count(String key, {bool optional = false}) {
          final value = usage[key];
          if (value == null && optional) return null;
          if (value is! int || value < 0) throw const FormatException();
          return value;
        }

        final next = _UsageRecord(
          date.toLocal(),
          count('input_tokens')!,
          count('output_tokens')!,
          count('cache_read_input_tokens', optional: true),
          count('cache_creation_input_tokens', optional: true),
          (sessionId != null && decoded['sessionId'] == sessionId) ||
              isActiveTranscript,
        );
        final previous = records[identifier];
        // Streaming transcript records may repeat one API message's counters.
        records[identifier] = previous == null ? next : previous.merge(next);
      }
    }
  } on Object catch (error) {
    emit('claude.history.scan.error', 'error', error);
    return unavailable('Claude history is incomplete or unreadable.');
  }
  if (records.isEmpty) {
    emit('claude.history.scan.empty', 'unavailable');
    return unavailable('No recorded Claude token usage is available.');
  }
  final localNow = (now ?? DateTime.now()).toLocal();
  final start = DateTime(localNow.year, localNow.month, localNow.day);
  final end = DateTime(localNow.year, localNow.month, localNow.day + 1);
  TokenCount sum(Iterable<_UsageRecord> selected) {
    var input = 0;
    var output = 0;
    var cached = 0;
    var created = 0;
    var creationAvailable = true;
    for (final record in selected) {
      input += record.input + (record.cached ?? 0) + (record.created ?? 0);
      output += record.output;
      cached += record.cached ?? 0;
      created += record.created ?? 0;
      if (record.created == null) creationAvailable = false;
    }
    return TokenCount(
      total: input + output,
      input: input,
      output: output,
      cachedInput: cached,
      cachedCreationInput: creationAvailable ? created : null,
    );
  }

  final session = records.values.where((record) => record.session);
  emit('claude.history.scan.success', 'success');
  return TokenUsage(
    today: sum(
      records.values.where(
        (record) => !record.date.isBefore(start) && record.date.isBefore(end),
      ),
    ),
    session: session.isEmpty ? null : sum(session),
    lifetime: sum(records.values),
    todayLabel: 'Today (local)',
    lifetimeLabel: 'Local total',
    note:
        'Retained local Claude history only; input includes cache reads and writes.',
  );
}

class _UsageRecord {
  const _UsageRecord(
    this.date,
    this.input,
    this.output,
    this.cached,
    this.created,
    this.session,
  );
  final DateTime date;
  final int input;
  final int output;
  final int? cached;
  final int? created;
  final bool session;

  _UsageRecord merge(_UsageRecord next) {
    final newer = next.date.isBefore(date) ? this : next;
    final older = identical(newer, this) ? next : this;
    return _UsageRecord(
      newer.date,
      newer.input,
      newer.output,
      newer.cached ?? older.cached,
      newer.created ?? older.created,
      session || next.session,
    );
  }
}
