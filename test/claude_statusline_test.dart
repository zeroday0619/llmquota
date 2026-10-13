import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Claude bridge writes independent account snapshots', () async {
    final configuration = File('.dart_tool/package_config.json');
    final packages = jsonDecode(await configuration.readAsString()) as Map;
    final flutter = (packages['packages'] as List).cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final flutterUri = configuration.absolute.uri.resolve(
      '${flutter['rootUri']}/',
    );
    final dart = flutterUri
        .resolve(
          '../../bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
        )
        .toFilePath();
    final temporary = await Directory.systemTemp.createTemp('quota-bridge-');
    addTearDown(() => temporary.delete(recursive: true));
    Future<int> writeSnapshot(
      String path,
      int used, {
      Future<void> Function(Process)? beforeInput,
    }) async {
      final process = await Process.start(dart, [
        'run',
        'tool/claude_statusline.dart',
        '--snapshot',
        path,
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        return await (() async {
          if (beforeInput != null) await beforeInput(process);
          process.stdin.write(
            jsonEncode({
              'rate_limits': {
                'five_hour': {'used_percentage': used},
              },
              'api_key': 'must-not-be-stored',
            }),
          );
          await process.stdin.close();
          final code = await process.exitCode;
          expect(await output, isNot(contains('must-not-be-stored')));
          expect(await errors, isNot(contains('must-not-be-stored')));
          return code;
        })().timeout(const Duration(seconds: 15));
      } finally {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(const Duration(seconds: 2));
        }
      }
    }

    final first = File('${temporary.path}/first.json');
    final second = File('${temporary.path}/second.json');
    expect(await writeSnapshot(first.path, 20), 0);
    expect(await writeSnapshot(second.path, 60), 0);
    for (final entry in [(first, 20), (second, 60)]) {
      final contents = await entry.$1.readAsString();
      expect(contents, isNot(contains('must-not-be-stored')));
      expect(
        jsonDecode(contents)['rate_limits']['five_hour']['used_percentage'],
        entry.$2,
      );
    }
    expect(await writeSnapshot('relative.json', 10), 1);
    expect(
      jsonDecode(
        await first.readAsString(),
      )['rate_limits']['five_hour']['used_percentage'],
      20,
    );

    if (!Platform.isWindows) {
      final victim = File('${temporary.path}/victim.txt');
      await victim.writeAsString('original');
      final snapshot = File('${temporary.path}/symlink.json');
      expect(
        await writeSnapshot(
          snapshot.path,
          35,
          beforeInput: (process) async {
            await Link(
              '${snapshot.path}.${process.pid}.temp',
            ).create(victim.path);
          },
        ),
        0,
      );
      expect(await victim.readAsString(), 'original');
      expect(
        jsonDecode(
          await snapshot.readAsString(),
        )['rate_limits']['five_hour']['used_percentage'],
        35,
      );

      final unsafe = Directory('${temporary.path}/shared');
      await unsafe.create();
      final permissionChange = await Process.run('chmod', [
        '0777',
        unsafe.path,
      ]);
      expect(permissionChange.exitCode, 0);
      final rejected = File('${unsafe.path}/quota.json');
      expect(await writeSnapshot(rejected.path, 35), 1);
      expect(await rejected.exists(), isFalse);
    }
  });
}
