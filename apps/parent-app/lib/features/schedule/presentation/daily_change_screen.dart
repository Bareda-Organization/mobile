import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/ui/confirm_dialog.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_panel.dart';

/// 일일 변경 신청(P-06 · `UF-P-06`) — 일정 탭에서 들어오는 하위 화면(§3.8).
///
/// 적다가 뒤로 가면 확인을 한 번 묻는다(R32 P14).
class DailyChangeScreen extends ConsumerWidget {
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
          appBar: const AppHeader(title: '일일 변경 신청'),
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
                    // R32 P5 — 자녀 ID 를 key 로 건다. 고른 회차·입력한 주소가 자녀를 바꿔도 남으면
                    // 다른 자녀의 회차로 신청하게 된다.
                    Expanded(
                      child: ChangeRequestPanel(
                        key: ValueKey('change-request-$selectedId'),
                        studentId: selectedId,
                      ),
                    ),
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
