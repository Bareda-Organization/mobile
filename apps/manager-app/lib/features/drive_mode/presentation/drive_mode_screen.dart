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
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/bottom_notice_stack.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/presentation/open_navigation.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
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
  const new({super.key});

  @override
  ConsumerState<DriveModeScreen> createState() => _DriveModeScreenState();
}

class _DriveModeScreenState extends ConsumerState<DriveModeScreen> {
  bool _submitting = false;
  String? _errorMessage;

  /// 도착 처리에 성공한 직후 버튼을 잠그는 시간 — 신호 대기 중 더블탭이 다음 승하차지까지 처리하는 것을 막는다.
  /// 되돌리는 API 가 없어 한 번 나간 도착은 취소할 수 없다(R46).
  static const _arriveLockDuration = Duration(seconds: 2);

  /// 토스트가 도착 처리 단추 줄 위에 뜨는 높이 — 위 여백 12 + 단추 64 + 아래 여백 12 + 간격 8.
  static const _toastAboveActionBar = 96.0;
  bool _arriveLocked = false;
  Timer? _arriveLockTimer;

  /// 외부 내비를 여는 중 — 겹쳐 누르지 않게 한다. 열고 나서 서버가 잘랐다고 알리면 그 안내를 [_navNotice] 에 둔다.
  bool _navigating = false;
  String? _navNotice;

  /// 카카오내비가 설치돼 있지 않다 — 안내 배너에 [설치하기] 를 붙인다.
  bool _naviNotInstalled = false;

  /// [initState] 에서 받아 둔 포트 — `ConsumerState.dispose()` 안에서는
  /// `ref.read` 가 안전하지 않다(위젯이 이미 unmount 되는 중이라 Riverpod
  /// 이 `StateError` 를 던진다). 필드에 저장해 두면 dispose 에서 이 값만
  /// 쓰면 되고 `ref` 를 다시 묻지 않는다.
  late final WakelockPort _wakelockPort;

  /// 송신기가 아직 안 도는 동안(막 열렸거나 송신이 멈췄을 때) 화면이 직접 재확인한 위치 권한·서비스 상태(M2-02).
  /// 송신 중에는 송신기의 상태(`PositionTransmission.availability`)가 우선한다.
  PositionAvailability? _recheckedAvailability;
  Timer? _availabilityTimer;

  /// 기기에 저장해 둔 명단(`RosterResponse.cachedAt`)으로 다음 곳을 가리키는 동안 서버에서 다시 받아 보는
  /// 주기(M-M3) — 연결이 돌아오면 서버 명단으로 바뀐다. 서버에서 받은 명단이면 아무것도 하지 않는다.
  static const _cachedRetryInterval = Duration(seconds: 15);
  Timer? _cachedRetryTimer;

  /// 위치 송신 상태의 [PositionAvailability] 를 화면 문구로 옮긴다 — 정상(`available`)이거나
  /// 아직 모르면(`null`) 아무것도 보여주지 않는다.
  String? _positionGuidance(PositionAvailability? availability) =>
      switch (availability) {
        PositionAvailability.permissionDenied => '위치 권한이 꺼져 있어요',
        PositionAvailability.serviceDisabled => '기기 위치 서비스가 꺼져 있어요',
        PositionAvailability.available || null => null,
      };

  String? _positionGuidanceBody(PositionAvailability? availability) =>
      availability == null || availability == PositionAvailability.available
      ? null
      : '학부모 화면에 버스 위치가 안 보여요.';

