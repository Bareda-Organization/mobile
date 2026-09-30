// `myStudentsProvider`(§3.1)·`runsForStudentProvider`(§3.5)는 `schedule`
// feature 도 함께 쓰므로 `core/students`·`core/runs` 로 옮겼다 — 이 화면은
// `export` 로 그대로 재노출해 기존 import 경로(`home_providers.dart`)를
// 쓰는 위젯들을 고치지 않아도 되게 한다. `changeRequestsProvider`(§3.9)도
// 같은 이유로 `core/change_requests` 에 있으나(P-06 "홈에 처리 대기
// 건수 배지"), 그 provider 는 `widgets/pending_change_badge.dart` 가
// 직접 import 하므로 여기서는 재노출하지 않는다.
//
// 알림 목록 provider 는 R44 에서 `features/notifications` 로 옮겼다 — 홈은 알림을 보여주지 않는다.
export 'package:parent_app/core/runs/presentation/run_providers.dart';
export 'package:parent_app/core/students/presentation/student_providers.dart';
