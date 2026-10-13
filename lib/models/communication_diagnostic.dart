import 'dart:async';
import 'dart:convert';

import 'quota.dart';

final Object communicationDiagnosticSinkKey = Object();
typedef CommunicationDiagnosticSink = void Function(CommunicationDiagnostic);

class CommunicationDiagnostic {
  const CommunicationDiagnostic({
    required this.protocol,
    required this.direction,
    required this.operation,
    required this.detail,
    this.bytes,
    this.statusCode,
  });
  final String protocol;
  final String direction;
  final String operation;
  final String detail;
  final int? bytes;
  final int? statusCode;
}

class DebugLogEntry {
  const DebugLogEntry({
    required this.elapsed,
    required this.provider,
    required this.accountNumber,
    required this.message,
  });
  final Duration elapsed;
  final ProviderKind provider;
  final int accountNumber;
  final String message;
  String get formatted =>
      '[${(elapsed.inMicroseconds / 1000000).toStringAsFixed(6).padLeft(11)}] ${provider.name}/account-$accountNumber $message';
}

void recordCommunication(
  String protocol,
  String direction,
  String operation, {
  Object? payload,
  int? bytes,
  int? statusCode,
}) {
  final sink = Zone.current[communicationDiagnosticSinkKey];
  if (sink is! CommunicationDiagnosticSink) return;
  sink(
    CommunicationDiagnostic(
      protocol: _identifier(protocol),
      direction: _identifier(direction),
      operation: _identifier(operation),
      detail: sanitizeCommunicationPayload(payload),
      bytes: bytes,
      statusCode: statusCode,
    ),
  );
}

String _identifier(String value) =>
    RegExp(r'^[A-Za-z0-9_./ -]{1,100}$').hasMatch(value) ? value : '[REDACTED]';

const _fields = <String>{
  'body',
  'authHeaderPresent',
  'parseError',
  'args',
  'arguments',
  'contentType',
  'connectProtocolVersion',
  'jsonrpc',
  'id',
  'method',
  'params',
  'result',
  'error',
  'code',
  'data',
  'capabilities',
  'experimentalApi',
  'clientInfo',
  'version',
  'rateLimits',
  'rateLimitsByLimitId',
  'primary',
  'secondary',
  'usedPercent',
  'windowDurationMins',
  'resetsAt',
  'credits',
  'balance',
  'unlimited',
  'hasCredits',
  'planType',
  'planName',
  'summary',
  'lifetimeTokens',
  'dailyUsageBuckets',
  'startDate',
  'tokens',
  'threadUsage',
  'tokenUsage',
  'total',
  'last',
  'groups',
  'totalTokens',
  'inputTokens',
  'outputTokens',
  'cachedInputTokens',
  'cachedCreationInputTokens',
  'forceRefresh',
  'metadata',
  'userStatus',
  'quotaSummary',
  'quotaInfos',
  'remainingFraction',
  'resetTime',
  'usage',
  'input_tokens',
  'output_tokens',
  'cache_read_input_tokens',
  'cache_creation_input_tokens',
  'five_hour',
  'seven_day',
  'utilization',
  'resets_at',
  'subscriptionType',
  'subscription_type',
  'isAuthenticated',
  'loggedIn',
  'status',
  'port',
  'exitCode',
  'payload',
  'codex',
  'rate_limits',
  'plan_type',
  'used_percent',
  'window_minutes',
  'limitName',
  'rateLimitResetCredits',
  'availableCount',
  'used_percentage',
  'models',
  'cascadeModelConfigData',
  'clientModelConfigs',
  'buckets',
  'bucketId',
  'quotaInfo',
  'remaining',
  'displayName',
  'label',
  'description',
  'planStatus',
  'planInfo',
  'name',
  'title',
  'ideName',
  'extensionName',
  'ideVersion',
  'locale',
  'model',
  'modelId',
  'modelName',
};
const _sensitive = <String>{
  'threadid',
  'message',
  'email',
  'path',
  'token',
  'auth',
  'csrf',
  'userid',
  'accountid',
  'apikey',
  'headers',
  'authorization',
  'password',
  'secret',
  'accesstoken',
  'refreshtoken',
  'csrftoken',
};

String sanitizeCommunicationPayload(Object? payload) {
  Object? sanitize(Object? value, String? field, int depth) {
    if (depth > 6) return '[TRUNCATED]';
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : '[REDACTED]';
    if (value is Map) {
      final output = <String, Object?>{};
      var omitted = 0;
      var included = 0;
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          omitted++;
          continue;
        }
        final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        if (normalized == 'path' &&
            entry.value is String &&
            RegExp(
              r'^/exa\.language_server_pb\.LanguageServerService/(RetrieveUserQuotaSummary|GetUserStatus)$',
            ).hasMatch(entry.value as String)) {
          output['path'] = entry.value;
          included++;
          continue;
        }
        if (_sensitive.contains(normalized)) {
          if (included++ < 100) output['<redacted $normalized>'] = '[REDACTED]';
          continue;
        }
        if (!_fields.contains(key) || included >= 100) {
          omitted++;
          continue;
        }
        included++;
        output[key] = sanitize(entry.value, key, depth + 1);
      }
      if (omitted > 0) output['<omitted fields>'] = omitted;
      return output;
    }
    if (value is List)
      return [
        for (final item in value.take(20)) sanitize(item, field, depth + 1),
        if (value.length > 20) '[TRUNCATED]',
      ];
    if (value is String) {
      if (field == 'method' &&
          {
            'POST',
            'GET',
            'initialize',
            'initialized',
            'account/rateLimits/read',
            'account/usage/read',
            'account/rateLimits/updated',
            'thread/tokenUsage/updated',
            'account/updated',
            'error',
            'RetrieveUserQuotaSummary',
            'GetUserStatus',
          }.contains(value))
        return value;
      if ({'args', 'arguments'}.contains(field) &&
          {'auth', 'status', '--json'}.contains(value))
        return value;
      if (field == 'contentType' &&
          {
            'application/json',
            'application/json; charset=utf-8',
          }.contains(value))
        return value;
      if (field == 'connectProtocolVersion' && value == '1') return value;
      if (field == 'jsonrpc' && value == '2.0') return value;
      if ({'version', 'ideVersion'}.contains(field) &&
          RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$').hasMatch(value))
        return value;
      if ({'startDate', 'resetTime', 'resets_at'}.contains(field) &&
          RegExp(
            r'^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2}))?$',
          ).hasMatch(value))
        return value;
      if ({
            'planType',
            'planName',
            'plan_type',
            'subscriptionType',
            'subscription_type',
          }.contains(field) &&
          {
            'free',
            'plus',
            'pro',
            'team',
            'business',
            'enterprise',
            'education',
            'max',
            'Free',
            'Plus',
            'Pro',
            'Team',
            'Business',
            'Enterprise',
            'Education',
            'Max',
          }.contains(value))
        return value;
      if (field == 'balance' &&
          value.length <= 80 &&
          RegExp(r'^\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$').hasMatch(value))
        return value;
      return '[REDACTED]';
    }
    return '[REDACTED]';
  }

  final encoded = jsonEncode(sanitize(payload, null, 0));
  return encoded.length <= 4096
      ? encoded
      : '${encoded.substring(0, 4082)} [TRUNCATED]';
}