  @override
  void initState() {
    super.initState();
    // F2 — 백그라운드 위치 송신은 범위 밖이라, 운행 화면이 켜져 있는
    // 것이 지금 GPS 송신을 지키는 유일한 수단이다(M-B 2항).
    _wakelockPort = ref.read(wakelockPortProvider);
    unawaited(_wakelockPort.enable());
    _cachedRetryTimer = Timer.periodic(_cachedRetryInterval, (_) {
      if (ref.read(driveModeRosterProvider).value?.cachedAt != null) {
        ref.invalidate(driveModeRosterProvider);
      }
    });
    // 권한을 중간에 끄거나 위치 서비스가 꺼져도 주기마다 다시 본다. 스트림은 켜지 않는다.
    if (ref.read(roleCapabilitiesProvider)?.canTransmitPosition ?? false) {
      final source = ref.read(positionSourceProvider);
      unawaited(_recheck(source));
      _availabilityTimer = Timer.periodic(
        PositionConstants.transmissionInterval,
        (_) => unawaited(_recheck(source)),
      );
    }
  }

  Future<void> _recheck(PositionSource source) async {
    await source.recheck();
    if (!mounted || source.availability == _recheckedAvailability) return;
    setState(() => _recheckedAvailability = source.availability);
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _cachedRetryTimer?.cancel();
    _arriveLockTimer?.cancel();
    unawaited(_wakelockPort.disable());
    super.dispose();
  }

