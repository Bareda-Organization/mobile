import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/refresh/visible_poller.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/widgets/pending_change_badge.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';

/// P-03·P-04 홈 화면 — 오늘 회차(§3.5) · 등원 여부 토글(§3.6). 운행 정보만 둔다.
/// 알림 목록(P-09)은 2026-09-30 부터 아래 탭 막대의 `[알림]` 탭이다(`NotificationsScreen`, R44) —
/// 홈 맨 아래에 이어 붙이면 끝까지 내려야 보였다.
///
/// 역할 분기는 문자열이 아니라 `roleCapabilitiesProvider.canToggleAttendance`
/// 하나로만 한다(§1.1) — 학부모는 연결 자녀 중 선택(UF-P-02), 자녀별 탑승
/// 토글(UF-P-04, ②구간 승인 대기는 UF-P-05). 학생은
/// 본인 `student_id` 하나만 쓴다(UF-S-01 조회 전용).
class HomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// 푸시 SDK 가 아직 없어 앱 안 갱신이 유일한 통지 수단이다(F05-06) — 당기지 않아도 [pollInterval] 마다 · 앱에
/// 돌아올 때 회차를 다시 받는다. 앱이 백그라운드이거나 다른 화면이 홈 위에 있으면
/// 멈춘다(`VisiblePoller`, R46 D #7).
/// 알림은 `AppShell` 이 받는다.
class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final VisiblePoller _poller = VisiblePoller(
    interval: pollInterval,
    onTick: _reloadQuietly,
    isCovered: () => isCoveredFrom(context, {AppRoutes.home}),
  );

  @override
  void initState() {
    super.initState();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  /// 화면을 스피너로 바꾸지 않고(무효화는 옛 값을 유지한 채 다시 받는다) 서버 값으로 갈아 끼운다.
  void _reloadQuietly() {
    ref
      ..invalidate(runsForStudentProvider)
      ..invalidate(runsForStudentOnProvider)
      ..invalidate(changeRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return Scaffold(
      // 로그아웃을 머리말에도 둔다(2026-09-29 사용자 지적 · Ruling 362) — [설정] 맨 아래에만
      // 있어 찾지 못했다. 매니저 앱 홈과 같은 자리다. 설정 화면의 버튼은 그대로 둔다.
      appBar: AppHeader(
        title: '운행',
        actions: BaraedaButton(
          label: '로그아웃',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.ghost,
          onPressed: () => confirmLogout(context, ref),
        ),
      ),
      body: SafeArea(
        // 당겨서 새로고침 — 내용이 화면보다 짧아도 당겨지도록 항상 스크롤 가능하게 둔다.
        child: RefreshIndicator(
          onRefresh: () => _refresh(isParent: isParent),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
            children: [
              if (isParent) const _ParentSection() else const _StudentSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// 화면을 아래로 당기면 자녀·회차를 서버에서 다시 받는다. 실패해도 각 영역의 오류 띠가
  /// 이유를 보여주므로 여기서는 끝나기만 기다린다.
  Future<void> _refresh({required bool isParent}) async {
    ref
      ..invalidate(runsForStudentProvider)
      ..invalidate(runsForStudentOnProvider)
      ..invalidate(changeRequestsProvider);
    final base = isParent
        ? ref.refresh(myStudentsProvider.future)
        : ref.refresh(myStudentIdProvider.future);
    await base.then<void>((_) {}, onError: (_) {});
  }
}

/// 학부모 갈래 — §3.1 연결 자녀 목록을 먼저 받아야 회차를 조회할 수 있다.
class _ParentSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _ErrorBanner(
        message: '자녀 목록을 불러오지 못했습니다',
        onRetry: () => ref.invalidate(myStudentsProvider),
      ),
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

        final selectedId = watchSelectedStudentId(ref, students);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // §3.1 "자녀 선택 UI 는 2명 이상일 때만 노출."
            StudentSwitcher(students: students, selectedId: selectedId),
            // P2·P3 — 처리 대기 배지는 0건이면 사라져 일정 화면·둘째 연결로 갈 길이 없었다.
            const _ParentShortcuts(),
            PendingChangeBadge(studentId: selectedId),
            _RunsSection(studentId: selectedId, canToggle: true),
          ],
        );
      },
    );
  }
}

/// 불러오기 실패 띠 — 띠만 있으면 화면을 나갔다 들어오는 수밖에 없어 [다시 시도] 를 붙인다(R32 P7).
class _ErrorBanner extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AlertBanner(
      tone: AlertTone.missed,
      body: message,
      action: BaraedaButton(
        label: '다시 시도',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: onRetry,
      ),
    );
  }
}

