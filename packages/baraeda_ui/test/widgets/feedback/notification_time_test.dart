import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 한국 시간(UTC+9) 기준으로 그린다 — 기기 시간대가 달라도 서버의 날짜와 같아야 한다(R26).
void main() {
  // 2026-09-30 10:00 KST (수요일).
  final now = DateTime.utc(2026, 9, 30, 1);

  test('오늘 · 어제 · 그 전 날짜 머리', () {
    expect(
      dayHeader(DateTime.utc(2026, 9, 29, 23, 37), now),
      '오늘',
    ); // 9/30 08:37
    expect(dayHeader(DateTime.utc(2026, 9, 29, 5), now), '어제'); // 9/29 14:00
    expect(dayHeader(DateTime.utc(2026, 9, 28, 5), now), '9월 28일(월)');
  });

  test('해가 다르면 연도를 붙인다', () {
    expect(dayHeader(DateTime.utc(2025, 12, 28, 5), now), '2025년 12월 28일(일)');
  });

  test('날짜 경계는 한국 자정이다 — UTC 15:00 이 다음 날 0시', () {
    // 9/29 23:59 KST = 9/29 14:59 UTC → 어제, 9/30 00:00 KST = 9/29 15:00 UTC → 오늘.
    expect(dayHeader(DateTime.utc(2026, 9, 29, 14, 59), now), '어제');
    expect(dayHeader(DateTime.utc(2026, 9, 29, 15), now), '오늘');
  });

  test('시각 표기는 24시간제이고 앞자리 0 이 없다', () {
    expect(clockLabel(DateTime.utc(2026, 9, 29, 23, 37)), '8:37');
    expect(clockLabel(DateTime.utc(2026, 9, 30, 9, 5)), '18:05');
  });

  test('낭독용 시각은 오전·오후로 읽는다', () {
    expect(spokenClock(DateTime.utc(2026, 9, 29, 23, 37)), '오전 8시 37분');
    expect(spokenClock(DateTime.utc(2026, 9, 30, 9, 5)), '오후 6시 5분');
    expect(
      spokenClock(DateTime.utc(2026, 9, 30, 3)),
      '오후 12시',
    ); // 정각은 분을 읽지 않는다
    expect(spokenClock(DateTime.utc(2026, 9, 29, 15)), '오전 12시'); // 0시
  });
}
