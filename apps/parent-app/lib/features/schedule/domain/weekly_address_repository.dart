import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';

/// 화면이 보는 요일별 주소 계약 — §3.7.
abstract interface class WeeklyAddressRepository {
  /// GET §3.7 — 설정 화면 초기 조회.
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId);

  /// PATCH §3.7 — 검증 실패 시 `Failure.api(code: 'ADDRESS_VERIFICATION_FAILED')`
  /// 를 던지며 저장은 보류된다(서버가 저장하지 않으므로 응답도 없다).
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  );
}
