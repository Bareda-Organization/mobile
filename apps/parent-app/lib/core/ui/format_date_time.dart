import 'package:intl/intl.dart';

/// 화면에 보이는 날짜·시각 — `9월 12일 07:30`. 서버가 주는 시각은 UTC 순간이라 기기 표준시로 옮긴 뒤 쓴다.
///
/// `DateTime` 을 문자열에 그대로 넣으면 `2026-09-12 07:30:00.000Z` 가 화면에 나온다.
String formatDateTime(DateTime time) =>
    DateFormat('M월 d일 HH:mm').format(time.toLocal());

/// 승인 마감 안내 꼬리말 — ` (마감 9월 12일 07:30)`. 서버가 마감을 안 주면 빈 문자열.
String deadlineNote(DateTime? deadline) =>
    deadline == null ? '' : ' (마감 ${formatDateTime(deadline)})';

/// 남은 시간 문구 — `1시간 20분` · `30분` · `1분 미만`. 분 단위로 내림하며 0 이하는 `1분 미만` 으로 본다.
String formatRemaining(Duration left) {
  if (left.inMinutes < 1) return '1분 미만';
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}
