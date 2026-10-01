import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 오프라인 큐 (M-06, API_SPEC §1.7 대상 ①승하차 처리 ②비상 발신).
///
/// 호출부는 실제 전송을 `send` 클로저로 넘긴다 — 이 repository 는 그 결과가
/// `NetworkFailure`(연결 실패·타임아웃)이거나 서버가 응답한 5xx(백엔드 재기동 중
/// 502·풀 고갈 500 — JSON 본문이면 `ApiFailure`, nginx HTML 이면 `UnknownFailure`)일
/// 때만 `payload` 를 큐에 쌓는다.
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

  /// 큐에 쌓인 요청을 순서대로 다시 보낸다. 부르는 곳 셋 —
  /// ①큐 화면의 수동 재시도 버튼 ②[sendOrQueue] (쓰기 한 건이 성공하기 직전)
  /// ③`OfflineQueueAutoSync` 의 주기 타이머. ②·③ 이 M-06 의 "복구 시 **자동**
  /// 동기화" 를 맡는다.
  ///
  /// 통신이 아직 두절이면 **첫 실패에서 멈춘다** — 남은 행마다 타임아웃을
  /// 되풀이할 이유가 없고, 중간 건만 성공하면 큐 안의 순서가 뒤집힌다.
  ///
  /// 서버가 5xx 로 응답한 머리 행은 시도 횟수를 센다(R46-FIXRT S-9) — 횟수나 나이
  /// 상한에 닿으면 영구 실패로 재생에서 빼고(행은 큐 화면에 남는다) 같은 재생에서
  /// 뒤 행을 이어 보낸다. 큐 머리의 한 행이 뒤를 영구히 막지 않게 하는 장치다.
  Future<ReplayResult> replayPending();

  /// 대기 중인 요청을 전부 버린다 — 로그아웃·세션 만료 때만 부른다. 큐에는 사용자 열이
  /// 없어 남겨 두면 다음 계정의 토큰으로 이전 계정의 처리가 재생된다(F06-02).
  Future<void> clear();

  /// 대기 요청 한 건을 큐에서 지운다 — 잘못 눌러 쌓인 처리를 사용자가 버릴 때 쓴다(F06-15).
  Future<void> cancel(int id);
}
