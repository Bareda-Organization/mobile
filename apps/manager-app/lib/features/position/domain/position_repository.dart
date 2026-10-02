import 'package:manager_app/features/position/data/models/position_request.dart';

/// §4.12 위치 업로드(LOC-01) — 기사 전용, `run_status=moving` 에서만.
///
/// 응답이 `204`(본문 없음)라 반환 타입이 `void` 다 — §1.9 는 "쓰기 응답은
/// 변경 후 자원 상태를 반환" 이라고 하지만 이 엔드포인트는 그 원칙의
/// 예외로 정본이 명시적으로 `204` 만 규정한다.
abstract interface class PositionRepository {
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  });
}
