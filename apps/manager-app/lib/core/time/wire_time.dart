/// 서버로 보내는 시각 표기 — API_SPEC §1.1 "ISO-8601 + 오프셋".
///
/// `DateTime.now()` 는 기기 로컬 시각이라 그대로 `toIso8601String()` 하면
/// 오프셋이 빠진다 — UTC(`Z`)로 바꿔 같은 순간을 오프셋과 함께 낸다.
String toWireTime(DateTime time) => time.toUtc().toIso8601String();
