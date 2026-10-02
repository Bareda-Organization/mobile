import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';

/// §4.13 현장 상황 보고 — 기사·동승자 둘 다 가능(§4.6·§4.9 처럼 역할이
/// 갈리지 않는다. role_policy.dart 에 별도 capability 를 두지 않은 이유).
// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과
// 맞추려 인터페이스로 둔다(CONVENTIONS_FLUTTER.md §2, RosterRepository 등
// 여러 메서드짜리와 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
abstract interface class ReportsRepository {
  Future<ReportResult> submitReport({
    required String runId,
    required ReportRequest request,
  });
}
