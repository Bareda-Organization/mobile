import 'dart:async';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';
import 'package:manager_app/features/notifications/presentation/widgets/notification_bell_button.dart';

/// ManagerHome — 오늘의 담당 회차 목록(§4.1, M-02·M-07).
///
/// 세 가지 상태(로딩·성공·실패)를 `AsyncValue.when` 으로 그린다
/// (CONVENTIONS_FLUTTER.md §6). 탭하면 [selectedRunIdProvider] 에 회차를
/// 담고 역할에 따라 DriveMode(기사) 또는 StopRoster(동승자)로 이동한다 —
/// 두 화면 다 "지금 선택된 회차 하나" 만 다루므로 라우터 path parameter
/// 대신 provider 로 넘긴다(보고서 § 판단 근거 참고).
///
/// 열려 있는 동안 [todayRunsRefreshInterval] 마다, 앱이 백그라운드에서 돌아올 때 목록을 다시
/// 받는다 — 확정은 서버 배치가 시각에 맞춰 바꾸므로(F06-13) 한 번 받은 목록은 곧 낡는다.
class ManagerHomeScreen extends ConsumerStatefulWidget {
  const ManagerHomeScreen({super.key});

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
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final hasMovingRun =
        runsAsync.value?.any((run) => run.runStatus == RunStatus.moving) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘 운행'),
        actions: [
          // 비상(M-15, R32 M2) — 기사·동승자 모두, 확정된 회차가 있으면 운행 중이 아니어도 보낸다.
          EmergencyButton(homeRuns: runsAsync.value),
          // 알림 목록(NTF-08, R46) — 안 읽은 수 배지. 운행 중 화면에는 두지 않는다(운전 중 시선).
          const NotificationBellButton(),
          // 비밀번호 변경(AUTH-07 · UF-X-09, R32 M13) — 기사·동승자 공통.
          BaraedaIconButton(
            icon: 'lock',
            label: '비밀번호 변경',
            onPressed: () => unawaited(context.push(AppRoutes.passwordChange)),
          ),
          // 로그아웃(2026-09-23, 확인 대화 2026-09-26 추가·AUTH-09) —
          // 역할이 비면 라우터가 로그인 화면으로 보낸다. 기사·동승자 둘 다
          // 이 화면을 거쳐 운행 화면으로 들어가므로(§4.1) 둘 다 닿는 자리다.
          TextButton(
            onPressed: () => unawaited(_confirmSignOut(context, hasMovingRun)),
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(todayRunsProvider.future),
        child: runsAsync.when(
          // 주기 갱신 중에는 받아 둔 목록을 그대로 두고 바꿔 그린다 — 30초마다 스피너가 뜨지 않게.
          skipLoadingOnReload: true,
          // 갱신이 실패해도 마지막으로 받은 목록을 지우지 않는다 — 오류는 목록 위에 따로 알린다(R46).
          skipError: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: WordWrapText(
                  '오늘 운행을 불러오지 못했습니다: ${describeError(error)}',
                ),
              ),
            ],
          ),
          data: (runs) {
            final refreshError = runsAsync.error;
            final staleBanner = refreshError == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AlertBanner(
                      tone: AlertTone.missed,
                      body:
                          '최신 운행을 불러오지 못했습니다 · 이전 목록을 보고 있습니다: '
                          '${describeError(refreshError)}',
                      action: BaraedaButton(
                        label: '다시 시도',
                        size: BaraedaButtonSize.sm,
                        variant: BaraedaButtonVariant.secondary,
                        onPressed: () => ref.invalidate(todayRunsProvider),
                      ),
                    ),
                  );
            if (runs.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ?staleBanner,
                  const SizedBox(height: 120),
                  const Center(child: WordWrapText('오늘 배정된 운행이 없습니다')),
                ],
              );
            }
            final movingCount = runs
                .where((run) => run.runStatus == RunStatus.moving)
                .length;
            final finishedCount = runs
                .where((run) => run.runStatus == RunStatus.finished)
                .length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ?staleBanner,
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: '오늘 배정',
                        value: '${runs.length}',
                        unit: '건',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: '운행 중',
                        value: '$movingCount',
                        unit: '건',
                        tone: StatCardTone.moving,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: '종료',
                        value: '$finishedCount',
                        unit: '건',
                        tone: StatCardTone.boarded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final run in runs) ...[
                  RunSummaryCard(
                    bus: run.busNo,
                    leg: run.direction == RunDirection.toAcademy ? '등원' : '하원',
                    status: _statusOf(run.runStatus),
                    statusLabel: _statusLabelOf(run),
                    eta: _departLabel(run.departTime),
                    origin: run.origin,
                    destination: run.destination,
                    onTap: run.confirmed
                        ? () => _openRun(context, run, capabilities)
                        : null,
                  ),
                  // 확정 전 카드는 눌러도 반응이 없다 — 이유와 열리는 시각을 알린다(M-02, R32 M9).
                  if (!run.confirmed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: WordWrapText(
                        switch (run.confirmAt) {
                          null => '출발 30분 전 확정 후 열립니다',
                          final at =>
                            '출발 30분 전 확정 후 열립니다 '
                                '(${DateFormat('HH:mm').format(at.toLocal())})',
                        },
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  BaraedaStatus _statusOf(RunStatus status) => switch (status) {
    RunStatus.idle || RunStatus.confirmed => BaraedaStatus.idle,
    RunStatus.moving => BaraedaStatus.moving,
    RunStatus.finished => BaraedaStatus.boarded,
  };

  String _statusLabelOf(ManagerRun run) {
    if (!run.confirmed) return '확정 전';
    return switch (run.runStatus) {
      RunStatus.idle => '확정 전',
      RunStatus.confirmed => '확정',
      RunStatus.moving => '운행 중',
      RunStatus.finished => '종료',
    };
  }

  void _openRun(
    BuildContext context,
    ManagerRun run,
    RoleCapabilities? capabilities,
  ) {
    ref.read(selectedRunIdProvider.notifier).state = run.runId;
    final canOperateRun = capabilities?.canOperateRun ?? false;
    final destination = canOperateRun ? AppRoutes.driveMode : AppRoutes.roster;
    unawaited(context.push(destination));
  }

  /// 아직 서버에 보내지 못한 오프라인 대기 요청 수. 읽지 못하면 0 으로 보고 로그아웃을 막지 않는다.
  Future<int> _pendingCount() async {
    try {
      return (await ref.read(offlineQueueRepositoryProvider).fetchPending())
          .length;
    } on Object {
      return 0;
    }
  }

  /// 로그아웃 확인 대화상자(AUTH-09) — [hasMovingRun] 이면 명단·위치 송신이
  /// 멈춘다는 경고를 덧붙인다(`USER_FLOWS` UF-O-04 와 같은 이유 — 로그인
  /// 유지 중 로그아웃하면 명단 조회가 끊겨 하차 처리가 중단된다). 확인해야만
  /// [signOut] 을 부른다 — 그 함수는 서버 성패와 무관하게 토큰을 지우고,
  /// 라우터가 그 변화를 보고 로그인 화면으로 보낸다(판정은 라우터 한 곳).
  Future<void> _confirmSignOut(
    BuildContext context,
    bool hasMovingRun,
  ) async {
    // 창은 바로 띄우고 건수는 읽히는 대로 채운다 — 대기열 읽기가 로그아웃 확인을 막지 않게.
    final pendingCount = _pendingCount();
    final confirmed = await showBaraedaConfirmDialog(
      context: context,
      title: '로그아웃하시겠습니까?',
      confirmLabel: '로그아웃',
      content: FutureBuilder<int>(
        future: pendingCount,
        initialData: 0,
        builder: (context, snapshot) => WordWrapText(
          [
            if (hasMovingRun)
              '운행 중에 로그아웃하면 명단·위치 송신이 멈춥니다'
            else
              '다시 로그인해야 이 앱을 계속 쓸 수 있습니다',
            // M2-01 — 큐에는 계정 열이 없어 로그아웃하면 비운다(F06-02). 있을 때만 알린다.
            if ((snapshot.data ?? 0) > 0)
              '아직 보내지 못한 처리 ${snapshot.data}건은 버려집니다',
          ].join('\n'),
          style: BaraedaTypography.bodySm.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
    if (confirmed) {
      try {
        await signOut(ref);
      } on Object {
        // signOut 은 서버 호출 실패도 그대로 다시 던진다(`account_session.dart`
        // 문서 — 토큰은 이미 finally 에서 지워졌다). 여기서 보여줄 추가
        // 동작이 없다 — 라우터가 역할 소실을 보고 로그인 화면으로 보낸다.
      }
    }
  }
}

/// 카드에 적는 출발 시각 — 시각만 크게 있으면 출발인지 도착인지 모른다(R46).
String _departLabel(DateTime departTime) =>
    '출발 ${DateFormat('HH:mm').format(departTime.toLocal())}';