  Future<void> _arriveStop(
    String runId,
    String stopId, {
    required int order,
    required String name,
    required RunDirection direction,
    bool isLast = false,
    bool hasBoardedRiders = false,
  }) async {
    // 마지막 승하차지의 도착 처리는 등원이면 곧 운행 종료다(C-15) — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    // 하원은 도착만 기록되고 남은 학생이 있으면 종료가 보류된다. 그 앞 승하차지는 운전 중에 자주 누르는 조작이라
    // 묻지 않는다.
    if (isLast) {
      final toAcademy = direction == RunDirection.toAcademy;
      final confirmed = await confirmAction(
        context,
        title: '마지막 승하차지예요',
        body: toAcademy
            ? '도착 처리가 곧 운행 종료예요. 되돌릴 수 없어요.\n'
                  // 타고 있는 학생이 없으면 자동 하차할 사람이 없다 — 그 줄을 내지 않는다(A9).
                  '${hasBoardedRiders ? '· 등원 학생 전원이 자동으로 하차 처리돼요\n' : ''}'
                  '· 위치 보내기가 멈춰요\n'
                  '· 학원 관계자에게 운행 종료가 전달돼요'
            : '도착이 기록돼요. 되돌릴 수 없어요.\n'
                  '· 아직 버스에 있는 학생이 있으면 운행 종료가 보류돼요\n'
                  '· 동승자가 마지막 학생을 하차 처리하면 운행이 끝나요\n'
                  '· 남은 학생이 내릴 때까지 위치는 계속 보내요',
        confirmLabel: toAcademy ? '도착했어요 · 운행 종료' : '도착했어요',
        cancelLabel: '닫기',
      );
      if (!confirmed || !mounted) return;
    }
    final container = ProviderScope.containerOf(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final outcome = await ref
          .read(driveModeRepositoryProvider)
          .arriveStop(runId: runId, stopId: stopId);
      // 요청 중에 화면이 닫혀도 서버는 이미 도착을 반영했다 — 화면 생존과 무관한 갱신은 컨테이너로 한다
      // (닫힌 화면의 `ref` 는 쓸 수 없다, F06-16). 큐에 쌓인 도착이 이번 요청 앞에서 비워졌을 수 있다.
      container.invalidate(pendingRequestsProvider);
      switch (outcome) {
        case Queued():
          // 서버에 닿지 못해 기기에 저장만 됐다(859) — 아직 반영되지 않았으니 서버 응답을 가정한 갱신은 하지 않는다.
          // 저장된 곳은 다음 곳을 가리키는 데 쓰이고([queuedArrivalStopIdsProvider]),
          // 연결되면 큐가 순서대로 보낸다.
          if (!mounted) return;
          _lockArriveButton();
          showBaraedaToast(
            context,
            // 하원은 도착이 서버에 닿아도 남은 학생이 있으면 종료가 보류된다 — 운행이 끝난다고 약속하지 않는다.
            message: isLast && direction == RunDirection.toAcademy
                ? '마지막 승하차지 도착을 저장했어요 · 연결되면 보내고 운행이 끝나요'
                : isLast
                ? '마지막 승하차지 도착을 저장했어요 · 연결되면 보내요'
                : '$name 도착을 저장했어요 · 연결되면 보내요',
            aboveTabBar: false,
            bottomOffset: _toastAboveActionBar,
          );
        case Sent(value: final result):
          container.invalidate(todayRunsProvider);
          if (result.isFinal) {
            // 종점에 닿았다 — 운행이 끝났으면 위치 송신은 여기서 끝난다. 하원 잔류로 종료가 보류됐으면 송신은
            // 계속된다(`Ruling 855`). 송신기가 보류 여부를 스냅샷에서 읽으므로 스냅샷을 먼저 채운다.
            container.read(lastArriveResultProvider.notifier).state = result;
            container.read(transmissionEndedRunIdProvider.notifier).state =
                runId;
            if (!mounted) return;
            unawaited(context.push(AppRoutes.runEnd));
          } else {
            container.invalidate(driveModeRosterProvider);
            if (!mounted) return;
            // 같은 자리 단추의 이름만 다음 승하차지로 바뀌면 처리된 줄 모른다 — 처리 사실을 토스트로 알린다(M6).
            // 시각은 서버가 적은 도착 시각(§4.5 `arrived_at`)이다.
            _lockArriveButton();
            showBaraedaToast(
              context,
              message: '$name 도착 처리했어요 · ${hhmm(result.arrivedAt)}',
              aboveTabBar: false,
              // 도착 처리 단추 줄(여백 + 단추 64 + 여백) 바로 위 — 토스트가 단추를 가리면 다음 누름을 가로챈다.
              bottomOffset: _toastAboveActionBar,
            );
          }
      }
    } on Failure catch (failure) {
      // 이미 처리된 도착(`403 DUPLICATE_ARRIVE`)은 실패가 아니라 명단이 낡았다는 신호다 — 큐 재생과 같이 성공으로
      // 취급하고, 서버 명단을 다시 받아 다음 승하차지를 가리킨다(A10).
      if (failure case ApiFailure(code: 'DUPLICATE_ARRIVE')) {
        container
          ..invalidate(driveModeRosterProvider)
          ..invalidate(todayRunsProvider);
        return;
      }
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 지도 위 [다음 목적지] · [남은 전 구간] 단추로 고른 범위의 길안내를 카카오내비로 연다(UF-D-02, RUN-08,
  /// Ruling 570) — 범위를 고르는 시트는 없다.
  Future<void> _openNavigation(String runId, NavigationScope scope) async {
    setState(() {
      _navigating = true;
      _errorMessage = null;
      _navNotice = null;
      _naviNotInstalled = false;
    });
    final result = await openExternalNavigation(
      ref,
      runId: runId,
      scope: scope,
    );
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _naviNotInstalled = result.notInstalled;
      _errorMessage = result.error;
      _navNotice = result.truncatedNotice;
    });
  }

  void _lockArriveButton() {
    setState(() => _arriveLocked = true);
    _arriveLockTimer?.cancel();
    _arriveLockTimer = Timer(_arriveLockDuration, () {
      if (mounted) setState(() => _arriveLocked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 저장해 둔 도착이 큐에서 빠졌다 — 서버로 나갔거나 영구 실패다. 서버의 도착 시각을 새로 받는다. 안 받으면
    // "처리한 곳" 에서 빠진 그 곳이 다음 곳으로 되살아난다(859).
    ref.listen(queuedArrivalStopIdsProvider, (previous, next) {
      if (previous == null || next.containsAll(previous)) return;
      ref
        ..invalidate(driveModeRosterProvider)
        ..invalidate(todayRunsProvider);
    });
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(driveModeRunProvider);
    final transmission = ref.watch(positionTransmitterProvider);
    final availability = transmission.availability ?? _recheckedAvailability;

    return Scaffold(
      appBar: ManagerHeader(
        title: '운행 중',
        subtitle: run == null
            ? null
            : '${run.busNo} · ${directionLabel(run.direction)} · '
                  '${hhmm(run.departTime)} 출발',
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없어요 — 운행에서 회차를 골라 주세요'))
          : _buildBody(context, runId, run, transmission, availability),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String runId,
    ManagerRun? run,
    PositionTransmission transmission,
    PositionAvailability? availability,
  ) {
    final rosterAsync = ref.watch(driveModeRosterProvider);
    final colors = context.colors;
    // 지도 높이는 화면 비율로 정한다 — 작은 화면(360×640)에서도 아래 대형 버튼이 밀리지 않는다.
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.28).clamp(
      DriveMapPanel.minHeight,
      DriveMapPanel.maxHeight,
    );
    final roster = rosterAsync.value;
    final moving = run?.runStatus == RunStatus.moving;
    final queuedStopIds = ref.watch(queuedArrivalStopIdsProvider);
    final nextStop = roster == null
        ? null
        : nextUnarrivedStop(roster, queuedStopIds: queuedStopIds);
    final navigationEnabled =
        _canUseExternalNavigation(run) && !_navigating && nextStop != null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 위치가 서버에 닿고 있는지 — 음영 구간에서 기사가 먼저 알게 한다(R46). 송신 중일 때만 그린다.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    BaraedaStatusPill(
                      status: moving
                          ? BaraedaStatus.moving
                          : BaraedaStatus.idle,
                      label: moving ? '운행 중' : '운행 전',
                      size: BaraedaStatusPillSize.lg,
                    ),
                    if (_positionGuidance(availability) != null)
                      const BaraedaStatusPill(
                        status: BaraedaStatus.missed,
                        label: '전송 안 됨',
                        size: BaraedaStatusPillSize.lg,
                      )
                    else
                      const PositionLinkChip(),
                  ],
                ),
                const SizedBox(height: 12),
                const PositionLostBanner(),
                // rosterAsync.when(...) 의 모든 분기 바깥 — "명단 없음"(정상)과
                // "연결 끊김"(비정상)을 구별해야 한다(목표 9, ManagerChannelBanner
                // 문서 참고).
                ManagerChannelBanner(runId: runId),
                // 알림은 가장 중요한 한 건만 보이고 나머지는 접힌다 — 노선 변경 확인은 접히지 않는 맨 위
                // 칸(Ruling 596).
                BottomNoticeStack(
                  leading: (run?.ackRequired ?? false)
                      ? ChangeAckBanner(
                          runId: runId,
                          ackRequired: true,
                          addedCount: run?.addedCount ?? 0,
                          removedCount: run?.removedCount ?? 0,
                        )
                      : null,
                  notices: _notices(rosterAsync, availability),
                ),
                if (run != null && roster != null && moving) ...[
                  if (nextStop != null) ...[
                    const SizedBox(height: 4),
                    _NextStopCard(
                      stop: nextStop,
                      order: _orderOf(roster, nextStop),
                      direction: roster.direction,
                      isLast: isLastRemainingStop(
                        roster,
                        nextStop,
                        queuedStopIds: queuedStopIds,
                      ),
                      onRoster: () =>
                          unawaited(context.push(AppRoutes.rosterView)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _mapWithControls(
                    context,
                    mapHeight,
                    transmission,
                    showNavigation: navigationEnabled || _navigating,
                    onNavigation: navigationEnabled
                        ? (scope) => unawaited(_openNavigation(runId, scope))
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _RemainingStops(
                    roster: roster,
                    colors: colors,
                    queuedStopIds: queuedStopIds,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  _mapWithControls(context, mapHeight, transmission),
                ],
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bgBase,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: rosterAsync.when(
                // 갱신이 실패해도 마지막으로 받은 명단을 지우지 않는다 — 음영 구간을 지난 직후에
                // [도착 처리] 가 사라지면 다음 실시간 이벤트가 올 때까지 기사가 조작할 수 없다(R46).
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const SizedBox.shrink(),
                data: (roster) => _buildActionArea(runId, run, roster),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 지도 + 왼쪽 위 [다음 목적지] · [남은 전 구간] 두 단추 · 오른쪽 아래 `크게 보기`
  /// (노선 지도 화면, `Ruling 829`).
  Widget _mapWithControls(
    BuildContext context,
    double height,
    PositionTransmission transmission, {
    bool showNavigation = false,
    void Function(NavigationScope scope)? onNavigation,
  }) {
    return Stack(
      children: [
        DriveMapPanel(height: height, busPosition: transmission.busPosition),
        if (showNavigation)
          Positioned(
            left: 8,
            top: 8,
            right: 64,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BaraedaMapButton(
                  icon: 'navigation',
                  label: '다음 목적지',
                  semanticLabel: '카카오내비',
                  onPressed: onNavigation == null
                      ? null
                      : () => onNavigation(NavigationScope.next),
                ),
                BaraedaMapButton(
                  icon: 'route',
                  label: '남은 전 구간',
                  semanticLabel: '카카오내비',
                  onPressed: onNavigation == null
                      ? null
                      : () => onNavigation(NavigationScope.remaining),
                ),
              ],
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: BaraedaMapButton(
            icon: 'map',
            semanticLabel: '노선 크게 보기',
            onPressed: () => unawaited(context.push(AppRoutes.routeMap)),
          ),
        ),
      ],
    );
  }

  /// 명단 안에서 이 승하차지의 번호 — 서버 `seq` 가 아니라 명단 순서(경유 지점은 명단에 없다, `Ruling 398`).
  int _orderOf(RosterResponse roster, RosterStop stop) =>
      roster.stops.indexWhere((s) => s.stopId == stop.stopId) + 1;

  /// 알림을 중요한 순서로 모은다 — 접힌 상태에서는 첫 건만 보인다([BottomNoticeStack]).
  /// 도착 처리 실패 > 명단 조회 실패 > 위치 송신 불가 > 카카오내비 미설치 > 길안내 안내 순이다:
  /// 지금 조작이 막힌 것을 앞에, 알려 주는 것을 뒤에 둔다.
  List<BottomNotice> _notices(
    AsyncValue<RosterResponse> rosterAsync,
    PositionAvailability? availability,
  ) {
    final guidance = _positionGuidance(availability);
    return [
      if (_errorMessage != null)
        BottomNotice(tone: AlertTone.missed, body: _errorMessage!),
      if (rosterAsync.hasError)
        _rosterFailureNotice(rosterAsync.error!, stale: rosterAsync.hasValue),
      if (guidance != null)
        BottomNotice(
          tone: AlertTone.missed,
          body: '$guidance ${_positionGuidanceBody(availability)}',
          action: BaraedaButton(
            label: '설정 열기',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(settingsOpenerProvider)(
                availability == PositionAvailability.permissionDenied
                    ? DeviceSettingsPage.app
                    : DeviceSettingsPage.location,
              ),
            ),
          ),
        ),
      if (_naviNotInstalled)
        BottomNotice(
          tone: AlertTone.missed,
          body: '카카오내비가 설치돼 있지 않아요. 설치한 뒤 다시 눌러 주세요.',
          action: BaraedaButton(
            label: '설치하기',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(uriOpenerProvider)(
                ref.read(kakaoNaviLauncherProvider).installUri,
              ),
            ),
          ),
        ),
      if (_navNotice != null)
        BottomNotice(tone: AlertTone.moving, body: _navNotice!),
    ];
  }

  bool _canUseExternalNavigation(ManagerRun? run) =>
      ref.watch(kakaoNaviAppKeyProvider).isNotEmpty &&
      (ref.watch(roleCapabilitiesProvider)?.canOperateRun ?? false) &&
      (run?.runStatus == RunStatus.confirmed ||
          run?.runStatus == RunStatus.moving);

  /// 명단 조회 실패 안내 + [다시 시도]. [stale] 이면 화면의 명단이 마지막 성공분이라는 뜻이다.
  BottomNotice _rosterFailureNotice(Object error, {required bool stale}) =>
      BottomNotice(
        tone: AlertTone.missed,
        body: stale
            ? '최신 명단을 불러오지 못했어요 · 이전 명단을 보고 있어요: ${describeError(error)}'
            : '명단을 불러오지 못했어요: ${describeError(error)}',
        action: BaraedaButton(
          label: '다시 시도',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: () => ref.invalidate(driveModeRosterProvider),
        ),
      );

  Widget _buildActionArea(
    String runId,
    ManagerRun? run,
    RosterResponse roster,
  ) {
    if (run == null) return const SizedBox.shrink();

    // 운행 시작은 운행 준비 화면에서만 한다(`Ruling 799`) — 아직 시작 전 회차로 들어왔으면 그리로 보낸다.
    if (run.runStatus == RunStatus.idle ||
        run.runStatus == RunStatus.confirmed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordWrapText('아직 운행을 시작하지 않았어요'),
          const SizedBox(height: 8),
          BaraedaButton(
            label: '운행 준비하기',
            icon: 'bus',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () => context.pushReplacement(AppRoutes.runReady),
          ),
        ],
      );
    }

    if (run.runStatus == RunStatus.moving) {
      final queuedStopIds = ref.watch(queuedArrivalStopIdsProvider);
      final nextStop = nextUnarrivedStop(roster, queuedStopIds: queuedStopIds);
      if (nextStop == null) {
        // 하원은 마지막 도착 뒤에도 탑승 중 학생이 있으면 종료가 보류된다 — 보류 화면(하차 대기 목록 · 보호자 부재
        // 보고)을 나갔다가 다시 열 길을 둔다. 도착이 큐에 있으면 아직 서버에 닿지 않았다.
        final pendingEnd =
            queuedStopIds.isEmpty &&
            roster.direction == RunDirection.fromAcademy;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WordWrapText(
              queuedStopIds.isEmpty
                  ? '모든 승하차지 도착 처리가 끝났어요'
                  : '도착 처리를 저장했어요 · 연결되면 서버로 보내요',
            ),
            if (pendingEnd) ...[
              const SizedBox(height: 8),
              BaraedaButton(
                label: '하차 대기 보기',
                size: BaraedaButtonSize.xl,
                block: true,
                onPressed: () => unawaited(context.push(AppRoutes.runEnd)),
              ),
            ],
          ],
        );
      }
      final lost = judgePositionLink(
        now: ref.read(clockProvider).now(),
        link: ref.read(positionLinkProvider),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 이름이 길어도 동사(`도착 처리`)는 잘리지 않는다 — 이름만 `…` 로 줄어든다(M5).
          BaraedaButton(
            name: nextStop.name,
            label: '도착 처리',
            icon: 'check',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: _submitting || _arriveLocked
                ? null
                : () => _arriveStop(
                    runId,
                    nextStop.stopId,
                    order: _orderOf(roster, nextStop),
                    name: nextStop.name,
                    direction: roster.direction,
                    hasBoardedRiders: roster.counts.boarded > 0,
                    isLast: isLastRemainingStop(
                      roster,
                      nextStop,
                      queuedStopIds: queuedStopIds,
                    ),
                  ),
          ),
          if (lost?.kind == PositionLinkKind.lost)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '연결이 없어도 도착 처리는 저장돼요. 연결되면 자동으로 보내요.',
                textAlign: TextAlign.center,
                style: BaraedaTypography.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WordWrapText('이미 종료된 운행이에요'),
        const SizedBox(height: 8),
        BaraedaButton(
          label: '종료 보고서 보기',
          size: BaraedaButtonSize.xl,
          block: true,
          onPressed: () => unawaited(context.push(AppRoutes.runEnd)),
        ),
      ],
    );
  }
}

/// 다음 승하차지 큰 카드 — `다음 승하차지 · 3번` + 이름(나눔명조 큰 글자) + 부제 + `명단 ›`(조회 전용 명단).
class _NextStopCard extends StatelessWidget {
  const new({
    required this.stop,
    required this.order,
    required this.direction,
    required this.isLast,
    required this.onRoster,
  });

  final RosterStop stop;
  final int order;
  final RunDirection direction;
  final bool isLast;
  final VoidCallback onRoster;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = isLast
        ? _lastStopNote(direction)
        : [
            if (stop.change == StopChange.added) '신규',
            '탑승 예정 ${stop.students.length}명',
          ].join(' · ');
    return BaraedaCard(
      accent: BaraedaStatus.moving,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isLast ? '마지막' : '다음'} 승하차지 · $order번',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaraedaTypography.h2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          BaraedaButton(
            label: '명단',
            iconEnd: 'chevron-right',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: onRoster,
          ),
        ],
      ),
    );
  }
}

