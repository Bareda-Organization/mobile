import 'package:parent_app/features/live_map/domain/bus_position.dart';

/// 화면이 보는 §3.11 계약 — 메서드가 1개뿐이라 `one_member_abstracts` 가
/// 걸리지만, `route_repository.dart` 와 같은 이유로 최상위 함수로 바꾸지
/// 않는다(이 앱의 다른 repository 들과 같은 인터페이스+구현체 계층 유지).
// ignore: one_member_abstracts
abstract interface class BusPositionRepository {
  Future<BusPosition> getBusPosition(String studentId);
}
