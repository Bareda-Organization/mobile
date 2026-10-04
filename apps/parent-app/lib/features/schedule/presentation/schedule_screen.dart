import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/minute_ticker.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_history.dart';

/// 일정 탭(P-04 · `UF-P-03·06`) — 날짜별 회차 조회가 첫 칸이고, 편집 둘(요일별 주소 · 일일 변경)은 하위 화면이다.
///
/// 처리 대기 신청이 있으면 맨 위 띠가 사라지지 않는다(`UF-P-06`). 신청 이력은 이 탭 맨 아래에 있다.
/// 학부모만 편집한다(§1.1 `canChangeBoardingLocation`) — 학생에게는 이 탭이 없다.
class ScheduleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit =
        ref.watch(roleCapabilitiesProvider)?.canChangeBoardingLocation ?? false;
    final now = ref.watch(clockProvider).now();

    return Scaffold(
      appBar: AppHeader(title: '일정', subtitle: _dateWithWeekday(now, 0)),
      body: SafeArea(
        child: canEdit ? const _ParentSection() : const _StudentSection(),
      ),
    );
  }
}

/// `10월 3일 (토)` — 한국 시간 달력 날짜.
String _dateWithWeekday(DateTime now, int plusDays) {
  final date = koreaServiceDate(now, plusDays: plusDays);
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
}

class _ParentSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () => const _LoadingBody(),
      error: (error, stack) =>
          _ErrorBody(onRetry: () => ref.invalidate(myStudentsProvider)),
      data: (students) {
        if (students.isEmpty) {
          return Center(
            child: EmptyState(
              icon: 'user-plus',
              title: '연결된 자녀가 없어요',
              body: '자녀 앱에서 만든 연결 코드를 입력하면\n일정을 볼 수 있어요.',
              action: BaraedaButton(
                label: '자녀 연결하기',
                onPressed: () => context.push(AppRoutes.childLink),
              ),
            ),
          );
        }
        final selectedId = watchSelectedStudentId(ref, students);
        return _ScheduleBody(students: students, studentId: selectedId);
      },
    );
  }
}

