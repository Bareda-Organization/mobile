import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R46 B — 기사가 운전하는 화면에는 알림 진입점을 두지 않는다. 운전 중 시선을
/// 뺏는 요소를 막는다. 알림은 아래 탭으로 열리고(`Ruling 857`) 동승자 명단(탭 안
/// 화면)에 알림 배지가 생겨도 허용이다(동승자는 운전하지 않는다) — 지금 명단
/// 코드가 알림을 참조하지 않아 아래 목록에 함께 둘 뿐이고, 배지를 넣을 때
/// `lib/features/roster` 를 목록에서 뺀다. 이 시험은 import 만 본다 — 화면이
/// 실제로 그리는 것은 `test/features/drive_mode/
/// drive_mode_no_notification_entry_test.dart` 가 고정한다(857).
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
