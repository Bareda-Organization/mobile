/// 알림 목록의 날짜·시각 표기 — **한국 시간(UTC+9)** 으로 센다. 기기 시간대가 달라도 서버의 날짜와 같아야 한다.
/// 서버 시각은 UTC 순간으로 들어오므로(R26) `toLocal()` 이 아니라 여기서 +9시간을 더한다.
library;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

DateTime _kst(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// 날짜 머리 — `오늘` · `어제` · `9월 28일(월)`. 해가 다르면 `2025년 12월 28일(일)`.
String dayHeader(DateTime sentAt, DateTime now) {
  final sent = _kst(sentAt);
  final today = _kst(now);
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(sent.year, sent.month, sent.day)).inDays;
  if (days == 0) return '오늘';
  if (days == 1) return '어제';
  final weekday = _weekdays[sent.weekday - 1];
  final date = '${sent.month}월 ${sent.day}일($weekday)';
  return sent.year == today.year ? date : '${sent.year}년 $date';
}

/// 행 오른쪽 시각 — 24시간제, 앞자리 0 없음. 예: `8:37` · `18:05`.
String clockLabel(DateTime sentAt) {
  final sent = _kst(sentAt);
  return '${sent.hour}:${sent.minute.toString().padLeft(2, '0')}';
}

/// 낭독용 시각 — `오전 8시 37분`. 정각은 분을 읽지 않는다.
String spokenClock(DateTime sentAt) {
  final sent = _kst(sentAt);
  final meridiem = sent.hour < 12 ? '오전' : '오후';
  final hour = sent.hour % 12 == 0 ? 12 : sent.hour % 12;
  return sent.minute == 0
      ? '$meridiem $hour시'
      : '$meridiem $hour시 ${sent.minute}분';
}
