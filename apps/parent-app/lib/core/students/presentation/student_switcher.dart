import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';

/// 자녀 전환 — 홈·지도·일정·노선이 같은 모양을 쓴다(`FEATURE_SPEC P-02` "자녀 2명 이상일 때만 노출").
///
/// 2~3명은 이름을 나란히 두고 한 번 눌러 바꾼다(고르는 창을 열고 닫는 두 번 누름이 아침마다 쌓였다).
/// 4명 이상은 이름이 좁아 [BaraedaSelect] 로 둔다.
class StudentSwitcher extends ConsumerWidget {
  const StudentSwitcher({
    required this.students,
    required this.selectedId,
    super.key,
  });

  /// 한 줄에 이름을 나란히 둘 수 있는 자녀 수의 상한.
  static const maxSegmentedCount = 3;

  final List<Student> students;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (students.length < 2) return const SizedBox.shrink();

    final control = students.length <= maxSegmentedCount
        ? BaraedaSegmentedControl(
            block: true,
            options: [
              for (final s in students)
                BaraedaSegmentedOption(s.studentId, label: s.name),
            ],
            value: selectedId,
            onChanged: (value) => selectStudent(ref, value),
          )
        : BaraedaSelect(
            label: '자녀 선택',
            value: selectedId,
            options: [
              for (final s in students)
                BaraedaSelectOption(s.studentId, label: s.name),
            ],
            onChanged: (value) {
              if (value != null) selectStudent(ref, value);
            },
          );
    return Semantics(
      label: '자녀 선택',
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
        child: control,
      ),
    );
  }
}
