import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';

// `myStudentsProvider`(§3.1)·`runsForStudentProvider`(§3.5)는 `schedule`
// feature 도 함께 쓰므로 `core/students`·`core/runs` 로 옮겼다 — 이 화면은
// `export` 로 그대로 재노출해 기존 import 경로(`home_providers.dart`)를
// 쓰는 위젯들을 고치지 않아도 되게 한다. `changeRequestsProvider`(§3.9)도
// 같은 이유로 `core/change_requests` 에 있으나(P-06 "홈에 처리 대기
// 건수 배지"), 그 provider 는 `widgets/pending_change_badge.dart` 가
// 직접 import 하므로 여기서는 재노출하지 않는다.
export 'package:parent_app/core/runs/presentation/run_providers.dart';
export 'package:parent_app/core/students/presentation/student_providers.dart';

/// 알림 목록에서 한 번에 받는 건수 — [더 보기] 가 [notificationPageStep] 씩 늘린다(F05-08).
/// 서버 한도가 100건(§1.8)이라 [notificationPageMax] 를 넘기지 않는다.
const int notificationPageStep = 20;
const int notificationPageMax = 100;

final StateProvider<int> notificationPageSizeProvider = StateProvider<int>((
  ref,
) {
  ref.watch(currentUserRoleProvider); // 계정이 바뀌면 처음 크기로
  return notificationPageStep;
});

/// §3.12 — 알림 목록. 첫 페이지(`page=0`)를 [notificationPageSizeProvider] 건수만큼 받는다.
final notificationsProvider = FutureProvider<NotificationPage>((ref) {
  // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
  ref.watch(currentUserRoleProvider);
  final size = ref.watch(notificationPageSizeProvider);
  return ref.watch(notificationRepositoryProvider).getNotifications(size: size);
});
