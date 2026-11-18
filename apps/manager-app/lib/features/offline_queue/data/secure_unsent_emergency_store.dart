import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:manager_app/features/offline_queue/domain/unsent_emergency_store.dart';

/// 기본 구현 — `flutter_secure_storage`(Keychain · EncryptedSharedPreferences).
class SecureUnsentEmergencyStore implements UnsentEmergencyStore {
  const new({this.key = emergencyKey});

  /// 비상 신고 안내가 쓰는 키.
  static const emergencyKey = 'baraeda_manager_unsent_emergency';

  /// 승하차·도착 거절 안내가 쓰는 키(Ruling 892) — 같은 저장 수단에 키만 다르다.
  static const droppedKey = 'baraeda_manager_dropped_requests';

  final String key;

  SecureSlot get _slot => SecureSlot(key);

  /// 저장소를 읽지 못하면 예외를 그대로 낸다 — "남긴 안내 없음" 과 "읽지 못함" 을 구분해야, 읽기에 실패한 채로 새 건을
  /// 쓰다 앞 건수를 덮지 않는다. 모양이 틀린 값은 되살릴 수 없으니 "없음" 이다.
  @override
  Future<UnsentEmergency?> read() async {
    final raw = await _slot.read(strict: true);
    if (raw == null) return null;
    try {
      return UnsentEmergency.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  // 저장 실패여도 이번 실행 동안은 메모리 안내가 남는다.
  @override
  Future<void> write(UnsentEmergency value) =>
      _slot.write(jsonEncode(value.toJson()));

  // 지우지 못하면 다음 실행에 안내가 다시 보일 뿐이다.
  @override
  Future<void> clear() => _slot.delete();
}
