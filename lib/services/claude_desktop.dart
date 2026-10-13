import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/communication_diagnostic.dart';
import '../models/integration_diagnostic.dart';
import '../models/quota.dart';

typedef ClaudeDesktopSessionReader =
    Future<Map<String, dynamic>?> Function(bool allowPrompt);
typedef ClaudeDesktopTransport =
    Future<ClaudeDesktopResponse> Function(Uri endpoint, String sessionKey);

class ClaudeDesktopResponse {
  const ClaudeDesktopResponse(this.statusCode, this.body, {this.retryAfter});
  final int statusCode;
  final String body;
  final String? retryAfter;
}

enum ClaudeDesktopErrorCode {
  permissionDenied,
  sessionMissing,
  sessionInvalid,
  unauthorized,
  forbidden,
  rateLimited,
  responseInvalid,
  network,
  organizationUnavailable,
}

class ClaudeDesktopException implements Exception {
  const ClaudeDesktopException(
    this.code,
    this.message, {
    this.discardPreviousData = false,
  });
  factory ClaudeDesktopException.fromPlatformException(
    PlatformException error,
  ) {
    return switch (error.code) {
      'desktop_keychain_locked' ||
      'permissionDenied' ||
      'permission_denied' => const ClaudeDesktopException(
        ClaudeDesktopErrorCode.permissionDenied,
        'Allow Claude Desktop Keychain access in Settings > Connect providers.',
      ),
      'desktop_session_missing' => const ClaudeDesktopException(
        ClaudeDesktopErrorCode.sessionMissing,
        'Sign in to Claude Desktop and connect it in Settings > Connect providers.',
      ),
      'desktop_session_invalid' => const ClaudeDesktopException(
        ClaudeDesktopErrorCode.sessionInvalid,
        'Claude Desktop session is invalid. Sign in and reconnect it.',
      ),
      _ => const ClaudeDesktopException(
        ClaudeDesktopErrorCode.responseInvalid,
        'Claude Desktop session could not be read. Reconnect it or use the Claude Code bridge.',
      ),
    };
  }

  final ClaudeDesktopErrorCode code;
  final String message;
  final bool discardPreviousData;
  @override
  String toString() => message;
}

/// Reads the existing desktop session without changing or persisting credentials.
class ClaudeDesktopService {
  ClaudeDesktopService({
    ClaudeDesktopSessionReader? sessionReader,
    ClaudeDesktopTransport? transport,
    DateTime Function()? now,
  }) : _sessionReader = sessionReader ?? _readNativeSession,
       _transport = transport ?? _request,
       _now = now ?? DateTime.now;

  final ClaudeDesktopSessionReader _sessionReader;
  final ClaudeDesktopTransport _transport;
  final DateTime Function() _now;
  QuotaSnapshot? _cached;
  DateTime? _nextAttempt;

  String? _identity;
  bool _pendingDiscard = false;
  DateTime? _rateLimitUntil;
  ClaudeDesktopException? _lastFailure;

  bool _bindSession(Map<String, dynamic>? session) {
    final identity = session == null
        ? null
        : '${session['sessionKey']}\u0000${session['lastActiveOrganization']}';
    if (identity == _identity) return false;
    _pendingDiscard = _pendingDiscard || _identity != null;
    _identity = identity;
    _cached = null;
    _nextAttempt = null;
    _rateLimitUntil = null;
    _lastFailure = null;
    return true;
  }

  Future<bool> requestAccess() async {
    final session = await _sessionReader(true);
    _bindSession(session);
    if (_rateLimitUntil == null || !_now().toUtc().isBefore(_rateLimitUntil!))
      _nextAttempt = null;
    return session != null;
  }

