import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/services/claude_desktop.dart';

void main() {
  const identifier = '12345678-1234-1234-1234-123456789abc';
  final instant = DateTime.utc(2026, 10, 14);
  Map<String, dynamic> session() => {
    'sessionKey': 'secret',
    'lastActiveOrganization': identifier,
  };
  ClaudeDesktopResponse organizations() => ClaudeDesktopResponse(
    200,
    jsonEncode([
      {'uuid': identifier},
    ]),
  );
  ClaudeDesktopResponse usage(num percent) => ClaudeDesktopResponse(
    200,
    jsonEncode({
      'five_hour': {
        'utilization': percent,
        'resets_at': '2026-10-14T05:00:00Z',
      },
      'seven_day': {'utilization': 23, 'resets_at': null},
    }),
  );

  test(
    'reads desktop windows and preserves zero without invented usage',
    () async {
      var calls = 0;
      final service = ClaudeDesktopService(
        sessionReader: (_) async => session(),
        now: () => instant,
        transport: (endpoint, key) async {
          expect(endpoint.scheme, 'https');
          expect(endpoint.host, 'claude.ai');
          expect(key, 'secret');
          calls++;
          return endpoint.path.endsWith('/usage') ? usage(0) : organizations();
        },
      );
      final snapshot = (await service.fetch())!;
      expect(snapshot.source, 'Claude Desktop');
      expect(snapshot.status, QuotaStatus.live);
      expect(snapshot.windows.first.usedPercent, 0);
      expect(snapshot.tokenUsage.hasData, false);
      expect(snapshot.creditBalance, isNull);
      expect(await service.fetch(), same(snapshot));
      expect(calls, 2);
    },
  );

  test('missing session returns null without HTTP', () async {
    final service = ClaudeDesktopService(
      sessionReader: (_) async => null,
      transport: (_, _) async => throw StateError('Unexpected request'),
    );
    expect(await service.fetch(), isNull);
  });

  test('does not guess across multiple organizations', () async {
    final service = ClaudeDesktopService(
      sessionReader: (_) async => {'sessionKey': 'secret'},
      transport: (_, _) async => ClaudeDesktopResponse(
        200,
        jsonEncode([
          {'uuid': identifier},
          {'uuid': 'abcdefab-1234-1234-1234-123456789abc'},
        ]),
      ),
    );
    await expectLater(service.fetch(), throwsA(isA<ClaudeDesktopException>()));
  });

  test('invalid usage is unavailable instead of zero', () async {
    final service = ClaudeDesktopService(
      sessionReader: (_) async => session(),
      transport: (endpoint, _) async =>
          endpoint.path.endsWith('/usage') ? usage(101) : organizations(),
    );
    final snapshot = (await service.fetch())!;
    expect(snapshot.windows.map((window) => window.id), ['seven_day']);
  });

  test(
    'failed refresh retains stale observation and rate-limit cooldown',
    () async {
      var now = instant;
      var failing = false;
      var calls = 0;
      final service = ClaudeDesktopService(
        sessionReader: (_) async => session(),
        now: () => now,
        transport: (endpoint, _) async {
          calls++;
          if (failing)
            return const ClaudeDesktopResponse(429, '', retryAfter: '300');
          return endpoint.path.endsWith('/usage') ? usage(40) : organizations();
        },
      );
      await service.fetch();
      now = now.add(const Duration(minutes: 6));
      failing = true;
      final stale = (await service.fetch())!;
      expect(stale.status, QuotaStatus.stale);
      expect(stale.observedAt, instant);
      expect(stale.windows.first.usedPercent, 40);
      final previousCalls = calls;
      await service.fetch();
      expect(calls, previousCalls);
    },
  );

  test('explicit access prompts only when requested', () async {
    final prompts = <bool>[];
    final service = ClaudeDesktopService(
      sessionReader: (prompt) async {
        prompts.add(prompt);
        return session();
      },
      transport: (endpoint, _) async =>
          endpoint.path.endsWith('/usage') ? usage(12) : organizations(),
    );
    expect(await service.requestAccess(), true);
    await service.fetch();
    expect(prompts, [true, false]);
  });

  test('malformed secret fails before transport', () async {
    final service = ClaudeDesktopService(
      sessionReader: (_) async => {'sessionKey': 'secret; other=value'},
      transport: (_, _) async => throw StateError('Unexpected request'),
    );
    await expectLater(service.fetch(), throwsA(isA<ClaudeDesktopException>()));
  });
  test(
    'changed session failure never returns previous account quota',
    () async {
      var key = 'first';
      final service = ClaudeDesktopService(
        sessionReader: (_) async => {...session(), 'sessionKey': key},
        transport: (endpoint, _) async {
          if (key == 'second') return const ClaudeDesktopResponse(500, '');
          return endpoint.path.endsWith('/usage') ? usage(42) : organizations();
        },
      );
      await service.fetch();
      key = 'second';
      await expectLater(
        service.fetch(),
        throwsA(
          isA<ClaudeDesktopException>().having(
            (error) => error.discardPreviousData,
            'discardPreviousData',
            true,
          ),
        ),
      );
    },
  );

  test('logout discards cached account before TTL expires', () async {
    var signedIn = true;
    final service = ClaudeDesktopService(
      sessionReader: (_) async => signedIn ? session() : null,
      transport: (endpoint, _) async =>
          endpoint.path.endsWith('/usage') ? usage(42) : organizations(),
    );
    await service.fetch();
    signedIn = false;
    await expectLater(
      service.fetch(),
      throwsA(
        isA<ClaudeDesktopException>()
            .having(
              (error) => error.code,
              'code',
              ClaudeDesktopErrorCode.sessionMissing,
            )
            .having(
              (error) => error.discardPreviousData,
              'discardPreviousData',
              true,
            ),
      ),
    );
  });

  for (final retryAfter in ['3600', 'Wed, 14 Oct 2026 01:00:00 GMT']) {
    test(
      'rate limit $retryAfter survives explicit access and long retry delay',
      () async {
        var now = instant;
        var calls = 0;
        final service = ClaudeDesktopService(
          sessionReader: (_) async => session(),
          now: () => now,
          transport: (_, _) async {
            calls++;
            return ClaudeDesktopResponse(429, '', retryAfter: retryAfter);
          },
        );
        await expectLater(
          service.fetch(),
          throwsA(
            isA<ClaudeDesktopException>().having(
              (error) => error.code,
              'code',
              ClaudeDesktopErrorCode.rateLimited,
            ),
          ),
        );
        now = instant.add(const Duration(minutes: 10));
        await service.requestAccess();
        await expectLater(
          service.fetch(),
          throwsA(isA<ClaudeDesktopException>()),
        );
        expect(calls, 1);
        now = instant.add(const Duration(minutes: 61));
        await expectLater(
          service.fetch(),
          throwsA(isA<ClaudeDesktopException>()),
        );
        expect(calls, 2);
      },
    );
  }

  for (final code in [401, 403]) {
    test(
      'HTTP $code exposes typed fixed failure and discards cached data',
      () async {
        var now = instant;
        var failing = false;
        final service = ClaudeDesktopService(
          sessionReader: (_) async => session(),
          now: () => now,
          transport: (endpoint, _) async {
            if (failing) return ClaudeDesktopResponse(code, 'private failure');
            return endpoint.path.endsWith('/usage')
                ? usage(42)
                : organizations();
          },
        );
        await service.fetch();
        failing = true;
        now = now.add(const Duration(minutes: 6));
        await expectLater(
          service.fetch(),
          throwsA(
            isA<ClaudeDesktopException>()
                .having(
                  (error) => error.discardPreviousData,
                  'discardPreviousData',
                  true,
                )
                .having(
                  (error) => error.message.contains('private'),
                  'safe message',
                  false,
                ),
          ),
        );
      },
    );
  }
  test('native error codes preserve typed failures without native details', () {
    final codes = {
      'desktop_keychain_locked': ClaudeDesktopErrorCode.permissionDenied,
      'desktop_session_missing': ClaudeDesktopErrorCode.sessionMissing,
      'desktop_session_invalid': ClaudeDesktopErrorCode.sessionInvalid,
      'desktop_session_unavailable': ClaudeDesktopErrorCode.responseInvalid,
    };
    for (final entry in codes.entries) {
      final failure = ClaudeDesktopException.fromPlatformException(
        PlatformException(
          code: entry.key,
          message: 'secret native data',
          details: 'private path',
        ),
      );
      expect(failure.code, entry.value);
      expect(failure.message, isNot(contains('secret')));
      expect(failure.toString(), isNot(contains('private')));
    }
  });
}
