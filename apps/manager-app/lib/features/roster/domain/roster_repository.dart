import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// §4.2 명단 조회(기사·동승자) + §4.6·§4.7·§4.8 개인별 처리(동승자 전용,
/// role_policy.dart `canDecideBoardingStatus`) + §4.11 변경 확인(기사·동승자
/// 둘 다 호출 가능). 조회는 두 역할 다 하지만 쓰기 3종은 화면이
/// `canDecideBoardingStatus` 로 버튼 자체를 숨긴다.
abstract interface class RosterRepository {
  Future<RosterResponse> fetchRoster(String runId);

  /// §4.6 승하차 상태 갱신 — §1.7 M-06 오프라인 큐 대상(UF-E-07 "동승자
  /// 승하차 처리" 가 그 예시로 명시된 항목). 통신 두절이면 [Queued] 로
  /// 돌아오고, 호출부가 넘긴 `request.clientKey` 가 즉시 전송·재생 양쪽에
  /// 그대로 쓰여 서버 쪽 중복 처리를 막는다.
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  });

  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  });

  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  });

  /// §4.11 `POST /runs/{runId}/ack-changes` — `changeIds` 를 생략하면
  /// 전건 확인(정본 문구).
  Future<AckChangesResult> ackChanges({
    required String runId,
    List<String>? changeIds,
  });
}
