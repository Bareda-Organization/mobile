import 'package:flutter_riverpod/legacy.dart';

/// 학부모가 화면 상단에서 고른 자녀. `home`·`schedule` 두 feature 가 함께
/// 참조하므로 `core/` 에 둔다(§3.1 "자녀 선택 UI 는 2명 이상일 때만 노출").
///
/// 학생 역할은 이 provider 를 쓰지 않는다 — 본인 `student_id` 는
/// `myStudentIdProvider`(`features/home`) 로 얻는다.
final selectedStudentIdProvider = StateProvider<String?>((ref) => null);
