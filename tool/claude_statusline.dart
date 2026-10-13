import 'dart:convert';
import 'dart:io';

import '../lib/services/app_paths.dart';

Future<Directory> _snapshotDirectory(File file) async {
  await file.parent.create(recursive: true);
  final directory = Directory(await file.parent.resolveSymbolicLinks());
  if (!Platform.isWindows) {
    var ancestor = directory;
    while (true) {
      final mode = (await ancestor.stat()).mode;
      const groupOrOtherWriteBits = 0x12;
      const stickyDirectoryBit = 0x200;
      if ((mode & groupOrOtherWriteBits) != 0 &&
          (mode & stickyDirectoryBit) == 0) {
        throw FileSystemException(
          'Snapshot directory is writable by another user without the sticky bit.',
          ancestor.path,
        );
      }
      final parent = ancestor.parent;
      if (parent.path == ancestor.path) break;
      ancestor = parent;
    }
  }
  return directory;
}

Future<void> main(List<String> arguments) async {
  try {
    File? configuredSnapshot;
    if (arguments.isNotEmpty) {
      if (arguments.length != 2 ||
          arguments.first != '--snapshot' ||
          !File(arguments.last).isAbsolute) {
        throw const FormatException();
      }
      configuredSnapshot = File(arguments.last);
    }
    final bytes = <int>[];
    await for (final chunk in stdin) {
      if (bytes.length + chunk.length > 1048576) throw const FormatException();
      bytes.addAll(chunk);
    }
    final input = jsonDecode(utf8.decode(bytes));
    if (input is! Map<String, dynamic>) throw const FormatException();
    final limits = input['rate_limits'];
    final filtered = <String, Object?>{};
    if (limits is Map) {
      for (final key in ['five_hour', 'seven_day']) {
        final window = limits[key];
        if (window is Map) {
          filtered[key] = {
            if (window['used_percentage'] is num)
              'used_percentage': window['used_percentage'],
            if (window['resets_at'] is num) 'resets_at': window['resets_at'],
          };
        }
      }
    }
    final file = configuredSnapshot ?? AppPaths().claudeSnapshotFile;
    final parent = await _snapshotDirectory(file);
    final target = File(
      '${parent.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
    );
    final directory = await parent.createTemp('.claude-snapshot-');
    final temporary = File('${directory.path}/snapshot.json');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'observed_at': DateTime.now().toUtc().toIso8601String(),
          'rate_limits': filtered,
          if (input['session_id'] is String &&
              (input['session_id'] as String).isNotEmpty &&
              (input['session_id'] as String).length <= 256)
            'session_id': input['session_id'],
          if (input['transcript_path'] is String &&
              (input['transcript_path'] as String).length <= 4096 &&
              File(input['transcript_path'] as String).isAbsolute)
            'transcript_path': input['transcript_path'],
        }),
        flush: true,
      );
      await temporary.rename(target.path);
    } finally {
      await directory.delete();
    }
    final primary = filtered['five_hour'];
    final used = primary is Map ? primary['used_percentage'] : null;
    stdout.write(
      used is num && used.isFinite && used >= 0 && used <= 100
          ? 'Claude ${(100 - used).round()}% left'
          : 'Claude quota unavailable',
    );
  } on Object {
    // Status-line failures must not reveal input or disrupt the Claude session.
    stdout.write('Claude quota unavailable');
    exitCode = 1;
  }
}
