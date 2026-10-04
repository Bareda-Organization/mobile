import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/widgets/focus_run_card.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

/// 홈 탭 — 오늘의 담당 회차(§4.1, M-02·M-07). 기사는 `오늘 운행`, 동승자는 `오늘 회차`.
///
/// 큰 카드 하나(진행 중 > 확정된 가장 이른, [focusRunProvider]) + "다른 회차" 목록. 기사는 맨 아래 주 단추
/// `운행 준비하기` 가 운행 준비 화면으로 간다 — 운행 시작 요청은 그 화면의 확인 창 뒤에만 나간다(`Ruling 799`).
/// 동승자는 카드 안 `명단 열기` 가 명단 탭으로 간다.
///
/// 열려 있는 동안 [todayRunsRefreshInterval] 마다, 앱이 백그라운드에서 돌아올 때 목록을 다시 받는다 —
/// 확정은 서버 배치가 시각에 맞춰 바꾸므로(F06-13) 한 번 받은 목록은 곧 낡는다.
class ManagerHomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends ConsumerState<ManagerHomeScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      todayRunsRefreshInterval,
      (_) => _reloadQuietly(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _reloadQuietly();
    // 실시간 연결도 다시 붙게 한다 — REST 만 다시 읽으면 끊긴 소켓이 다음 재연결 타이머(최대 30초)를 기다린다.
    // 운행 화면이 열려 있지 않으면 듣는 컨트롤러가 없어 아무 일도 일어나지 않는다(R46-FIXRT S-5).
    ref.read(appResumedProvider.notifier).state++;
  }

  /// 회차 목록과 알림(배지)을 스피너 없이 다시 받는다 — 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이다.
  void _reloadQuietly() {
    ref.invalidate(todayRunsProvider);
    unawaited(ref.read(notificationFeedProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final runsAsync = ref.watch(todayRunsProvider);
    final forEscort =
        ref.watch(roleCapabilitiesProvider)?.canOperateRun == false;
    final noun = forEscort ? '회차' : '운행';

    return Scaffold(
      appBar: ManagerHeader(
        title: '오늘 $noun',
        dateSubtitle: true,
        homeRuns: runsAsync.value,
      ),
      body: runsAsync.when(
        // 주기 갱신 중에는 받아 둔 목록을 그대로 두고 바꿔 그린다 — 30초마다 뼈대가 뜨지 않게.
        skipLoadingOnReload: true,
        // 갱신이 실패해도 마지막으로 받은 목록을 지우지 않는다 — 오류는 목록 위에 따로 알린다(R46).
        skipError: true,
        loading: () => const _HomeSkeleton(),
        error: (error, _) => _HomeError(
          noun: noun,
          urgent: forEscort ? '명단이 급하면' : '운행 시작이 급하면',
          onRetry: () => ref.invalidate(todayRunsProvider),
        ),
        data: (runs) => _HomeBody(
          runs: runs,
          forEscort: forEscort,
          refreshError: runsAsync.error,
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const new({
    required this.runs,
    required this.forEscort,
    required this.refreshError,
  });

  final List<ManagerRun> runs;
  final bool forEscort;
  final Object? refreshError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final now = ref.watch(clockProvider).now();
    final focus = ref.watch(focusRunProvider);

    if (runs.isEmpty) {
      return const _HomeEmpty();
    }

    final others = [
      for (final run in runs)
        if (run.runId != focus?.runId) run,
    ];
    final finished = runs
        .where((run) => run.runStatus == RunStatus.finished)
        .length;

    final list = RefreshIndicator(
      onRefresh: () => ref.refresh(todayRunsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (refreshError != null) ...[
            AlertBanner(
              tone: AlertTone.missed,
              title: '최신 운행을 불러오지 못했어요',
              body: '이전 목록을 보고 있어요 · ${describeError(refreshError!)}',
              action: BaraedaButton(
                label: '다시 시도',
                size: BaraedaButtonSize.sm,
                variant: BaraedaButtonVariant.secondary,
                onPressed: () => ref.invalidate(todayRunsProvider),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!forEscort && focus != null)
            ChangeAckBanner(
              runId: focus.runId,
              ackRequired: focus.ackRequired,
              addedCount: focus.addedCount,
              removedCount: focus.removedCount,
              bottomGap: 12,
            ),
          if (focus != null)
            FocusRunCard(
              run: focus,
              now: now,
              forEscort: forEscort,
              caption: switch ((forEscort, focus.runStatus)) {
                (true, _) => '지금 명단',
                (false, RunStatus.moving) => '지금 운행',
                (false, _) => '다음 운행',
              },
              footer: forEscort
                  ? BaraedaButton(
                      label: '명단 열기',
                      icon: 'list',
                      block: true,
                      onPressed: () => context.go(AppRoutes.roster),
                    )
                  : null,
            ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      focus == null ? '오늘 회차' : '다른 회차',
                      style: BaraedaTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    forEscort
                        ? '오늘 ${runs.length}건'
                        : '오늘 ${runs.length}건 중 $finished건 종료',
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            BaraedaListGroup(
              children: [
                for (final run in others)
                  _OtherRunRow(run: run, forEscort: forEscort),
              ],
            ),
          ],
        ],
      ),
    );

    // 기사는 맨 아래 주 단추 — 진행 중이면 운행 화면으로, 확정됐으면 운행 준비로.
    final action = forEscort || focus == null ? null : _primaryAction(focus);
    if (action == null) return list;
    return Column(
      children: [
        Expanded(child: list),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bgBase,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: action(context, ref),
          ),
        ),
      ],
    );
  }

  Widget Function(BuildContext, WidgetRef)? _primaryAction(ManagerRun focus) {
    if (focus.runStatus == RunStatus.moving) {
      return (context, ref) => BaraedaButton(
        label: '운행 화면으로',
        icon: 'bus',
        size: BaraedaButtonSize.xl,
        block: true,
        onPressed: () => unawaited(context.push(AppRoutes.driveMode)),
      );
    }
    return (context, ref) => BaraedaButton(
      label: '운행 준비하기',
      icon: 'bus',
      size: BaraedaButtonSize.xl,
      block: true,
      onPressed: () => unawaited(context.push(AppRoutes.runReady)),
    );
  }
}

/// "다른 회차" 한 줄 — 확정된 회차를 누르면 그 회차가 큰 카드로 올라온다. 종료 · 확정 전 회차는 누를 곳이 없다.
class _OtherRunRow extends ConsumerWidget {
  const new({required this.run, required this.forEscort});

  final ManagerRun run;
  final bool forEscort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final (status, label) = runStatusChip(run);
    final selectable = run.confirmed && run.runStatus != RunStatus.finished;
    return BaraedaListRow(
      title:
          '${hhmm(run.departTime)} · '
          '${run.busNo} ${directionLabel(run.direction)}',
      subtitle: _subtitle(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BaraedaStatusPill(status: status, label: label),
          if (selectable) ...[
            const SizedBox(width: 4),
            BaraedaIcon('chevron-right', color: colors.textSecondary),
          ],
        ],
      ),
      onTap: selectable
          ? () => ref.read(selectedRunIdProvider.notifier).state = run.runId
          : null,
    );
  }

  String _subtitle() {
    if (run.runStatus == RunStatus.finished) {
      final riders = run.riderCount;
      return riders == null ? '종료된 운행' : '종료 · 학생 $riders명';
    }
    if (!run.confirmed) {
      final at = run.confirmAt;
      return at == null ? '출발 30분 전에 확정되면 열려요' : '${hhmm(at)} 에 확정되면 열려요';
    }
    return run.riderCount == null
        ? '출발 ${hhmm(run.departTime)}'
        : '탑승 예정 ${run.riderCount}명';
  }
}

/// 처음 받는 중 — 큰 카드 · 목록 자리를 뼈대로 잡아 둔다.
class _HomeSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        BaraedaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BaraedaSkeleton(width: 80, height: 14),
              SizedBox(height: 12),
              BaraedaSkeleton(width: 160, height: 52),
              SizedBox(height: 12),
              BaraedaSkeleton(width: 120, height: 20),
              SizedBox(height: 16),
              BaraedaSkeleton(height: 48),
            ],
          ),
        ),
        SizedBox(height: 24),
        BaraedaSkeletonList(count: 2),
      ],
    );
  }
}

