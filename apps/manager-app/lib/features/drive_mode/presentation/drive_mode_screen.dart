import 'dart:async';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:manager_app/features/position/data/models/position_request.dart';
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

  /// §4.12 위치 전송 주기 타이머 — `_syncPositionTransmission` 이 운행 중
  /// 여부·역할에 맞춰 시작·정지를 맡는다. `null` 이면 지금은 전송하지 않는
  /// 상태.
  Timer? _positionTimer;

  /// 마지막 전송 시도에서 본 [PositionSource.availability] — 권한 거부·
  /// 위치 서비스 꺼짐이면 화면에 안내 한 줄을 보여준다(LOC-01 할 일 2).
  /// 전송 타이머가 돌 때만 갱신되므로(2초 주기), 타이머가 아예 안 도는
  /// 상태(이동 중이 아니거나 동승자)에서는 계속 `null` — 안내를 보여줄
  /// 근거가 없다.
  PositionAvailability? _positionAvailability;

  /// 기사 단말이 마지막으로 잰 좌표 — 지도의 버스 마커 자리(R32 M1). 위치 전송 주기(2초)마다
  /// 갱신된다. 서버 방송에는 좌표가 없고(§7 매니저 채널) 기사 단말이 이미 스스로 재고 있어
  /// 별도 요청을 만들지 않고 그 값을 그대로 쓴다.
  ({double lat, double lng})? _busPosition;

  /// [initState] 에서 받아 둔 포트 — `ConsumerState.dispose()` 안에서는
  /// `ref.read` 가 안전하지 않다(위젯이 이미 unmount 되는 중이라 Riverpod
  /// 이 `StateError` 를 던진다). 필드에 저장해 두면 dispose 에서 이 값만
  /// 쓰면 되고 `ref` 를 다시 묻지 않는다.
  late final WakelockPort _wakelockPort;

  /// LOC-01 배경 송신(`Ruling 360`) — 위치 스트림(Android 포그라운드
  /// 서비스 알림 · iOS 백그라운드 갱신)을 [initState] 에서 시작해 둔
  /// 인스턴스. 기사만 채운다(`canTransmitPosition` 게이트) — 동승자는
  /// `null` 로 남아 [PositionSource.start] 를 한 번도 부르지 않는다.
  /// 위 [_wakelockPort] 와 같은 이유로 `dispose()` 가 쓸 수 있게 필드에
  /// 저장해 둔다.
  PositionSource? _positionSource;

  /// [_positionAvailability] 를 화면 문구로 옮긴다 — 정상(`available`)이거나
  /// 아직 모르면(`null`) 아무것도 보여주지 않는다.
  String? get _positionGuidance => switch (_positionAvailability) {
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
    // LOC-01 배경 송신(Ruling 360) — 위치 스트림은 화면 진입 시 기사만
    // 시작한다(위 wakelock 과 달리 동승자는 시작하지 않는다, BRIEF-BG
    // 할 일 3 · 지금 canTransmitPosition 게이트와 같은 기준).
    if (ref.read(roleCapabilitiesProvider)?.canTransmitPosition ?? false) {
      final source = ref.read(positionSourceProvider)..start();
      _positionSource = source;
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    unawaited(_wakelockPort.disable());
    _positionSource?.stop();
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
        PositionConstants.transmissionInterval,
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
    final source = ref.read(positionSourceProvider);
    if (mounted && source.availability != _positionAvailability) {
      setState(() => _positionAvailability = source.availability);
    }
    final sample = source.sample();
    if (sample == null) return;
    if (mounted) {
      setState(() => _busPosition = (lat: sample.lat, lng: sample.lng));
    }
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
    // 시작하면 노선이 잠기고 학부모·관계자에게 알림이 나간다 — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    final confirmed = await confirmAction(
      context,
      title: '운행을 시작할까요?',
      body: '시작하면 학부모·관계자에게 운행 시작 알림이 나가고 노선이 잠깁니다',
      confirmLabel: '시작하기',
    );
    if (!confirmed || !mounted) return;
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
      // M4(Ruling 340) — 취소된 회차는 §4.1 목록에서 빠져야 하는데, 목록을
      // 다시 불러오지 않으면 이미 취소된 카드가 화면에 그대로 남는다.
      if (failure case ApiFailure(code: 'RUN_CANCELED')) {
        ref.invalidate(todayRunsProvider);
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
    // 운행 종료(§4.10 이 `finished` 로 옮기는 순간) — 화면은 종료 보고서로
    // 이동하지 않고 스택에 남을 수 있어(FIX-MF.md §2) dispose 만으로는
    // 늦다. 위치 스트림을 여기서 바로 멈춘다(Ruling 360, BRIEF-BG 할 일 3).
    if (run?.runStatus == RunStatus.finished) {
      _positionSource?.stop();
    }

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
          : _buildBody(context, runId, run),
    );
  }

  Widget _buildBody(BuildContext context, String runId, ManagerRun? run) {
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
                    currentStop: run.origin,
                    nextStop: run.destination,
                  ),
                const SizedBox(height: 16),
                DriveMapPanel(height: mapHeight, busPosition: _busPosition),
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
                if (_positionGuidance != null) ...[
                  AlertBanner(tone: AlertTone.missed, body: _positionGuidance),
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
