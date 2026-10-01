import 'package:parent_app/core/routes/domain/route_detail.dart';

/// 화면이 보는 노선 상세 계약 — API_SPEC §3.10.
///
/// 메서드가 1개뿐이라 `one_member_abstracts` 가 걸리지만,
/// `student_repository.dart` 와 같은 이유로 최상위 함수로 바꾸지 않는다
/// (이 앱의 다른 repository 들과 같은 인터페이스+구현체 계층 구조 유지).
// ignore: one_member_abstracts
abstract interface class RouteRepository {
  /// `date`·`runId` 둘 다 선택값이다 — 생략하면 서버가 당일 다음 회차
  /// 기준으로 응답한다.
  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  });
}
