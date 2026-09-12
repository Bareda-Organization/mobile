/// 위젯이 `DateTime.now()` 를 직접 부르지 않게 하는 시각 주입점
/// (CONVENTIONS_FLUTTER.md §9). 이 서비스의 중심축이 시간이라, 시험에서
/// 시각을 고정할 수 없으면 검증이 불가능하다.
///
/// ⚠ [SystemClock] 은 항상 실 시각을 반환한다 — 여기서 시각을 고정하지
/// 않는다. 운행 시작 30분 전 판정 같은 로직은 실제로 흐르는 시간에
/// 의존하므로, 이 주입점의 목적은 프로덕션 동작을 바꾸는 것이 아니라
/// 시험에서만 고정 시각으로 치환할 수 있게 하는 것이다.
///
/// 메서드가 1개뿐이라 `one_member_abstracts` 가 걸리지만, `TokenStorage` 등
/// 이 패키지의 다른 인터페이스와 같은 형태로 Riverpod `Provider` 에 배선해
/// 시험에서 가짜 구현으로 바꿔 끼우기 위해 최상위 함수로 바꾸지 않는다.
// ignore: one_member_abstracts
abstract class Clock {
  /// 현재 시각. 프로덕션에서는 [SystemClock] 이 `DateTime.now()` 를,
  /// 시험에서는 고정 시각을 반환하는 가짜 구현을 넣는다.
  DateTime now();
}

/// 실 시각을 반환하는 기본 구현 — 프로덕션에서 유일하게 쓰는 구현체다.
class SystemClock implements Clock {
  /// 상수 생성자 — 상태가 없어 인스턴스를 몇 개 만들어도 차이가 없다.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
