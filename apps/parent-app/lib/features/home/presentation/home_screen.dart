import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
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
import 'package:parent_app/features/home/presentation/widgets/home_bus_preview.dart';
import 'package:parent_app/features/home/presentation/widgets/pending_change_badge.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';
import 'package:url_launcher/url_launcher.dart';

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

    final now = ref.watch(clockProvider).now();

    return Scaffold(
      // 로그아웃은 설정 탭 맨 아래에만 있다(`Ruling 826`) — 홈 머리말에서 뺐다. 학생은 날짜를 부제로 붙인다.
      appBar: AppHeader(
        title: isParent ? '우리 아이 버스' : '내 버스',
        subtitle: isParent ? null : _dateWithWeekday(now),
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
      loading: () => const BaraedaSkeletonList(),
      error: (error, stack) =>
          _LoadFailure(onRetry: () => ref.invalidate(myStudentsProvider)),
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
            _Preview(
              studentId: selectedId,
              studentName: students
                  .firstWhere((s) => s.studentId == selectedId)
                  .name,
            ),
            // 처리 대기 건수 — 0건이면 사라진다. 일정 탭이 이력으로 가는 길이다(UF-P-06).
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

/// 자녀 카드 — 오늘 회차의 방향 · 내 승하차지를 같이 넘긴다(`HomeBusPreview` 가 §3.11 을 30초마다 읽는다).
class _Preview extends ConsumerWidget {
  const new({required this.studentId, required this.studentName});

  final String studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(runsForStudentProvider(studentId)).value;
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
      child: HomeBusPreview(
        studentId: studentId,
        studentName: studentName,
        runs: runs ?? const [],
      ),
    );
  }
}

/// 홈을 못 불러왔다 — 다시 시도 + (기기에 남긴 학원 문의처에 번호가 있으면) 급할 때 걸 전화(시안
/// `home-parent--error`).
class _LoadFailure extends ConsumerWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = phoneNumberOf(ref.watch(savedAcademyContactProvider).value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(
          icon: 'wifi-off',
          title: '버스 정보를 불러오지 못했어요',
          body: '인터넷 연결을 확인하고 다시 시도해 주세요.\n연결되면 자동으로 다시 불러와요.',
          // 이 화면에서 할 수 있는 일은 이것 하나다 — 채워진 주 단추로 둔다.
          action: BaraedaButton(
            label: '다시 시도',
            icon: 'refresh',
            onPressed: onRetry,
          ),
        ),
        if (phone != null) ...[
          const SizedBox(height: BaraedaSpacing.space4),
          _EmergencyPhone(phone: phone),
        ],
      ],
    );
  }
}

/// 급할 때 거는 학원 전화 — 번호를 줄 때만 나온다(`Ruling 827`). 못 불러온 화면에서도 버스가 궁금한 사람이 갈 곳이 있다.
class _EmergencyPhone extends StatelessWidget {
  const new({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BaraedaCard(
      tone: BaraedaCardTone.mist,
      child: Row(
        children: [
          ExcludeSemantics(
            child: BaraedaIcon('phone', color: colors.accentPrimary),
          ),
          const SizedBox(width: BaraedaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WordWrapText(
                  '버스가 급하게 궁금하면',
                  style: TextStyle(fontWeight: BaraedaFontWeight.bold),
                ),
                WordWrapText(
                  '학원 $phone',
                  style: BaraedaTypography.bodySm.copyWith(
                    color: colors.accentPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: BaraedaSpacing.space2),
          BaraedaButton(
            label: '전화',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
          ),
        ],
      ),
    );
  }
}

/// `10월 3일 (토)` — 한국 시간 달력 날짜.
String _dateWithWeekday(DateTime now) {
  final date = koreaServiceDate(now);
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용, UF-S-01).
class _StudentSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentIdAsync = ref.watch(myStudentIdProvider);

    return studentIdAsync.when(
      loading: () => const BaraedaSkeletonList(),
      error: (error, stack) =>
          _LoadFailure(onRetry: () => ref.invalidate(myStudentIdProvider)),
      data: (studentId) => studentId == null
          ? const EmptyState(title: '학생 계정 정보가 없습니다')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Preview(studentId: studentId, studentName: '내'),
                _RunsSection(studentId: studentId, canToggle: false),
                // P1 — 연결 코드(S-05)로 가는 길. 학생은 일정 탭이 없어 홈 맨 아래에 둔다.
                BaraedaListGroup(
                  children: [
                    BaraedaListRow(
                      leadingIcon: 'link',
                      title: '부모님과 연결하기',
                      subtitle: '코드를 만들어 부모님께 알려 주세요',
                      trailing: const BaraedaIcon('chevron-right'),
                      onTap: () => context.push(AppRoutes.childLink),
                    ),
                  ],
                ),
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
    // P-03 — ②구간 신청이 승인을 기다리는 회차는 카드에 서버 마감까지 남은 시간을 붙인다(`Ruling 870`).
    // 신청 이력이 아직 없거나 실패면 붙이지 않는다. 같은 회차의 대기 신청이 여럿이면 가장 이른 마감을 쓴다.
    final waiting = <String, DateTime?>{};
    for (final request
        in ref.watch(changeRequestsProvider(studentId)).value?.items ??
            const <ChangeRequest>[]) {
      final runId = request.runId;
      if (request.status != ChangeRequestStatus.pending || runId == null) {
        continue;
      }
      final prior = waiting[runId];
      waiting[runId] = switch ((prior, request.deadlineAt)) {
        (final a?, final b?) => a.isBefore(b) ? a : b,
        (_, final b) => prior ?? b,
      };
    }
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
                    isApprovalPending: waiting.containsKey(run.runId),
                    approvalDeadlineAt: waiting[run.runId],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
