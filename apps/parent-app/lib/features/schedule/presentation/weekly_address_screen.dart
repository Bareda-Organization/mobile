import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/ui/confirm_dialog.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/widgets/weekly_address_editor.dart';

/// 요일별 등하원 주소(P-05 · `UF-P-03`) — 일정 탭에서 들어오는 하위 화면(§3.7).
///
/// 적다가 뒤로 가면 확인을 한 번 묻는다(R32 P14, 시안 `weekly-address--leave`).
class WeeklyAddressScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edits = ref.watch(scheduleUnsavedEditsProvider);
    final studentsAsync = ref.watch(myStudentsProvider);

    return ListenableBuilder(
      listenable: edits,
      builder: (context, _) => PopScope(
        canPop: !edits.hasAny,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await showConfirmDialog(
            context,
            title: '입력을 그만할까요?',
            body: '저장하지 않은 내용은 사라져요.',
            confirmLabel: '나가기',
            cancelLabel: '계속 입력',
          );
          if (leave && context.mounted) context.pop();
        },
        child: Scaffold(
          appBar: const AppHeader(title: '요일별 주소'),
          body: SafeArea(
            child: studentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => const Center(
                child: AlertBanner(
                  tone: AlertTone.missed,
                  body: '자녀 정보를 불러오지 못했어요',
                ),
              ),
              data: (students) {
                final selectedId = watchSelectedStudentId(ref, students);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (students.length >= 2)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          BaraedaSpacing.gutterMobile,
                          BaraedaSpacing.space2,
                          BaraedaSpacing.gutterMobile,
                          0,
                        ),
                        child: StudentSwitcher(
                          students: students,
                          selectedId: selectedId,
                        ),
                      ),
                    Expanded(child: _Body(studentId: selectedId)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const new({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressAsync = ref.watch(weeklyAddressProvider(studentId));
    return addressAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(
        child: AlertBanner(tone: AlertTone.missed, body: '주소를 불러오지 못했어요'),
      ),
      // R32 P5 — 자녀 ID 를 key 로 건다. 없으면 이미 불러 둔 다른 자녀로 바꿀 때 입력칸이 이전
      // 자녀의 글자를 그대로 들고 있어, 저장하면 다른 아이 이름으로 덮어쓴다.
      data: (entries) => WeeklyAddressEditor(
        key: ValueKey('weekly-address-$studentId'),
        studentId: studentId,
        entries: entries,
      ),
    );
  }
}
