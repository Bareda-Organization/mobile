import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';

/// §4.9 지연 알림 — 동승자 전용(role_policy.dart `canSendDelayNotification`).
// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과
// 맞추려 인터페이스로 둔다(CONVENTIONS_FLUTTER.md §2, RosterRepository 등
// 여러 메서드짜리와 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
abstract interface class DelayRepository {
  Future<DelayResult> sendDelay({
    required String runId,
    required DelayRequest request,
  });
}
