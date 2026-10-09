import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';

/// 이름 칩으로 나란히 보여 주는 자녀 수의 끝 — 이보다 많으면 고르는 창이다.
const _chipLimit = 3;

/// 자녀 전환 — 홈·지도·일정·노선이 같은 모양을 쓴다(`FEATURE_SPEC P-02` "자녀 2명 이상일 때만 노출").
///
/// 이름 앞에 첫 글자 동그라미를 단 알약이 가로로 이어지고, 한 번 눌러 바꾼다(R48 시안 `.m-pill`).
/// 알약은 이름이 길면 그 칸만 `…` 로 줄고, **4명 이상이면 알약 대신 고르는 창(드롭다운) 하나**다.
class StudentSwitcher extends ConsumerWidget {
  const new({required this.students, required this.selectedId, super.key});

  final List<Student> students;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (students.length < 2) return const SizedBox.shrink();

    // 4명 이상은 칩이 좁아져 고르는 창(드롭다운)으로 바꾼다(UF-P-02, frontend `Ruling 472`).
    if (students.length >= _chipLimit + 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
        child: BaraedaSelect(
          label: '자녀 선택',
          value: selectedId,
          options: [
            for (final student in students)
              BaraedaSelectOption(student.studentId, label: student.name),
          ],
          onChanged: (id) {
            if (id != null) selectStudent(ref, id);
          },
        ),
      );
    }

    return Semantics(
      label: '자녀 선택',
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final student in students) ...[
                if (student != students.first)
                  const SizedBox(width: BaraedaSpacing.space2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: BaraedaFilterPill(
                    label: student.name,
                    selected: student.studentId == selectedId,
                    leading: _Initial(
                      name: student.name,
                      selected: student.studentId == selectedId,
                    ),
                    onTap: () => selectStudent(ref, student.studentId),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 이름 첫 글자를 담은 지름 28 동그라미 — 선택되면 흰 면, 아니면 연한 회색 면.
class _Initial extends StatelessWidget {
  const new({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? colors.surfaceCard : colors.statusIdleSoft,
        ),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Text(
              name.isEmpty ? '' : name.characters.first,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textPrimary,
                fontWeight: BaraedaFontWeight.bold,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
