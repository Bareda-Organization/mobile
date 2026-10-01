import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/ui/confirm_dialog.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_panel.dart';
import 'package:parent_app/features/schedule/presentation/widgets/weekly_address_editor.dart';

/// P-05·P-06 등하원 일정 화면 — 요일별 주소(§3.7) · 일일 변경 신청(§3.8·§3.9).
///
/// 학부모만 편집한다(§1.1 `canChangeBoardingLocation`). 학생 계정은 이 화면
/// 대신 부모 연결 코드 생성 진입점(S-05)만 본다.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canEdit = capabilities?.canChangeBoardingLocation ?? false;

    final edits = ref.watch(scheduleUnsavedEditsProvider);

    // R32 P14 — 주소·변경 요청을 적다가 뒤로 가면 확인 없이 입력이 사라졌다. 적은 것이 있을 때만 묻는다.
    return ListenableBuilder(
      listenable: edits,
      builder: (context, _) => PopScope(
        canPop: !edits.hasAny,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await showConfirmDialog(
            context,
            title: '입력을 그만할까요?',
            body: '저장하지 않은 내용은 사라집니다.',
            confirmLabel: '나가기',
            cancelLabel: '계속 입력',
          );
          if (leave && context.mounted) context.pop();
        },
        child: Scaffold(
          appBar: const AppHeader(title: '등하원 일정'),
          body: SafeArea(
            child: canEdit ? const _ParentSection() : const _StudentSection(),
          ),
        ),
      ),
    );
  }
}

class _ParentSection extends ConsumerWidget {
  const _ParentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(
        child: AlertBanner(tone: AlertTone.missed, body: '자녀 정보를 불러오지 못했습니다'),
      ),
      data: (students) {
        if (students.isEmpty) {
          return Center(
            child: EmptyState(
              icon: 'user-plus',
              title: '연결된 자녀가 없습니다',
              action: BaraedaButton(
                label: '자녀 연결하기',
                onPressed: () => context.push(AppRoutes.childLink),
              ),
            ),
          );
        }

        final selectedId = watchSelectedStudentId(ref, students);

        return ListView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          children: [
            StudentSwitcher(students: students, selectedId: selectedId),
            _StudentScheduleBody(studentId: selectedId),
          ],
        );
      },
    );
  }
}

class _StudentScheduleBody extends ConsumerWidget {
  const _StudentScheduleBody({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressAsync = ref.watch(weeklyAddressProvider(studentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('요일별 등하원 주소', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space2),
        addressAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const AlertBanner(
            tone: AlertTone.missed,
            body: '주소를 불러오지 못했습니다',
          ),
          // R32 P5 — 자녀 ID 를 key 로 건다. 없으면 이미 불러 둔 다른 자녀로 바꿀 때 입력칸이 이전
          // 자녀의 글자를 그대로 들고 있어, 저장하면 다른 아이 이름으로 덮어쓴다.
          data: (entries) => WeeklyAddressEditor(
            key: ValueKey('weekly-address-$studentId'),
            studentId: studentId,
            entries: entries,
          ),
        ),
        const SizedBox(height: BaraedaSpacing.sectionGap),
        const Text('일일 변경 신청', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space2),
        // 같은 이유 — 고른 회차·입력한 주소가 자녀를 바꿔도 남으면 다른 자녀의 회차로 신청하거나
        // (드롭다운이 목록에 없는 값을 들고 있어) 화면이 깨진다.
        ChangeRequestPanel(
          key: ValueKey('change-request-$studentId'),
          studentId: studentId,
        ),
      ],
    );
  }
}

/// 학생 계정 — 이 화면에서 편집 권한이 없으므로 부모 연결 코드 생성 화면
/// (S-05)으로 안내한다.
class _StudentSection extends StatelessWidget {
  const _StudentSection();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: 'link',
        title: '등하원 일정은 부모님 계정에서 관리합니다',
        action: BaraedaButton(
          label: '부모 연결 코드 발급',
          onPressed: () => context.push(AppRoutes.childLink),
        ),
      ),
    );
  }
}
