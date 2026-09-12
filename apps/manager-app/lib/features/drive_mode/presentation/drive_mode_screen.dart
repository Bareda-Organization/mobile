import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
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

  /// §4.12 위치 전송 주기 타이머 — `_syncPositionTransmission` 이 운행 중
  /// 여부·역할에 맞춰 시작·정지를 맡는다. `null` 이면 지금은 전송하지 않는
  /// 상태.
  Timer? _positionTimer;

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  /// [build] 가 매번 호출해도 안전하도록 멱등으로 짰다 — 이미 원하는
  /// 상태(타이머 있음/없음)면 아무 것도 하지 않는다.
  void _syncPositionTransmission({
    required String? runId,
    required bool shouldTransmit,
  }) {
    final wantTimer = shouldTransmit && runId != null;
    if (wantTimer && _positionTimer == null) {
      _positionTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(_sendPositionTick(runId)),
      );
    } else if (!wantTimer && _positionTimer != null) {
      _positionTimer!.cancel();
      _positionTimer = null;
    }
  }

  /// 주기마다 좌표를 읽어 §4.12 로 올린다. 화면 액션이 아니라 배경
  /// 텔레메트리라 실패해도 `_errorMessage` 를 세우지 않는다 — 다음 주기
  /// 전송이 실패를 대신 만회하고, 매번 배너를 띄우면 운전 중 방해만 된다.
  Future<void> _sendPositionTick(String runId) async {
    final sample = ref.read(positionSourceProvider).sample();
    if (sample == null) return;
    try {
      await ref
          .read(positionRepositoryProvider)
          .sendPosition(
            runId: runId,
            request: PositionRequest(
              lat: sample.lat,
              lng: sample.lng,
              recordedAt: sample.recordedAt,
              speed: sample.speed,
              heading: sample.heading,
            ),
          );
    } on Failure {
      // 배경 전송 실패 — 다음 주기가 대신한다(§1.9 는 화면 액션의 낙관적
      // 표시를 금지할 뿐, 이 텔레메트리는 화면 액션이 아니다).
    }
  }

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
    final canTransmitPosition =
        ref.watch(roleCapabilitiesProvider)?.canTransmitPosition ?? false;
    _syncPositionTransmission(
      runId: runId,
      shouldTransmit: canTransmitPosition && run?.runStatus == RunStatus.moving,
    );

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
      // 시각은 `clockProvider` 로 주입받는다 — 위젯 안에서 `DateTime.now()`
      // 를 직접 부르지 않는다(CONVENTIONS_FLUTTER.md §9, 이월 11).
      final now = ref.watch(clockProvider).now();
      final withinWindow =
          !now.isBefore(run.startWindowFrom) && !now.isAfter(run.startWindowTo);
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
