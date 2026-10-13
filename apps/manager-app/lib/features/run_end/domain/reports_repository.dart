import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';

/// §4.13 현장 상황 보고 — 기사·동승자 둘 다 가능(§4.6·§4.9 처럼 역할이
/// 갈리지 않는다. role_policy.dart 에 별도 capability 를 두지 않은 이유).
// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과
// 맞추려 인터페이스로 둔다(CONVENTIONS_FLUTTER.md §2, RosterRepository 등
// 여러 메서드짜리와 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
///
/// §1.7 오프라인 큐 대상이다(R56 · Ruling 894 ⑧) — 통신 두절이면 [Queued] 로 돌아오고,
/// 호출부가 넘긴 `request.clientKey` 가 즉시 전송·재생 양쪽에 그대로 쓰여 서버 쪽 중복 처리를 막는다.
/// 보호자 부재 같은 안전 관련 보고가 통신 두절 구간에서 사라지지 않게 하는 장치다.
abstract interface class ReportsRepository {
  Future<SendOutcome<ReportResult>> submitReport({
    required String runId,
    required ReportRequest request,
  });
}