/// 일정을 불러오는 중 — 날짜 알약 자리와 회차 칸 뼈대.
class _LoadingBody extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '일정을 불러오는 중',
      child: const Padding(
        padding: EdgeInsets.all(BaraedaSpacing.gutterMobile),
        child: BaraedaSkeletonList(),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: 'wifi-off',
        title: '일정을 불러오지 못했어요',
        body: '인터넷 연결을 확인하고 다시 시도해 주세요.\n오늘 버스 위치는 홈에서 볼 수 있어요.',
        action: BaraedaButton(
          label: '다시 시도',
          variant: BaraedaButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

class _ScheduleBody extends ConsumerStatefulWidget {
  const new({required this.students, required this.studentId});

  final List<Student> students;
  final String studentId;

  @override
  ConsumerState<_ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends ConsumerState<_ScheduleBody> {
  /// 0 = 오늘, 1 = 내일 (한국 시간).
  int _dayOffset = 0;
  final GlobalKey<State<StatefulWidget>> _historyKey = GlobalKey();

  void _showHistory() {
    final target = _historyKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: BaraedaDuration.sheet,
      curve: BaraedaCurve.drawer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentId = widget.studentId;
    final now = ref.watch(clockProvider).now();
    final date = _dayOffset == 0
        ? null
        : koreaServiceDate(now, plusDays: _dayOffset);
    final runsAsync = date == null
        ? ref.watch(runsForStudentProvider(studentId))
        : ref.watch(runsForStudentOnProvider((studentId, date)));
    final pending =
        ref.watch(changeRequestsProvider(studentId)).value?.pendingCount ?? 0;

    return ListView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      children: [
        StudentSwitcher(students: widget.students, selectedId: studentId),
        if (pending > 0) ...[
          AlertBanner(
            tone: AlertTone.moving,
            title: '처리 대기 $pending건',
            body: '학원이 확인하고 있어요',
            inlineAction: true,
            action: BaraedaButton(
              label: '이력 보기',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.ghost,
              onPressed: _showHistory,
            ),
          ),
          const SizedBox(height: BaraedaSpacing.space4),
        ],
        BaraedaSegmentedControl(
          block: true,
          options: [
            BaraedaSegmentedOption(
              '0',
              label: '오늘 · ${_dateWithWeekday(now, 0).split(' (').first}',
            ),
            BaraedaSegmentedOption(
              '1',
              label: '내일 · ${_dateWithWeekday(now, 1).split(' (').first}',
            ),
          ],
          value: '$_dayOffset',
          onChanged: (value) => setState(() => _dayOffset = int.parse(value)),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        _RunsCard(
          runsAsync: runsAsync,
          dayWord: _dayOffset == 0 ? '오늘' : '내일',
          showCountdown: _dayOffset == 0,
          onRetry: () => date == null
              ? ref.invalidate(runsForStudentProvider(studentId))
              : ref.invalidate(runsForStudentOnProvider((studentId, date))),
        ),
        const SizedBox(height: BaraedaSpacing.sectionGap),
        const _SectionTitle('바꾸고 싶을 때'),
        BaraedaListGroup(
          children: [
            BaraedaListRow(
              leadingIcon: 'calendar',
              title: '요일별 등하원 주소',
              wrapSubtitleByWord: true,
              subtitle: _weeklySummary(
                ref.watch(weeklyAddressProvider(studentId)).value,
              ),
              trailing: const BaraedaIcon('chevron-right'),
              onTap: () => context.push(AppRoutes.weeklyAddress),
            ),
            BaraedaListRow(
              leadingIcon: 'pencil',
              title: '일일 변경 신청',
              subtitle: '오늘이나 내일 하루만 바꾸거나 취소해요',
              trailing: const BaraedaIcon('chevron-right'),
              onTap: () => context.push(AppRoutes.dailyChange),
            ),
          ],
        ),
        const SizedBox(height: BaraedaSpacing.sectionGap),
        KeyedSubtree(
          key: _historyKey,
          child: ChangeRequestHistory(studentId: studentId),
        ),
      ],
    );
  }
}

/// `월 ~ 토 등록 · 매주 같은 주소로 와요` — 등록된 요일을 이어진 구간이면 `a ~ b`, 아니면 점으로 늘어놓는다.
/// 아직 못 받았거나 하나도 없으면 뒷말만 둔다.
String _weeklySummary(List<WeeklyAddressEntry>? entries) {
  const tail = '매주 같은 주소로 와요';
  if (entries == null || entries.isEmpty) return tail;
  final days = {for (final e in entries) e.weekday}.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final contiguous = days.last.index - days.first.index == days.length - 1;
  final label = days.length >= 2 && contiguous
      ? '${days.first.label} ~ ${days.last.label}'
      : days.map((d) => d.label).join(' · ');
  return '$label 등록 · $tail';
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Semantics(
        header: true,
        child: Text(text, style: BaraedaTypography.h3),
      ),
    );
  }
}

/// 그날 회차 목록 한 칸 묶음 — 회차마다 `등원 · 12:20 출발` + 승하차지·호차·탑승 여부 + 상태 칩.
class _RunsCard extends StatelessWidget {
  const new({
    required this.runsAsync,
    required this.dayWord,
    required this.showCountdown,
    required this.onRetry,
  });

  final AsyncValue<List<StudentRun>> runsAsync;
  final String dayWord;
  final bool showCountdown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return runsAsync.when(
      skipError: true,
      loading: () => const BaraedaSkeletonList(count: 2),
      error: (error, stack) => AlertBanner(
        tone: AlertTone.missed,
        body: '$dayWord 회차를 불러오지 못했어요',
        inlineAction: true,
        action: BaraedaButton(
          label: '다시 시도',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ),
      data: (runs) {
        if (runs.isEmpty) {
          return EmptyState(title: '$dayWord 예정된 회차가 없어요');
        }
        return MinuteTicker(
          builder: (context, now) => BaraedaListGroup(
            children: [
              for (final run in runs)
                _runRow(run, now, showCountdown: showCountdown),
            ],
          ),
        );
      },
    );
  }
}

Widget _runRow(StudentRun run, DateTime now, {required bool showCountdown}) {
  final status = runStatusChip(run);
  final left = showCountdown ? untilConfirm(run, now) : null;
  final parts = [
    run.stop.name,
    run.busNo,
    if (run.riding) '탑승' else '탑승 안 함',
    ?(left == null ? null : '확정까지 $left'),
  ];
  return BaraedaListRow(
    leadingIcon: 'bus',
    title: '${run.direction.label} · ${formatClock(run.departTime)} 출발',
    subtitle: parts.join(' · '),
    wrapSubtitleByWord: true,
    trailing: BaraedaStatusPill(status: status.status, label: status.label),
  );
}

/// 학생 계정은 이 탭이 없다 — 주소로 들어와도 편집 화면 대신 안내만 둔다(기본값은 닫힘).
class _StudentSection extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: 'link',
        title: '등하원 일정은 부모님 계정에서 관리해요',
        action: BaraedaButton(
          label: '부모 연결 코드 발급',
          onPressed: () => context.push(AppRoutes.childLink),
        ),
      ),
    );
  }
}