  static Future<Map<String, dynamic>?> _readNativeSession(
    bool allowPrompt,
  ) async {
    if (!Platform.isMacOS) return null;
    try {
      return await const MethodChannel(
        'llmquota/claude_desktop',
      ).invokeMapMethod<String, dynamic>('readSession', {
        'allowPrompt': allowPrompt,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw ClaudeDesktopException.fromPlatformException(error);
    }
  }

  Future<QuotaSnapshot?> fetch() async {
    final now = _now().toUtc();
    var identityChanged = false;
    try {
      final session = await integrationStep(
        'claude.desktop.session',
        () => _sessionReader(false),
        available: (session) => session != null,
      );
      identityChanged = _bindSession(session) || _pendingDiscard;
      if (session == null) {
        if (identityChanged)
          throw const ClaudeDesktopException(
            ClaudeDesktopErrorCode.sessionMissing,
            'Claude Desktop is signed out. Sign in and reconnect it.',
            discardPreviousData: true,
          );
        return null;
      }
      if (_nextAttempt != null && now.isBefore(_nextAttempt!)) {
        if (_cached == null && _lastFailure != null) throw _lastFailure!;
        return _cached;
      }
      final key = session['sessionKey'];
      if (key is! String ||
          key.isEmpty ||
          key.length > 8192 ||
          RegExp(r'[\x00-\x20\x7f;]').hasMatch(key)) {
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.sessionInvalid,
          'Claude Desktop session is invalid.',
        );
      }
      final organizations = await _get(
        '/api/organizations',
        key,
        'organizations',
      );
      if (organizations is! List) {
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.responseInvalid,
          'Claude Desktop organizations were not recognized.',
        );
      }
      final identifiers = organizations
          .whereType<Map>()
          .map((organization) => organization['uuid'])
          .whereType<String>()
          .where(
            (identifier) => RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(identifier),
          )
          .toSet();
      final active = session['lastActiveOrganization'];
      final identifier = active is String && identifiers.contains(active)
          ? active
          : identifiers.length == 1
          ? identifiers.single
          : null;
      if (identifier == null) {
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.organizationUnavailable,
          'Claude Desktop active organization is unavailable.',
        );
      }
      final usage = await _get(
        '/api/organizations/$identifier/usage',
        key,
        'usage',
      );
      if (usage is! Map<String, dynamic>) {
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.responseInvalid,
          'Claude Desktop usage was not recognized.',
        );
      }
      final valid = <String, dynamic>{};
      for (final name in const [
        'five_hour',
        'seven_day',
        'seven_day_sonnet',
        'seven_day_opus',
        'seven_day_oauth_apps',
        'seven_day_cowork',
      ]) {
        final window = usage[name];
        if (window is! Map) continue;
        final percent = window['utilization'];
        if (percent is! num ||
            !percent.isFinite ||
            percent < 0 ||
            percent > 100)
          continue;
        final reset = window['resets_at'];
        if (reset != null &&
            (reset is! String ||
                !RegExp(
                  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
                ).hasMatch(reset) ||
                DateTime.tryParse(reset) == null))
          continue;
        valid[name] = {'utilization': percent, 'resets_at': reset};
      }
      if (valid.isEmpty)
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.responseInvalid,
          'Claude Desktop quota windows are unavailable.',
        );
      final snapshot = parseClaudeQuota(
        valid,
        observedAt: now,
        source: 'Claude Desktop',
      );
      _pendingDiscard = false;
      _lastFailure = null;
      _cached = snapshot;
      _nextAttempt = now.add(const Duration(minutes: 5));
      return snapshot;
    } on Object catch (error) {
      final failure = error is ClaudeDesktopException
          ? error
          : error is FormatException
          ? const ClaudeDesktopException(
              ClaudeDesktopErrorCode.responseInvalid,
              'Claude Desktop response was not recognized.',
            )
          : const ClaudeDesktopException(
              ClaudeDesktopErrorCode.network,
              'Claude Desktop could not be reached. Retry after checking the connection.',
            );
      final invalidSession =
          failure.code == ClaudeDesktopErrorCode.sessionMissing ||
          failure.code == ClaudeDesktopErrorCode.sessionInvalid;
      if (invalidSession) {
        identityChanged = _bindSession(null) || identityChanged;
        _cached = null;
      }
      _lastFailure = ClaudeDesktopException(
        failure.code,
        failure.message,
        discardPreviousData: identityChanged || failure.discardPreviousData,
      );
      if (failure.code == ClaudeDesktopErrorCode.unauthorized ||
          failure.code == ClaudeDesktopErrorCode.forbidden)
        _cached = null;
      final previous = _cached;
      if (previous == null) throw _lastFailure!;
      _cached = QuotaSnapshot(
        provider: previous.provider,
        windows: previous.windows,
        observedAt: previous.observedAt,
        source: previous.source,
        status: QuotaStatus.stale,
        message: failure.message,
      );
      _nextAttempt ??= now.add(const Duration(minutes: 1));
      if (!_nextAttempt!.isAfter(now))
        _nextAttempt = now.add(const Duration(minutes: 1));
      return _cached;
    }
  }

  Future<Object?> _get(String path, String key, String operation) async {
    return integrationStep('claude.desktop.http.$operation', () async {
      recordCommunication(
        'HTTPS',
        'TX',
        'Claude Desktop $operation',
        payload: {'method': 'GET', 'authHeaderPresent': true},
      );
      final response = await _transport(
        Uri.https('claude.ai', path),
        key,
      ).timeout(const Duration(seconds: 12));
      recordCommunication(
        'HTTPS',
        'RX',
        'Claude Desktop $operation',
        statusCode: response.statusCode,
        bytes: utf8.encode(response.body).length,
      );
      if (response.statusCode == 429) {
        final now = _now().toUtc();
        final seconds = int.tryParse(response.retryAfter ?? '');
        DateTime? date;
        try {
          date = HttpDate.parse(response.retryAfter ?? '').toUtc();
        } on Object {
          /* Invalid dates use the conservative fallback. */
        }
        _rateLimitUntil = seconds != null && seconds >= 0
            ? now.add(Duration(seconds: seconds))
            : date;
        final minimum = now.add(const Duration(minutes: 5));
        if (_rateLimitUntil == null || _rateLimitUntil!.isBefore(minimum))
          _rateLimitUntil = minimum;
        _nextAttempt = _rateLimitUntil;
      }
      if (response.statusCode != 200) {
        final code = switch (response.statusCode) {
          401 => ClaudeDesktopErrorCode.unauthorized,
          403 => ClaudeDesktopErrorCode.forbidden,
          429 => ClaudeDesktopErrorCode.rateLimited,
          _ => ClaudeDesktopErrorCode.network,
        };
        final message = switch (code) {
          ClaudeDesktopErrorCode.unauthorized =>
            'Claude Desktop session expired. Sign in and reconnect it.',
          ClaudeDesktopErrorCode.forbidden =>
            'Claude Desktop usage access was denied. Reconnect it or use the Claude Code bridge.',
          ClaudeDesktopErrorCode.rateLimited =>
            'Claude Desktop usage is rate limited. Wait before retrying.',
          _ =>
            'Claude Desktop usage request failed. Retry after checking the connection.',
        };
        throw ClaudeDesktopException(
          code,
          message,
          discardPreviousData:
              response.statusCode == 401 || response.statusCode == 403,
        );
      }
      if (utf8.encode(response.body).length > 1048576)
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.responseInvalid,
          'Claude Desktop response exceeded its size limit.',
        );
      try {
        final decoded = jsonDecode(response.body);
        if (operation == 'usage')
          recordCommunication(
            'HTTPS',
            'RX',
            'Claude Desktop quota',
            payload: decoded,
          );
        return decoded;
      } on FormatException {
        throw const ClaudeDesktopException(
          ClaudeDesktopErrorCode.responseInvalid,
          'Claude Desktop response was not valid JSON.',
        );
      }
    });
  }

  static Future<ClaudeDesktopResponse> _request(
    Uri endpoint,
    String key,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, 'sessionKey=$key');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        if (bytes.length + chunk.length > 1048576)
          throw const FormatException(
            'Claude Desktop response exceeded its size limit.',
          );
        bytes.addAll(chunk);
      }
      return ClaudeDesktopResponse(
        response.statusCode,
        utf8.decode(bytes),
        retryAfter: response.headers.value(HttpHeaders.retryAfterHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}
