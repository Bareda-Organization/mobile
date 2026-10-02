/// §4.2.1 보호자 전화 원번호 단건 조회(Ruling 482·521) — 명단은 마스킹(L2)이라 걸 수 없고, 매니저가
/// [전화] 를 누를 때만 그 탑승자 1명의 원번호를 받는다. 번호는 `tel:` 을 여는 데만 쓰고 화면에 싣지 않는다.
abstract interface class GuardianPhoneRepository {
  /// 연결된 보호자가 없으면 `null`.
  Future<String?> fetchGuardianPhone({
    required String runId,
    required String riderId,
  });
}
