import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/domain/student.dart';

/// §3.1 — 학부모의 연결 자녀 목록. `home`·`schedule` 두 feature 가 학생
/// 선택 UI 에 함께 쓰므로 `core/` 에 둔다(CONVENTIONS_FLUTTER.md §2).
/// 학생 계정은 이 provider 를 쓰지 않는다("권한 학부모" — 호출하면 403).
final myStudentsProvider = FutureProvider<List<Student>>((ref) {
  // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
  ref.watch(currentUserRoleProvider);
  return ref.watch(studentRepositoryProvider).getMyStudents();
});

/// 학생 계정 본인의 `student_id` — `GET /me` 의 `student_id` 필드(§2.10)를
/// 그대로 쓴다. 학생용 `/me/students` 대응 엔드포인트가 부재하므로 이 값이 유일한 경로다.
/// 홈·노선·지도 세 화면이 함께 쓰므로 `core/` 에 둔다(F05-12).
final myStudentIdProvider = FutureProvider<String?>((ref) async {
  // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
  ref.watch(currentUserRoleProvider);
  final me = await ref.watch(authRepositoryProvider).me();
  return me.studentId;
});
