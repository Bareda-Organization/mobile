import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/students/domain/student.dart';

/// 연결 완료 화면(시안 `child-link--done`) — "○○ 연결이 끝났어요" + 지금 연결된 자녀 목록.
///
/// 자녀가 여럿이면 코드를 한 번씩 반복해 입력하므로(다자녀) 목록에서 방금 연결한 자녀를 가려 보여 준다.
/// 목록을 아직 못 받았거나 못 받았다면 방금 연결한 자녀 하나만 보인다 — 연결은 이미 끝난 일이다.
class LinkDoneView extends StatelessWidget {
  const new({
    required this.justLinkedId,
    required this.justLinkedName,
    required this.students,
    super.key,
  });

  final String justLinkedId;
  final String justLinkedName;

  /// 서버가 돌려준 지금 연결된 자녀 전체. 못 받았으면 빈 목록.
  final List<Student> students;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 서버 목록에 방금 연결한 자녀가 아직 없으면(받아 오는 사이) 우리가 아는 이름으로 더한다.
    final rows = students.any((s) => s.studentId == justLinkedId)
        ? students
        : [
            ...students,
            Student(
              studentId: justLinkedId,
              name: justLinkedName,
              linkedAt: DateTime.now(),
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BaraedaSpacing.space10),
        Center(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accentPrimarySoft,
              ),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: BaraedaIcon(
                    'circle-check',
                    size: 32,
                    color: colors.accentPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        Text(
          '$justLinkedName 연결이 끝났어요',
          textAlign: TextAlign.center,
          style: BaraedaTypography.h3,
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        WordWrapText(
          '이제 $justLinkedName의 버스 위치와 알림을 볼 수 있어요.',
          textAlign: TextAlign.center,
          style: BaraedaTypography.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: BaraedaSpacing.space6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(BaraedaRadius.card),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                _StudentRow(
                  student: rows[i],
                  justLinked: rows[i].studentId == justLinkedId,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const new({required this.student, required this.justLinked});

  final Student student;
  final bool justLinked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = student.name;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaraedaSpacing.space3,
          vertical: BaraedaSpacing.space2,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentPrimary,
                ),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Text(
                      name.isEmpty ? '' : name.characters.first,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textInverse,
                        fontWeight: BaraedaFontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: BaraedaSpacing.space3),
            Expanded(child: WordWrapText(name, style: BaraedaTypography.body)),
            const SizedBox(width: BaraedaSpacing.space2),
            BaraedaStatusPill(
              status: BaraedaStatus.boarded,
              label: justLinked ? '방금 연결' : '연결됨',
            ),
          ],
        ),
      ),
    );
  }
}