/// 학부모 홈의 항상 보이는 진입 둘 — 등하원 일정(P-05·P-06)과 자녀 추가(P-02).
class _ParentShortcuts extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
      child: Row(
        children: [
          BaraedaButton(
            label: '일정',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => context.push(AppRoutes.schedule),
          ),
          const SizedBox(width: BaraedaSpacing.space2),
          BaraedaButton(
            label: '자녀 추가',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: () => context.push(AppRoutes.childLink),
          ),
        ],
      ),
    );
  }
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용, UF-S-01).
class _StudentSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentIdAsync = ref.watch(myStudentIdProvider);

    return studentIdAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _ErrorBanner(
        message: '내 정보를 불러오지 못했습니다',
        onRetry: () => ref.invalidate(myStudentIdProvider),
      ),
      data: (studentId) => studentId == null
          ? const EmptyState(title: '학생 계정 정보가 없습니다')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // P1 — 연결 코드(S-05)는 일정 화면에만 있어 학생은 갈 길이 없었다.
                Align(
                  alignment: Alignment.centerLeft,
                  child: BaraedaButton(
                    label: '부모 연결 코드',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: () => context.push(AppRoutes.childLink),
                  ),
                ),
                const SizedBox(height: BaraedaSpacing.space4),
                _RunsSection(studentId: studentId, canToggle: false),
              ],
            ),
    );
  }
}

/// 회차 영역 — [오늘 · 내일] 전환(UF-P-04 "전날~당일"). 내일은 한국 시간 내일 날짜로 §3.5 를 조회한다.
/// 학생(`canToggle` false)도 내일 회차를 볼 수 있으나 토글은 없다.
class _RunsSection extends ConsumerStatefulWidget {
  const new({required this.studentId, required this.canToggle});

  final String studentId;
  final bool canToggle;

  @override
  ConsumerState<_RunsSection> createState() => _RunsSectionState();
}

class _RunsSectionState extends ConsumerState<_RunsSection> {
  /// 0 = 오늘, 1 = 내일 (한국 시간).
  int _dayOffset = 0;

  @override
  Widget build(BuildContext context) {
    final studentId = widget.studentId;
    final isToday = _dayOffset == 0;
    final date = isToday
        ? null
        : koreaServiceDate(
            ref.watch(clockProvider).now(),
            plusDays: _dayOffset,
          );
    final runsAsync = date == null
        ? ref.watch(runsForStudentProvider(studentId))
        : ref.watch(runsForStudentOnProvider((studentId, date)));
    final dayWord = isToday ? '오늘' : '내일';
    final isOffline = ref.watch(
      networkStatusProvider.select((status) => status.isOffline),
    );
    // P-03 — ②구간 신청이 승인을 기다리는 회차는 카드에 출발까지 남은 시간을 붙인다.
    // 신청 이력이 아직 없거나 실패면 붙이지 않는다.
    final waitingRunIds = {
      for (final request
          in ref.watch(changeRequestsProvider(studentId)).value?.items ??
              const <ChangeRequest>[])
        if (request.status == ChangeRequestStatus.pending &&
            request.runId != null)
          request.runId,
    };
    Widget retryBanner(String message) => _ErrorBanner(
      message: message,
      onRetry: () => date == null
          ? ref.invalidate(runsForStudentProvider(studentId))
          : ref.invalidate(runsForStudentOnProvider((studentId, date))),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSegmentedControl(
          block: true,
          options: const [
            BaraedaSegmentedOption('0', label: '오늘'),
            BaraedaSegmentedOption('1', label: '내일'),
          ],
          value: '$_dayOffset',
          onChanged: (value) => setState(() => _dayOffset = int.parse(value)),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        runsAsync.when(
          // 갱신이 실패해도 마지막으로 받은 회차를 지우지 않는다 — 엘리베이터·지하철에서 카드가 오류 배너로
          // 바뀌지 않게, 오류는 카드 위에 따로 알린다(R46). 퇴원 학생 오류는 화면을 대체한다.
          skipError:
              !(runsAsync.hasError && isWithdrawnStudent(runsAsync.error!)),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => isWithdrawnStudent(error)
              ? const AlertBanner(
                  tone: AlertTone.missed,
                  body: withdrawnStudentMessage,
                )
              : retryBanner('$dayWord 회차를 불러오지 못했습니다'),
          data: (runs) => Column(
            children: [
              // 끊긴 동안은 맨 위 한 줄(`OfflineBar`)이 같은 말을 한다 — 카드마다 또 알리지 않는다.
              if (runsAsync.hasError && !isOffline)
                retryBanner('최신 $dayWord 회차를 불러오지 못했습니다 · 이전 정보입니다'),
              if (runs.isEmpty)
                EmptyState(title: '$dayWord 예정된 회차가 없습니다')
              else
                for (final run in runs)
                  RunCard(
                    studentId: studentId,
                    run: run,
                    canToggle: widget.canToggle,
                    date: date,
                    isApprovalPending: waitingRunIds.contains(run.runId),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
