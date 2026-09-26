import 'package:wakelock_plus/wakelock_plus.dart';

/// 화면 꺼짐 방지 포트 — F2. 백그라운드 위치 송신은 범위 밖이라(M-B 2항),
/// 운행 화면이 켜져 있는 것이 지금 GPS 송신을 지키는 유일한 수단이다.
///
/// 기본 구현은 [WakelockPlusPort](`wakelock_plus` 플러그인, `di.dart` 조립
/// 지점)다. 시험은 이 포트를 가짜로 덮어(`PositionSource` 와 같은 방식)
/// 실제 플랫폼 호출 없이 켜기·끄기 호출 횟수만 확인한다.
abstract interface class WakelockPort {
  /// 화면이 꺼지지 않게 한다 — 운행 화면 진입 시.
  Future<void> enable();

  /// 화면 꺼짐 방지를 해제한다 — 운행 화면을 떠날 때.
  Future<void> disable();
}

/// `wakelock_plus` 플러그인으로 실제 화면 꺼짐 방지를 켜고 끈다(F2).
class WakelockPlusPort implements WakelockPort {
  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
