import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/widgets/notification_list.dart';
import 'package:parent_app/features/home/presentation/widgets/pending_change_badge.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';

/// P-03·P-04·P-09 홈 화면 — 오늘 회차(§3.5) · 등원 여부 토글(§3.6) ·
/// 알림 목록(§3.12·§3.13). (`P-02` 가 아니다 — 그것은 자녀 연결 화면의
/// ID 이고, 이 화면이 보여주는 것은 P-09 알림 목록이다. FEATURE_SPEC ·
/// USER_FLOWS 직접 대조로 정정, 2026-09-12.)
///
/// 역할 분기는 문자열이 아니라 `roleCapabilitiesProvider.canToggleAttendance`
/// 하나로만 한다(§1.1) — 학부모는 연결 자녀 중 선택(UF-P-02), 자녀별 탑승
/// 토글(UF-P-04, ②구간 승인 대기는 UF-P-05), 알림 목록(UF-P-08). 학생은
/// 본인 `student_id` 하나만 쓴다(UF-S-01 조회 전용).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return Scaffold(
      // 로그아웃을 머리말에도 둔다(2026-09-29 사용자 지적 · Ruling 362) — [설정] 맨 아래에만
      // 있어 찾지 못했다. 매니저 앱 홈과 같은 자리다. 설정 화면의 버튼은 그대로 둔다.
      appBar: AppHeader(
        title: '오늘 운행',
        actions: BaraedaButton(
          label: '로그아웃',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.ghost,
          onPressed: () => confirmLogout(context, ref),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          children: [
            if (isParent) const _ParentSection() else const _StudentSection(),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('알림', style: BaraedaTypography.h3),
                // UF-P-08 — "홈 → [알림] → … → [알림 설정]". 이 배선이 없어서
                // SettingsScreen 에 도달할 길이 부재했다(2026-09-21).
                BaraedaButton(
                  label: '설정',
                  size: BaraedaButtonSize.sm,
                  variant: BaraedaButtonVariant.ghost,
                  onPressed: () => context.push(AppRoutes.settings),
                ),
              ],
            ),
            const SizedBox(height: BaraedaSpacing.space4),
            const _NotificationSection(),
          ],
        ),
      ),
    );
  }
}

/// 학부모 갈래 — §3.1 연결 자녀 목록을 먼저 받아야 회차를 조회할 수 있다.
class _ParentSection extends ConsumerWidget {
  const _ParentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '자녀 목록을 불러오지 못했습니다'),
      data: (students) {
        if (students.isEmpty) {
          return EmptyState(
            title: '연결된 자녀가 없습니다',
            body: '자녀 연결을 먼저 진행해 주세요',
            action: BaraedaButton(
              label: '자녀 연결하기',
              onPressed: () => context.push(AppRoutes.childLink),
            ),
          );
        }

        final selectedId =
            ref.watch(selectedStudentIdProvider) ?? students.first.studentId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // §3.1 "자녀 선택 UI 는 2명 이상일 때만 노출."
            if (students.length > 1) ...[
              BaraedaSelect(
                label: '자녀 선택',
                value: selectedId,
                options: students
                    .map(
                      (s) => BaraedaSelectOption(s.studentId, label: s.name),
                    )
                    .toList(),
                onChanged: (value) =>
                    ref.read(selectedStudentIdProvider.notifier).state = value,
              ),
              const SizedBox(height: BaraedaSpacing.space4),
            ],
            PendingChangeBadge(studentId: selectedId),
            _RunsSection(studentId: selectedId, canToggle: true),
          ],
        );
      },
    );
  }
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용, UF-S-01).
class _StudentSection extends ConsumerWidget {
  const _StudentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentIdAsync = ref.watch(myStudentIdProvider);

    return studentIdAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '내 정보를 불러오지 못했습니다'),
      data: (studentId) => studentId == null
          ? const EmptyState(title: '학생 계정 정보가 없습니다')
          : _RunsSection(studentId: studentId, canToggle: false),
    );
  }
}

class _RunsSection extends ConsumerWidget {
  const _RunsSection({required this.studentId, required this.canToggle});

  final String studentId;
  final bool canToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(runsForStudentProvider(studentId));

    return runsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '오늘 회차를 불러오지 못했습니다'),
      data: (runs) => runs.isEmpty
          ? const EmptyState(title: '오늘 예정된 회차가 없습니다')
          : Column(
              children: runs
                  .map(
                    (run) => RunCard(
                      studentId: studentId,
                      run: run,
                      canToggle: canToggle,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(notificationsProvider);

    return pageAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '알림을 불러오지 못했습니다'),
      data: (page) =>
          NotificationList(page: page, now: ref.watch(clockProvider).now()),
    );
  }
}
