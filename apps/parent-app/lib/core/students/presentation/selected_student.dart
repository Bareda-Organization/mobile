import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/core/auth/auth_providers.dart';

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
