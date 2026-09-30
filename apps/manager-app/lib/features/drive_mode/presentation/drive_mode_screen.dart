import 'dart:async';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/remaining_stops_list.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

/// DriveMode — 운행 시작(§4.4) · 승하차지 도착 처리(§4.5), 기사 전용
/// (M-08·M-10, role_policy.dart `canOperateRun`).
///
/// 다음 처리 대상은 §4.2 명단의 `arrived_at` 로 계산한다(`drive_mode_providers.dart`
/// 참고). 가운데 지도(R32 M1)는 [DriveMapPanel] — 노선·승하차지·버스 위치를 보인다.
/// 도착·종료 대형 버튼은 지도 아래가 아니라 화면 아래에 붙여 둔다 — 지도가 커져도 밀려나지 않는다.
class DriveModeScreen extends ConsumerStatefulWidget {
  const DriveModeScreen({super.key});

  @override
  ConsumerState<DriveModeScreen> createState() => _DriveModeScreenState();
}

class _DriveModeScreenState extends ConsumerState<DriveModeScreen> {
  bool _submitting = false;
  String? _errorMessage;

  /// [initState] 에서 받아 둔 포트 — `ConsumerState.dispose()` 안에서는
  /// `ref.read` 가 안전하지 않다(위젯이 이미 unmount 되는 중이라 Riverpod
  /// 이 `StateError` 를 던진다). 필드에 저장해 두면 dispose 에서 이 값만
  /// 쓰면 되고 `ref` 를 다시 묻지 않는다.
  late final WakelockPort _wakelockPort;

  /// 운행 시작 전(송신기가 아직 안 도는 동안) 화면이 직접 재확인해 둔 위치 권한·서비스 상태(M2-02).
  /// 운행 중에는 송신기의 상태(`PositionTransmission.availability`)가 우선한다.
  PositionAvailability? _preStartAvailability;
  Timer? _availabilityTimer;

  /// 위치 송신 상태의 [PositionAvailability] 를 화면 문구로 옮긴다 — 정상(`available`)이거나
  /// 아직 모르면(`null`) 아무것도 보여주지 않는다.
  String? _positionGuidance(PositionAvailability? availability) =>
      switch (availability) {
        PositionAvailability.permissionDenied =>
          '위치 권한이 없어 위치를 보낼 수 없습니다. 설정에서 위치 권한을 허용해 주세요',
        PositionAvailability.serviceDisabled =>
          '기기 위치 서비스가 꺼져 있어 위치를 보낼 수 없습니다. 설정에서 위치 서비스를 켜 주세요',
        PositionAvailability.available || null => null,
      };

  @override
  void initState() {
    super.initState();
    // F2 — 백그라운드 위치 송신은 범위 밖이라, 운행 화면이 켜져 있는
    // 것이 지금 GPS 송신을 지키는 유일한 수단이다(M-B 2항). 화면에
    // 머무는 동안은 역할·운행 상태와 무관하게 켠다 — `_buildBody` 가
    // 이 화면에 들어오는 모든 사용자(기사·동승자)에게 공통이다.
    _wakelockPort = ref.read(wakelockPortProvider);
    unawaited(_wakelockPort.enable());
    // 위치 송신은 이 화면이 소유하지 않는다 — 앱 전역 송신기(`position_transmitter.dart`)가 운행 중인
    // 기사 회차에 맞춰 돈다(R33 M1). 여기서는 기사에게 위치 권한 확인만 미리 띄우려고 소스를 만들어 둔다
    // (운행을 시작하는 순간 권한 창이 뜨지 않게).
    if (ref.read(roleCapabilitiesProvider)?.canTransmitPosition ?? false) {
      final source = ref.read(positionSourceProvider);
      // M2-02 — 출발 뒤에야 송신 실패를 알지 않게, 시작 전에도 권한·서비스를 주기마다 다시 본다.
      // 스트림은 켜지 않는다(포그라운드 서비스 알림은 운행 중에만).
      _availabilityTimer = Timer.periodic(
        PositionConstants.transmissionInterval,
        (_) => unawaited(_recheckAvailability(source)),
      );
    }
  }

  Future<void> _recheckAvailability(PositionSource source) async {
    await source.recheck();
    if (!mounted || source.availability == _preStartAvailability) return;
    setState(() => _preStartAvailability = source.availability);
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    unawaited(_wakelockPort.disable());
    super.dispose();
  }

