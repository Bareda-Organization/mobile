import 'dart:async';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';

/// ManagerHome — 오늘의 담당 회차 목록(§4.1, M-02·M-07).
///
/// 세 가지 상태(로딩·성공·실패)를 `AsyncValue.when` 으로 그린다
/// (CONVENTIONS_FLUTTER.md §6). 탭하면 [selectedRunIdProvider] 에 회차를
/// 담고 역할에 따라 DriveMode(기사) 또는 StopRoster(동승자)로 이동한다 —
/// 두 화면 다 "지금 선택된 회차 하나" 만 다루므로 라우터 path parameter
/// 대신 provider 로 넘긴다(보고서 § 판단 근거 참고).
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // 로그아웃(2026-09-23, 확인 대화 2026-09-26 추가·AUTH-09) —
          // 역할이 비면 라우터가 로그인 화면으로 보낸다. 기사·동승자 둘 다
          // 이 화면을 거쳐 운행 화면으로 들어가므로(§4.1) 둘 다 닿는 자리다.
          TextButton(
            onPressed: () =>
                unawaited(_confirmSignOut(context, ref, hasMovingRun)),
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(todayRunsProvider.future),
        child: runsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('오늘 운행을 불러오지 못했습니다: ${describeError(error)}')),
            ],
          ),
          data: (runs) {
            if (runs.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('오늘 배정된 운행이 없습니다')),
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
                    eta: DateFormat('HH:mm').format(run.departTime.toLocal()),
                    currentStop: run.origin,
                    nextStop: run.destination,
                    onTap: run.confirmed
                        ? () => _openRun(context, ref, run, capabilities)
                        : null,
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
    WidgetRef ref,
    ManagerRun run,
    RoleCapabilities? capabilities,
  ) {
    ref.read(selectedRunIdProvider.notifier).state = run.runId;
    final canOperateRun = capabilities?.canOperateRun ?? false;
    final destination = canOperateRun ? AppRoutes.driveMode : AppRoutes.roster;
    unawaited(context.push(destination));
  }

  /// 로그아웃 확인 대화상자(AUTH-09) — [hasMovingRun] 이면 명단·위치 송신이
  /// 멈춘다는 경고를 덧붙인다(`USER_FLOWS` UF-O-04 와 같은 이유 — 로그인
  /// 유지 중 로그아웃하면 명단 조회가 끊겨 하차 처리가 중단된다). 확인해야만
  /// [signOut] 을 부른다 — 그 함수는 서버 성패와 무관하게 토큰을 지우고,
  /// 라우터가 그 변화를 보고 로그인 화면으로 보낸다(판정은 라우터 한 곳).
  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    bool hasMovingRun,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃하시겠습니까?'),
        content: Text(
          hasMovingRun
              ? '운행 중에 로그아웃하면 명단·위치 송신이 멈춥니다'
              : '다시 로그인해야 이 앱을 계속 쓸 수 있습니다',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
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
