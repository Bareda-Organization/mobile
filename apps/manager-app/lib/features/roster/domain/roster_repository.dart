import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// §4.2 명단 조회(기사·동승자) + §4.6·§4.7·§4.8 개인별 처리(동승자 전용,
/// role_policy.dart `canDecideBoardingStatus`). 조회는 두 역할 다 하지만
/// 쓰기 3종은 화면이 `canDecideBoardingStatus` 로 버튼 자체를 숨긴다.
abstract interface class RosterRepository {
  Future<RosterResponse> fetchRoster(String runId);

  Future<RiderUpdateResult> updateRiderStatus({
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
}
