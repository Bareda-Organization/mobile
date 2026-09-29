/// 운행 날짜는 **한국 시간(UTC+9)** 달력으로 센다 — 기기 시간대가 달라도 서버의 운행일과 같아야 한다.
/// 돌려주는 값은 날짜만 의미가 있고(년·월·일), 시각은 0시다.
DateTime koreaServiceDate(DateTime now, {int plusDays = 0}) {
  final kst = now.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(kst.year, kst.month, kst.day + plusDays);
}
