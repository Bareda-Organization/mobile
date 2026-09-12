import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// DriveMode — 운행 시작(§4.4) · 승하차지 도착 처리(§4.5), 기사 전용
/// (M-08·M-10, role_policy.dart `canOperateRun`).
///
/// §4.3(노선 정보 API)은 이번 라운드 범위 밖이라 지도 없이, §4.2 명단의
/// `arrived_at` 로 다음 처리 대상을 계산한다(`drive_mode_providers.dart`
/// 참고). 지도 자리는 비워 둔 화면 폭 전체 placeholder 뿐이다 — 실제 지도
/// SDK 연동은 하지 않는다(브리프 제약).
class DriveModeScreen extends ConsumerStatefulWidget {
  const DriveModeScreen({super.key});

  @override
  ConsumerState<DriveModeScreen> createState() => _DriveModeScreenState();
}

class _DriveModeScreenState extends ConsumerState<DriveModeScreen> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _startRun(String runId) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(driveModeRepositoryProvider).startRun(runId);
      ref
        ..invalidate(todayRunsProvider)
        ..invalidate(driveModeRosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _arriveStop(String runId, String stopId) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(driveModeRepositoryProvider)
          .arriveStop(runId: runId, stopId: stopId);
      ref.invalidate(todayRunsProvider);
      if (!mounted) return;
      if (result.isFinal) {
        ref.read(lastArriveResultProvider.notifier).state = result;
        unawaited(context.push(AppRoutes.runEnd));
      } else {
        ref.invalidate(driveModeRosterProvider);
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(driveModeRunProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('운행 모드')),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId, run),
    );
  }

  Widget _buildBody(BuildContext context, String runId, ManagerRun? run) {
    final rosterAsync = ref.watch(driveModeRosterProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (run != null)
            RunSummaryCard(
              bus: run.busNo,
              leg: run.direction == RunDirection.toAcademy ? '등원' : '하원',
              status: run.runStatus == RunStatus.moving
                  ? BaraedaStatus.moving
                  : BaraedaStatus.idle,
              statusLabel: run.runStatus == RunStatus.moving ? '운행 중' : '확정',
              currentStop: run.origin,
              nextStop: run.destination,
            ),
          const SizedBox(height: 16),
          // 지도 자리 — 실제 지도 SDK 는 이번 범위 밖(브리프 제약).
          Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('지도 자리 — 연동은 다음 라운드'),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
            const SizedBox(height: 12),
          ],
          rosterAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('명단을 불러오지 못했습니다: $error'),
            data: (roster) => _buildActionArea(runId, run, roster),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(
    String runId,
    ManagerRun? run,
    RosterResponse roster,
  ) {
    if (run == null) return const SizedBox.shrink();

    if (run.runStatus == RunStatus.idle ||
        run.runStatus == RunStatus.confirmed) {
      // 서버가 창(출발 ±10분) 밖 호출을 `START_WINDOW_CLOSED` 로 막고
      // 있어(failure_messages.dart) 실패 문구로도 알 수 있지만, 미리
      // 버튼을 눌러 두게 두면 매번 실패 왕복이 생긴다. `run` 에 이미
      // 창 정보가 있어(§4.1) 화면에서도 같은 판정을 미리 보여준다.
      final now = DateTime.now();
      final withinWindow =
          !now.isBefore(run.startWindowFrom) &&
          !now.isAfter(run.startWindowTo);
      if (!withinWindow) {
        return const Text('운행 시작 가능 시간(출발 ±10분)이 아닙니다');
      }
      return BaraedaButton(
        label: '운행 시작',
        size: BaraedaButtonSize.lg,
        onPressed: _submitting ? null : () => _startRun(runId),
      );
    }

    if (run.runStatus == RunStatus.moving) {
      final nextStop = nextUnarrivedStop(roster);
      if (nextStop == null) {
        return const Text('모든 승하차지 도착 처리가 끝났습니다');
      }
      return BaraedaButton(
        label: '${nextStop.name} 도착 처리',
        size: BaraedaButtonSize.lg,
        onPressed: _submitting
            ? null
            : () => _arriveStop(runId, nextStop.stopId),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('이미 종료된 운행입니다'),
        const SizedBox(height: 8),
        BaraedaButton(
          label: '종료 보고서 보기',
          onPressed: () => unawaited(context.push(AppRoutes.runEnd)),
        ),
      ],
    );
  }
}
