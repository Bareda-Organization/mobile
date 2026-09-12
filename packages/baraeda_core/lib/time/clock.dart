/// 위젯·유스케이스가 `DateTime.now()` 를 직접 호출하지 않도록 만드는 주입 지점.
///
/// 이 서비스의 중심축은 시간이다(운행 시작 가능 구간 판정 등) — 판정에 쓰는
/// "지금" 을 코드에서 고정해 버리면 실제 서비스에서 틀린 값을 낸다. 그래서
/// 시각을 얼리지 않고, 대신 "지금이 몇 시인지 묻는 방법" 하나만 주입 가능하게
/// 만든다. 테스트에서만 [Clock] 을 가짜 구현으로 바꿔 특정 시각을 고정한다.
abstract interface class Clock {
  /// 판정에 사용할 현재 시각.
  DateTime now();
}

/// 실제 벽시계를 그대로 반환하는 기본 구현. 운영 코드의 기본 주입 대상.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