  Future<void> _startRun(String runId) async {
    // 시작하면 노선이 잠기고 학부모·관계자에게 알림이 나간다 — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    final confirmed = await confirmAction(
      context,
      title: '운행을 시작할까요?',
      body: '시작하면 학부모·관계자에게 운행 시작 알림이 나가고 노선이 잠깁니다',
      confirmLabel: '시작하기',
    );
    if (!confirmed || !mounted) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(driveModeRepositoryProvider).startRun(runId);
      // 요청 중에 화면이 닫혀도 서버는 이미 시작을 반영했다 — 컨테이너로 갱신한다(F06-16).
      container
        ..invalidate(todayRunsProvider)
        ..invalidate(driveModeRosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
      // M4(Ruling 340) — 취소된 회차는 §4.1 목록에서 빠져야 하는데, 목록을
      // 다시 불러오지 않으면 이미 취소된 카드가 화면에 그대로 남는다.
      if (failure case ApiFailure(code: 'RUN_CANCELED')) {
        container.invalidate(todayRunsProvider);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _arriveStop(
    String runId,
    String stopId, {
    bool isLast = false,
  }) async {
    // 마지막 승하차지의 도착 처리는 곧 운행 종료다(C-15) — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    // 그 앞 승하차지는 운전 중에 자주 누르는 조작이라 묻지 않는다.
    if (isLast) {
      final confirmed = await confirmAction(
        context,
        title: '마지막 승하차지입니다',
        body: '도착 처리하면 운행 종료 절차가 시작됩니다. 되돌릴 수 없습니다.',
        confirmLabel: '도착했습니다',
      );
      if (!confirmed || !mounted) return;
    }
    final container = ProviderScope.containerOf(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(driveModeRepositoryProvider)
          .arriveStop(runId: runId, stopId: stopId);
      // 요청 중에 화면이 닫혀도 서버는 이미 도착을 반영했다 — 화면 생존과 무관한 갱신은 컨테이너로 한다
      // (닫힌 화면의 `ref` 는 쓸 수 없다, F06-16).
      container.invalidate(todayRunsProvider);
      if (result.isFinal) {
        // 종점에 닿았으니 위치 송신은 여기서 끝난다 — 하원 잔류로 서버 회차가 아직 `moving` 이어도 그렇다.
        container.read(transmissionEndedRunIdProvider.notifier).state = runId;
        container.read(lastArriveResultProvider.notifier).state = result;
        if (!mounted) return;
        unawaited(context.push(AppRoutes.runEnd));
      } else {
        container.invalidate(driveModeRosterProvider);
        if (!mounted) return;
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
    final transmission = ref.watch(positionTransmitterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('운행 모드'),
        actions: [
          // 비상(M-15, R32 M2) — 출발 전(확정)에도 눌린다.
          const EmergencyButton(),
          // 노선 지도(M-04·M-09)는 기사 전용이고, 기사가 홈에서 들어오는 화면은 여기뿐이다 —
          // 명단 화면에만 두면 그 화면은 동승자만 들어가서 아무도 닿지 못한다(2026-09-23).
          TextButton(
            onPressed: () => unawaited(context.push(AppRoutes.routeMap)),
            child: const Text('노선 지도'),
          ),
        ],
      ),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId, run, transmission),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String runId,
    ManagerRun? run,
    PositionTransmission transmission,
  ) {
    final rosterAsync = ref.watch(driveModeRosterProvider);
    // 지도 높이는 화면 비율로 정한다 — 작은 화면(360×640)에서도 아래 대형 버튼이 밀리지 않는다.
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.3).clamp(
      140.0,
      320.0,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
                    statusLabel: run.runStatus == RunStatus.moving
                        ? '운행 중'
                        : '확정',
                    origin: run.origin,
                    destination: run.destination,
                  ),
                const SizedBox(height: 16),
                DriveMapPanel(
                  height: mapHeight,
                  busPosition: transmission.busPosition,
                ),
                const SizedBox(height: 16),
                // 노선 변경 확인(M-04, R32 M4) — 기사는 명단 화면에 가지 않으므로 여기서 확인한다.
                ChangeAckBanner(
                  runId: runId,
                  ackRequired: run?.ackRequired ?? false,
                ),
                // rosterAsync.when(...) 의 모든 분기 바깥 — "명단 없음"(정상)과
                // "연결 끊김"(비정상)을 구별해야 한다(목표 9, ManagerChannelBanner
                // 문서 참고).
                ManagerChannelBanner(runId: runId),
                if (_positionGuidance(
                      transmission.availability ?? _preStartAvailability,
                    )
                    case final guidance?) ...[
                  AlertBanner(tone: AlertTone.missed, body: guidance),
                  const SizedBox(height: 12),
                ],
                // 남은 승하차지(M-08, R32 M5) — 조회 전용. 끝난 운행에는 남은 곳이 없다.
                if (rosterAsync.value case final roster?
                    when run?.runStatus != RunStatus.finished)
                  RemainingStopsList(roster: roster),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  AlertBanner(tone: AlertTone.missed, body: _errorMessage),
                  const SizedBox(height: 12),
                ],
                rosterAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Text('명단을 불러오지 못했습니다: ${describeError(error)}'),
                  data: (roster) => _buildActionArea(runId, run, roster),
                ),
              ],
            ),
          ),
        ),
      ],
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
        // 언제부터 되는지를 알린다(R32 M10) — 이미 지났으면 지났다고 한다.
        return Text(
          now.isBefore(run.startWindowFrom)
              ? '${DateFormat('HH:mm').format(run.startWindowFrom.toLocal())} '
                    '부터 시작할 수 있습니다 (출발 ±10분)'
              : '운행 시작 가능 시간(출발 ±10분)이 지났습니다',
        );
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
            : () => _arriveStop(
                runId,
                nextStop.stopId,
                isLast: isLastRemainingStop(roster, nextStop),
              ),
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
