import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R46 B — 운행 중 화면(기사 운전 화면 · 동승자 명단)에는 알림 진입점을 두지 않는다. 운전 중 시선을 뺏는 요소를 막는다.
void main() {
  for (final dir in [
    'lib/features/drive_mode',
    'lib/features/roster',
  ]) {
    test('$dir 는 알림 화면·배지를 참조하지 않는다', () {
      final offenders = [
        for (final file in Directory(dir).listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('features/notifications/'))
            file.path,
      ];

      expect(offenders, isEmpty);
    });
  }
}
