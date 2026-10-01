import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/data/selected_student_storage.dart';
import 'package:parent_app/core/students/domain/student.dart';

/// 학부모가 화면 상단에서 고른 자녀. `home`·`schedule` 두 feature 가 함께
/// 참조하므로 `core/` 에 둔다(§3.1 "자녀 선택 UI 는 2명 이상일 때만 노출").
///
/// 학생 역할은 이 provider 를 쓰지 않는다 — 본인 `student_id` 는
/// `myStudentIdProvider`(`features/home`) 로 얻는다.
final selectedStudentIdProvider = StateProvider<String?>((ref) {
  // F05-01 — 계정이 바뀌면 앞 계정에서 고른 자녀를 버린다.
  ref.watch(currentUserRoleProvider);
  return null;
});

/// 기기에 기억해 둔 마지막 선택 저장소 — 시험이 메모리 대역으로 바꾼다.
final selectedStudentStorageProvider = Provider<SelectedStudentStorage>(
  (ref) => SelectedStudentStorage(),
);

/// 앱을 다시 켰을 때 되살릴 마지막 선택. 계정이 바뀌면 다시 읽는다.
final savedStudentIdProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserRoleProvider);
  return ref.watch(selectedStudentStorageProvider).read();
});

/// 지금 화면이 보여 줄 자녀 — 이번 실행에서 고른 자녀 → 기억해 둔 자녀 → 첫 자녀 순이다.
/// 연결이 끊겼거나 다른 계정에서 기억한 식별자는 목록에 없으므로 버린다.
String pickStudentId(
  List<Student> students, {
  String? picked,
  String? saved,
}) {
  final ids = {for (final student in students) student.studentId};
  for (final candidate in [picked, saved]) {
    if (candidate != null && ids.contains(candidate)) return candidate;
  }
  return students.first.studentId;
}

/// 화면이 자녀를 고르는 공용 진입 — 네 화면(홈·지도·일정·노선)이 같은 선택을 본다.
String watchSelectedStudentId(WidgetRef ref, List<Student> students) =>
    pickStudentId(
      students,
      picked: ref.watch(selectedStudentIdProvider),
      saved: ref.watch(savedStudentIdProvider).value,
    );

/// 자녀를 바꾼다 — 이번 실행의 선택을 바꾸고 기기에도 기억한다.
void selectStudent(WidgetRef ref, String studentId) {
  ref.read(selectedStudentIdProvider.notifier).state = studentId;
  unawaited(ref.read(selectedStudentStorageProvider).save(studentId));
}
