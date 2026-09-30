import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/failure_message.dart';
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
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// 푸시 SDK 가 아직 없어 앱 안 갱신이 유일한 통지 수단이다(F05-06) — 당기지 않아도 앱에 돌아오거나
/// [_autoRefreshInterval] 이 지나면 회차·알림을 다시 받는다.
class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  static const _autoRefreshInterval = Duration(seconds: 30);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_autoRefreshInterval, (_) => _reloadQuietly());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadQuietly();
  }

  /// 화면을 스피너로 바꾸지 않고(무효화는 옛 값을 유지한 채 다시 받는다) 서버 값으로 갈아 끼운다.
  void _reloadQuietly() {
    ref
      ..invalidate(runsForStudentProvider)
      ..invalidate(runsForStudentOnProvider)
      ..invalidate(changeRequestsProvider)
      ..invalidate(notificationsProvider);
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
              const SizedBox(height: BaraedaSpacing.sectionGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _NotificationTitle(),
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
      ),
    );
  }

  /// 화면을 아래로 당기면 자녀·회차·알림을 서버에서 다시 받는다. 실패해도 각 영역의 오류 띠가
  /// 이유를 보여주므로 여기서는 끝나기만 기다린다.
  Future<void> _refresh({required bool isParent}) async {
    ref
      ..invalidate(runsForStudentProvider)
      ..invalidate(runsForStudentOnProvider)
      ..invalidate(changeRequestsProvider)
      ..invalidate(notificationsProvider);
    final base = isParent
        ? ref.refresh(myStudentsProvider.future)
        : ref.refresh(myStudentIdProvider.future);
    await Future.wait([
      base.then<void>((_) {}, onError: (_) {}),
      ref
          .read(notificationsProvider.future)
          .then<void>((_) {}, onError: (_) {}),
    ]);
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
  const _ErrorBanner({required this.message, required this.onRetry});

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
  const _ParentShortcuts();

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
  const _StudentSection();

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
  const _RunsSection({required this.studentId, required this.canToggle});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('오늘')),
            ButtonSegment(value: 1, label: Text('내일')),
          ],
          selected: {_dayOffset},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _dayOffset = selection.first),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        runsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => isWithdrawnStudent(error)
              ? const AlertBanner(
                  tone: AlertTone.missed,
                  body: withdrawnStudentMessage,
                )
              : _ErrorBanner(
                  message: '$dayWord 회차를 불러오지 못했습니다',
                  onRetry: () => date == null
                      ? ref.invalidate(runsForStudentProvider(studentId))
                      : ref.invalidate(
                          runsForStudentOnProvider((studentId, date)),
                        ),
                ),
          data: (runs) => runs.isEmpty
              ? EmptyState(title: '$dayWord 예정된 회차가 없습니다')
              : Column(
                  children: runs
                      .map(
                        (run) => RunCard(
                          studentId: studentId,
                          run: run,
                          canToggle: widget.canToggle,
                          date: date,
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
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
      error: (error, stack) => _ErrorBanner(
        message: '알림을 불러오지 못했습니다',
        onRetry: () => ref.invalidate(notificationsProvider),
      ),
      data: (page) =>
          NotificationList(page: page, now: ref.watch(clockProvider).now()),
    );
  }
}

/// "알림" 머리말 — 안 읽은 알림이 있으면 건수 배지를 곁들인다(F05-08, UF-P-08 "미읽음 배지").
class _NotificationTitle extends ConsumerWidget {
  const _NotificationTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unreadCount ?? 0;
    return Row(
      children: [
        const Text('알림', style: BaraedaTypography.h3),
        if (unread > 0) ...[
          const SizedBox(width: BaraedaSpacing.space2),
          BaraedaBadge(
            label: '안 읽음',
            tone: BaraedaBadgeTone.amber,
            count: unread,
          ),
        ],
      ],
    );
  }
}
