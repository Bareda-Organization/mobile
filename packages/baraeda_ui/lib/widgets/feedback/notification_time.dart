/// 알림 목록의 날짜·시각 표기 — **한국 시간(UTC+9)** 으로 센다. 기기 시간대가 달라도 서버의 날짜와 같아야 한다.
/// 서버 시각은 UTC 순간으로 들어오므로(R26) `toLocal()` 이 아니라 여기서 +9시간을 더한다.
library;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

DateTime _kst(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// 한국 날짜로 [sentAt] 이 [now] 보다 며칠 전인가(오늘이면 0). UTC 날짜가 아니라 서울 날짜로 센다.
int _daysAgo(DateTime sentAt, DateTime now) {
  final sent = _kst(sentAt);
  final today = _kst(now);
  return DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(sent.year, sent.month, sent.day)).inDays;
}

/// 날짜 머리 — `오늘` · `어제` · `9월 28일(월)`. 해가 다르면 `2025년 12월 28일(일)`.
String dayHeader(DateTime sentAt, DateTime now) {
  final sent = _kst(sentAt);
  final today = _kst(now);
  final days = _daysAgo(sentAt, now);
  if (days == 0) return '오늘';
  if (days == 1) return '어제';
  final weekday = _weekdays[sent.weekday - 1];
  final date = '${sent.month}월 ${sent.day}일($weekday)';
  return sent.year == today.year ? date : '${sent.year}년 $date';
}

/// 날짜 머리 오른쪽의 날짜(시안 `오늘 · 10월 3일 (토)`) — `오늘` 은 요일까지, `어제` 는 날짜만.
/// 그 밖의 날은 머리 자체가 날짜라 오른쪽에 덧붙일 것이 없다(`null`).
String? dayHeaderDate(DateTime sentAt, DateTime now) {
  final header = dayHeader(sentAt, now);
  final sent = _kst(sentAt);
  final date = '${sent.month}월 ${sent.day}일';
  return switch (header) {
    '오늘' => '$date (${_weekdays[sent.weekday - 1]})',
    '어제' => date,
    _ => null,
  };
}

/// 행 오른쪽 시각 — 24시간제, 앞자리 0 없음. 예: `8:37` · `18:05`.
String clockLabel(DateTime sentAt) {
  final sent = _kst(sentAt);
  return '${sent.hour}:${sent.minute.toString().padLeft(2, '0')}';
}

/// 알림 행의 시각 — 오늘이면 [clockLabel] 그대로, 오늘이 아니면 날짜를 앞에 붙인다
/// (`10월 2일 17:48`). 서버가 보관하는 14일 안이라 해는 붙이지 않는다.
String timeLabel(DateTime sentAt, DateTime now) {
  if (_daysAgo(sentAt, now) == 0) return clockLabel(sentAt);
  final sent = _kst(sentAt);
  return '${sent.month}월 ${sent.day}일 ${clockLabel(sentAt)}';
}

/// [timeLabel] 의 낭독용 — 오늘이 아니면 `10월 2일 오후 5시 48분`.
String spokenTime(DateTime sentAt, DateTime now) {
  if (_daysAgo(sentAt, now) == 0) return spokenClock(sentAt);
  final sent = _kst(sentAt);
  return '${sent.month}월 ${sent.day}일 ${spokenClock(sentAt)}';
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
