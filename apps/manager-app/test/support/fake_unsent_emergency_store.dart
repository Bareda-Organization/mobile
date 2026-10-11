import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';

/// [UnsentEmergencyStore] 의 메모리 대역 — 시험에는 `flutter_secure_storage` 플랫폼 채널이 없다.
/// 컨테이너를 새로 만들어도(앱 재시작) 같은 대역을 넘기면 값이 남는다.
class FakeUnsentEmergencyStore implements UnsentEmergencyStore {
  new([this.saved]);

  UnsentEmergency? saved;

  @override
  Future<UnsentEmergency?> read() async => saved;

  @override
  Future<void> write(UnsentEmergency value) async => saved = value;

  @override
  Future<void> clear() async => saved = null;
}
