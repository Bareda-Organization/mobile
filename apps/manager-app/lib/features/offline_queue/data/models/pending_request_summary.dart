/// 큐 화면(`offline_queue_screen.dart`)이 보여줄 대기 요청 한 건 — drift
/// 가 생성한 행 타입(`PendingRequest`)을 그대로 노출하지 않고 옮겨,
/// presentation 이 drift 를 직접 import 하지 않게 한다(CONVENTIONS_FLUTTER.md
/// §2 "presentation 이 data 구현 세부를 모른다").
class PendingRequestSummary {
  const PendingRequestSummary({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.createdAt,
  });

  final int id;
  final String endpoint;
  final String method;
  final DateTime createdAt;
}

/// `OfflineQueueRepository.replayPending` 결과 — 큐 화면이 "N건 처리, M건
/// 대기 중" 같은 안내에 쓴다.
class ReplayResult {
  const ReplayResult({
    required this.succeeded,
    required this.stillPending,
    required this.droppedPermanently,
  });

  /// 재전송이 2xx 로 끝나 큐에서 빠진 건수.
  final int succeeded;

  /// 여전히 네트워크 장애라 큐에 남은 건수.
  final int stillPending;

  /// 서버가 4xx 로 확정 거부해 재시도해도 성공할 수 없어 큐에서 뺀 건수
  /// (예: 그사이 회차가 종료돼 `RUN_NOT_MOVING` 등으로 굳어진 요청).
  final int droppedPermanently;
}
