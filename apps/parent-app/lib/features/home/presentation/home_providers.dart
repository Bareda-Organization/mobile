import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';

// `myStudentsProvider`(§3.1)·`runsForStudentProvider`(§3.5)는 `schedule`
// feature 도 함께 쓰므로 `core/students`·`core/runs` 로 옮겼다 — 이 화면은
// `export` 로 그대로 재노출해 기존 import 경로(`home_providers.dart`)를
// 쓰는 위젯들을 고치지 않아도 되게 한다.
export 'package:parent_app/core/runs/presentation/run_providers.dart';
export 'package:parent_app/core/students/presentation/student_providers.dart';

/// 학생 계정 본인의 `student_id` — `GET /me` 의 `student_id` 필드(§2.10)를
/// 그대로 쓴다. 학생용 `/me/students` 대응 엔드포인트가 부재하므로 이 값이
/// 유일한 경로다.
final myStudentIdProvider = FutureProvider<String?>((ref) async {
  final me = await ref.watch(authRepositoryProvider).me();
  return me.studentId;
});

/// §3.12 — 알림 목록 1페이지(§1.8, 무한 스크롤 아님).
final notificationsProvider = FutureProvider<NotificationPage>((ref) {
  return ref.watch(notificationRepositoryProvider).getNotifications();
});
