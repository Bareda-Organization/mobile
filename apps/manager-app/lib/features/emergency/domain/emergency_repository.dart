import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// §4.14(발신·취소)·§4.15(목록) — 기사·동승자 둘 다 호출 가능(역할 제한
/// 없음, `role_policy.dart` 에 게이트를 두지 않는 이유).
///
/// `raise` 만 `SendOutcome` 을 감싼다 — §1.7 멱등 대상 ②라 오프라인 큐를
/// 거칠 수 있다. `cancel`·`fetchList` 는 §1.7 대상이 아니라 그대로
/// `Future<T>` 다.
abstract interface class EmergencyRepository {
  Future<SendOutcome<EmergencyRaiseResult>> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  });

  Future<void> cancel({required String runId, required String emergencyId});

  Future<EmergencyListResponse> fetchList({required String runId});
}
