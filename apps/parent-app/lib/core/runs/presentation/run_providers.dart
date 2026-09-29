import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// §3.5 — 학생별 당일 회차. `home`(오늘 운행 표시) · `schedule`(변경 신청
/// 대상 회차 선택) 두 feature 가 함께 쓰므로 `core/` 에 둔다
/// (CONVENTIONS_FLUTTER.md §2).
///
/// 성공한 쓰기(§3.6) 뒤에는 `ref.invalidate` 로 이 provider 를 무효화해
/// 서버가 돌려준 최신 상태를 다시 받는다(C-10 — 낙관적 UI 금지).
// `FutureProvider.family` 의 반환형 `FutureProviderFamily<...>` 는
// `flutter_riverpod` 가 공개 API 로 export 하지 않는 내부 타입이라
// 명시할 수 없다(riverpod-3.4.3/lib/src/internals.dart 확인).
// ignore: specify_nonobvious_property_types
final runsForStudentProvider = FutureProvider.family<List<StudentRun>, String>((
  ref,
  studentId,
) {
  return ref.watch(runRepositoryProvider).getRuns(studentId);
});

/// §3.5 `?date=` — 학생별 **특정 날짜** 회차. 변경 신청이 오늘 말고 내일 회차도
/// 고를 수 있게 하는 조회다(R33 P1). 오늘 조회는 위 [runsForStudentProvider] 를 그대로 쓴다.
// ignore: specify_nonobvious_property_types
final runsForStudentOnProvider =
    FutureProvider.family<List<StudentRun>, (String studentId, DateTime date)>((
      ref,
      key,
    ) {
      return ref.watch(runRepositoryProvider).getRuns(key.$1, date: key.$2);
    });
