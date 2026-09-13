import 'package:baraeda_core/id/as_id_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asIdString', () {
    test('JSON 정수(Long)를 문자열로 흡수한다 — Ruling 275', () {
      // WebSocketEnvelope.runId 가 실제로 내보내는 형태 (Long, 따옴표 없음).
      expect(asIdString(42), '42');
    });

    test('이미 문자열인 값은 그대로 통과시킨다', () {
      expect(asIdString('42'), '42');
    });

    test('큰 정수도 정밀도 손실 없이 흡수한다', () {
      expect(asIdString(9007199254740993), '9007199254740993');
    });
  });
}
