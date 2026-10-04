import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 명단의 보호자 번호는 마스킹이라 걸 수 없다 — [전화] 를 누른 순간 그 학생 1명의 원번호를
/// 서버에서 받아 `tel:` 로 연다(Ruling 482). 원번호는 화면에 싣지 않고 바로 전화 앱에 넘긴다.
/// 걸었으면 `null`, 못 걸었으면 화면에 보일 이유를 돌려준다. 명단 화면과 미승차 연락 화면이 같이 쓴다.
Future<String?> callGuardian(
  WidgetRef ref, {
  required String runId,
  required String riderId,
}) async {
  try {
    final phone = await ref
        .read(guardianPhoneRepositoryProvider)
        .fetchGuardianPhone(runId: runId, riderId: riderId);
    if (phone == null || phone.trim().isEmpty) {
      return '등록된 보호자 연락처가 없어요';
    }
    final opened = await ref.read(uriOpenerProvider)(
      Uri(scheme: 'tel', path: phone.trim()),
    );
    return opened ? null : '전화 앱을 열지 못했어요';
  } on Failure catch (failure) {
    return '보호자 번호를 가져오지 못했어요 — ${describeFailure(failure)}';
  }
}

/// 미승차 연락 기록(§4.8)을 보낸다. 성공하면 명단을 다시 받고 `null`, 실패하면 이유를 돌려준다.
/// 다른 사람이 미승차를 되돌렸다면(`NO_SHOW_CASE_NOT_FOUND`) 이 화면의 명단이 낡았으니 그때도 다시 받는다(Z-05).
Future<String?> submitNoShowContact(
  ProviderContainer container, {
  required String runId,
  required String riderId,
  required NoShowContactRequest request,
}) async {
  try {
    await container
        .read(rosterRepositoryProvider)
        .recordNoShowContact(runId: runId, riderId: riderId, request: request);
    container.invalidate(rosterProvider);
    return null;
  } on Failure catch (failure) {
    if (failure case ApiFailure(code: 'NO_SHOW_CASE_NOT_FOUND')) {
      container.invalidate(rosterProvider);
    }
    return describeFailure(failure);
  }
}