/// 오늘 목록을 못 받았다 — 다시 시도 + 학원에 바로 전화(번호가 있을 때).
class _HomeError extends StatelessWidget {
  const new({required this.noun, required this.urgent, required this.onRetry});

  final String noun;
  final String urgent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 40),
        EmptyState(
          icon: 'wifi-off',
          title: '오늘 $noun를 불러오지 못했어요',
          body: '인터넷 연결을 확인하고 다시 시도해 주세요. 연결되면 자동으로 다시 불러와요.',
          action: BaraedaButton(
            label: '다시 시도',
            icon: 'refresh',
            onPressed: onRetry,
          ),
        ),
        const SizedBox(height: 32),
        AcademyCallCard(lead: urgent),
      ],
    );
  }
}

/// 오늘 배정된 운행이 없다.
class _HomeEmpty extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(academyContactProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 40),
        EmptyState(
          icon: 'calendar',
          title: '오늘 배정된 운행이 없어요',
          body: '배정이 바뀌면 알림으로 알려 드려요. 잘못 배정된 것 같으면 학원에 문의해 주세요.',
          action: looksLikePhoneNumber(contact)
              ? BaraedaButton(
                  label: '학원에 전화 · ${contact!.trim()}',
                  icon: 'phone',
                  variant: BaraedaButtonVariant.secondary,
                  onPressed: () => unawaited(
                    ref.read(uriOpenerProvider)(
                      Uri(scheme: 'tel', path: contact.trim()),
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