/// `남은 승하차지 3곳 · 미경유 1곳은 건너뛰어요` + 번호 타임라인 — 조회 전용(승하차 처리는 동승자만, M-12).
class _RemainingStops extends StatelessWidget {
  const new({
    required this.roster,
    required this.colors,
    required this.queuedStopIds,
  });

  final RosterResponse roster;
  final BaraedaColors colors;

  /// 도착 처리를 기기에 저장해 둔 곳 — 이미 처리한 곳으로 보고 남은 목록에서 뺀다(859).
  final Set<String> queuedStopIds;

  @override
  Widget build(BuildContext context) {
    final remaining = [
      for (final stop in roster.stops)
        if (stop.arrivedAt == null && !queuedStopIds.contains(stop.stopId))
          stop,
    ];
    if (remaining.isEmpty) return const SizedBox.shrink();
    final skipped = remaining
        .where((stop) => stop.change == StopChange.skipped)
        .length;
    final active = remaining.length - skipped;
    final firstActive = remaining.indexWhere(
      (stop) => stop.change != StopChange.skipped,
    );
    return Column(
      key: const Key('remaining-stops'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '남은 승하차지 $active곳',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (skipped > 0)
              Text(
                '미경유 $skipped곳은 건너뛰어요',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        BaraedaCard(
          child: StopTimeline(
            stops: [
              for (var i = 0; i < remaining.length; i++)
                switch (remaining[i].change) {
                  StopChange.skipped => Stop(
                    name: remaining[i].name,
                    address: '정차 안 함',
                    time: '미경유',
                    state: StopState.skipped,
                  ),
                  _ => Stop(
                    name: remaining[i].name,
                    address: i == remaining.length - 1
                        ? _lastStopNote(roster.direction)
                        : '학생 ${remaining[i].students.length}명'
                              '${_addedSuffix(remaining[i])}',
                    time: remaining[i].change == StopChange.added ? '추가' : null,
                    state: i == firstActive
                        ? StopState.current
                        : StopState.upcoming,
                  ),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// 마지막 승하차지에 도착하면 일어나는 일 — 등원은 곧 운행 종료, 하원은 탑승 중 학생이 남아 있으면 종료가
/// 보류된다(C-15). 도착 확인 창의 안내와 같은 약속이다.
String _lastStopNote(RunDirection direction) =>
    direction == RunDirection.toAcademy
    ? '도착하면 운행이 끝나요'
    : '학생이 남아 있으면 종료가 보류돼요';

/// 신규로 추가된 승하차지의 부제 꼬리.
String _addedSuffix(RosterStop stop) =>
    stop.change == StopChange.added ? ' · 신규' : '';
