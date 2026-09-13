import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 오프라인 큐 (M-06, API_SPEC §1.7 대상 ①승하차 처리 ②비상 발신).
///
/// 호출부는 실제 전송을 `send` 클로저로 넘긴다 — 이 repository 는 그 결과가
/// `NetworkFailure`(연결 실패·타임아웃)일 때만 `payload` 를 큐에 쌓는다.
/// `payload` 에는 이미 `client_key` 가 필드로 들어 있어야 한다(즉시 전송과
/// 재생이 같은 멱등키를 쓰기 위함 — 지시서의 명시적 경고 사항). 이 값이
/// 멱등성의 유일한 정본이라 별도 파라미터로 다시 받지 않는다(FE-R2 목표 11).
abstract interface class OfflineQueueRepository {
  Future<SendOutcome<T>> sendOrQueue<T>({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
  });

  /// 큐 화면이 진입 시 보여줄 대기 목록.
  Future<List<PendingRequestSummary>> fetchPending();

  /// 큐 화면의 수동 재시도 버튼이 부르는 재생 — 네트워크가 돌아왔다고
  /// 사용자가 판단했을 때만 실행한다(자동 폴링은 이번 범위 밖, WS 도입
  /// 이후 F4 몫).
  Future<ReplayResult> replayPending();
}
