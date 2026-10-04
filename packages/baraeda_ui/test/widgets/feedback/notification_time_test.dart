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

  group('행 시각 — 오늘이 아니면 날짜를 붙인다(Ruling 835)', () {
    test('오늘 알림은 시각만, 어제 이전 알림은 `10월 2일 17:48` 처럼 날짜와 함께', () {
      // 2026-10-03 12:00 KST.
      final today = DateTime.utc(2026, 10, 3, 3);

      expect(timeLabel(DateTime.utc(2026, 10, 2, 23, 37), today), '8:37');
      expect(
        timeLabel(DateTime.utc(2026, 10, 2, 8, 48), today),
        '10월 2일 17:48',
      );
      expect(timeLabel(DateTime.utc(2026, 9, 28, 5, 5), today), '9월 28일 14:05');
    });

    // 웹 `ManagerList` 시험이 UTC 날짜로 "오늘" 을 가려 서울 자정~오전 9시에 틀렸던 사고(R48)의 앱 쪽 방어.
    test('서울 자정~오전 9시에도 오늘 판정이 서울 날짜를 따른다 — UTC 날짜가 달라도', () {
      // 지금 10-04 00:10 KST(= 10-03 15:10 UTC)
      // 알림 10-04 00:05 KST(= 10-03 15:05 UTC):
      // UTC 날짜는 둘 다 10-03 이고 서울로도 같은 날 → 오늘.
      final justAfterMidnight = DateTime.utc(2026, 10, 3, 15, 10);
      expect(
        timeLabel(DateTime.utc(2026, 10, 3, 15, 5), justAfterMidnight),
        '0:05',
      );

      // 지금 10-04 08:30 KST(= 10-03 23:30 UTC)
      // 알림 10-03 23:50 KST(= 10-03 14:50 UTC):
      // UTC 날짜는 둘 다 10-03 이지만 서울로는 어제 → 날짜가 붙어야 한다.
      final morning = DateTime.utc(2026, 10, 3, 23, 30);
      expect(
        timeLabel(DateTime.utc(2026, 10, 3, 14, 50), morning),
        '10월 3일 23:50',
      );

      // 지금 10-04 09:10 KST(= 10-04 00:10 UTC)
      // 알림 10-04 00:30 KST(= 10-03 15:30 UTC):
      // UTC 날짜는 서로 다르지만 서울로는 같은 날 → 오늘(날짜 없음).
      final nineAm = DateTime.utc(2026, 10, 4, 0, 10);
      expect(timeLabel(DateTime.utc(2026, 10, 3, 15, 30), nineAm), '0:30');
    });

    test('날짜 머리가 `오늘` 인 알림만 시각에 날짜가 없다', () {
      final now = DateTime.utc(2026, 10, 3, 16, 20); // 10-04 01:20 KST
      for (final hoursAgo in [0, 1, 2, 9, 10, 25, 30, 49, 24 * 13]) {
        final sentAt = now.subtract(Duration(hours: hoursAgo));
        expect(
          timeLabel(sentAt, now).contains('월'),
          dayHeader(sentAt, now) != '오늘',
          reason: '$hoursAgo 시간 전',
        );
      }
    });

    test('낭독도 오늘이 아니면 날짜를 먼저 읽는다', () {
      final today = DateTime.utc(2026, 10, 3, 3);

      expect(spokenTime(DateTime.utc(2026, 10, 2, 23, 37), today), '오전 8시 37분');
      expect(
        spokenTime(DateTime.utc(2026, 10, 2, 8, 48), today),
        '10월 2일 오후 5시 48분',
      );
    });
  });
}
