import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/models/communication_diagnostic.dart';

void main() {
  test(
    'communication payload preserves protocol metrics and removes secrets',
    () {
      final detail = sanitizeCommunicationPayload({
        'id': 3,
        'method': 'account/usage/read',
        'params': {'threadId': 'secret'},
        'result': {
          'summary': {'lifetimeTokens': 200},
          'balance': '12.50',
          'email': 'secret@example.com',
          'otherPrivateField': 'private',
        },
        'message': 'secret error',
      });
      expect(detail, contains('200'));
      expect(detail, contains('12.50'));
      expect(detail, contains('account/usage/read'));
      expect(detail, isNot(contains('secret')));
      expect(detail, isNot(contains('otherPrivateField')));
      expect(detail, contains('<omitted fields>'));
      expect(jsonDecode(detail), isA<Map>());
    },
  );
  test('arbitrary values under approved string fields remain redacted', () {
    final detail = sanitizeCommunicationPayload({
      'method': 'secret.method',
      'version': 'secret',
      'startDate': 'secret',
      'planName': 'secret',
      'model': 'secret',
      'name': 'secret',
    });
    expect(detail, isNot(contains('secret')));
  });
  test('HTTP metadata and CLI arguments retain safe protocol values', () {
    final detail = sanitizeCommunicationPayload({
      'method': 'POST',
      'path': '/exa.language_server_pb.LanguageServerService/GetUserStatus',
      'contentType': 'application/json',
      'connectProtocolVersion': '1',
      'authHeaderPresent': true,
      'body': {'forceRefresh': true},
      'arguments': ['auth', 'status', '--json', 'private'],
    });
    expect(detail, contains('GetUserStatus'));
    expect(detail, contains('application/json'));
    expect(detail, contains('--json'));
    expect(detail, isNot(contains('private')));
    expect(
      sanitizeCommunicationPayload({'path': '/private/home'}),
      isNot(contains('/private/home')),
    );
  });

  test('serialization is skipped without an active sink', () {
    expect(
      () => recordCommunication(
        'jsonrpc',
        'send',
        'request',
        payload: _Unserializable(),
      ),
      returnsNormally,
    );
  });
  test('sink receives bounded sanitized payload', () {
    final events = <CommunicationDiagnostic>[];
    runZoned(
      () => recordCommunication(
        'jsonrpc',
        'receive',
        'response',
        payload: {
          'groups': List.generate(100, (_) => {'totalTokens': 42}),
        },
        bytes: 50,
      ),
      zoneValues: {
        communicationDiagnosticSinkKey: (CommunicationDiagnostic event) =>
            events.add(event),
      },
    );
    expect(events.single.bytes, 50);
    expect(events.single.detail.length, lessThanOrEqualTo(4096));
    expect(events.single.detail, contains('[TRUNCATED]'));
  });
}

class _Unserializable {
  @override
  String toString() => throw StateError('Must not serialize.');
}
