import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/bottom_notice_stack.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_action_area.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_with_controls.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_notices.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/stop_cards.dart';
import 'package:manager_app/features/home/domain/models/manager_run.dart';
import 'package:manager_app/features/navigation/domain/models/navigation_scope.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

/// 운행 화면 본문 — 스크롤 영역(상태 · 알림 · 다음 승하차지 · 지도 · 남은 승하차지)과
/// 화면 아래에 붙는 조작 영역([DriveActionArea]).
///
/// 화면 상태(오류 문구 · 길안내 상태 · 처리 중 여부)는 운행 화면이 갖고 값과 콜백으로 내려보낸다.
class DriveModeBody extends ConsumerWidget {
  const new({
    required this.runId,
    required this.run,
    required this.transmission,
    required this.availability,
    required this.errorMessage,
    required this.navNotice,
    required this.naviNotInstalled,
    required this.navigating,
    required this.submitting,
    required this.arriveLocked,
    required this.onNavigation,
    required this.onArrive,
    super.key,
  });

  final String runId;
  final ManagerRun? run;
  final PositionTransmission transmission;
  final PositionAvailability? availability;
  final String? errorMessage;
  final String? navNotice;
  final bool naviNotInstalled;
  final bool navigating;
  final bool submitting;
  final bool arriveLocked;
  final void Function(NavigationScope scope) onNavigation;
  final ArriveStopCallback onArrive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = this.run;
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
        _canUseExternalNavigation(ref, run) && !navigating && nextStop != null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 위치가 서버에 닿고 있는지 — 음영 구간에서 기사가 먼저 알게 한다. 송신 중일 때만 그린다.
                _DriveStatusRow(moving: moving, availability: availability),
                const SizedBox(height: 12),
                const PositionLostBanner(),
                // rosterAsync.when(...) 의 모든 분기 바깥 — "명단 없음"(정상)과
                // "연결 끊김"(비정상)을 구별해야 한다(ManagerChannelBanner
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
                  notices: collectDriveNotices(
                    ref,
                    rosterAsync: rosterAsync,
                    availability: availability,
                    errorMessage: errorMessage,
                    naviNotInstalled: naviNotInstalled,
                    navNotice: navNotice,
                  ),
                ),
                if (run != null && roster != null && moving) ...[
                  if (nextStop != null) ...[
                    const SizedBox(height: 4),
                    NextStopCard(
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
                  DriveMapWithControls(
                    height: mapHeight,
                    transmission: transmission,
                    showNavigation: navigationEnabled || navigating,
                    onNavigation: navigationEnabled ? onNavigation : null,
                  ),
                  const SizedBox(height: 16),
                  RemainingStops(
                    roster: roster,
                    colors: colors,
                    queuedStopIds: queuedStopIds,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  DriveMapWithControls(
                    height: mapHeight,
                    transmission: transmission,
                  ),
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
                // [도착 처리] 가 사라지면 다음 실시간 이벤트가 올 때까지 기사가 조작할 수 없다.
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const SizedBox.shrink(),
                data: (roster) => DriveActionArea(
                  runId: runId,
                  run: run,
                  roster: roster,
                  submitting: submitting,
                  arriveLocked: arriveLocked,
                  onArrive: onArrive,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

bool _canUseExternalNavigation(WidgetRef ref, ManagerRun? run) =>
    ref.watch(kakaoNaviAppKeyProvider).isNotEmpty &&
    (ref.watch(roleCapabilitiesProvider)?.canOperateRun ?? false) &&
    (run?.runStatus == RunStatus.confirmed ||
        run?.runStatus == RunStatus.moving);

/// 명단 안에서 이 승하차지의 번호 — 서버 `seq` 가 아니라 명단 순서(경유 지점은 명단에 없다, `Ruling 398`).
int _orderOf(RosterResponse roster, RosterStop stop) =>
    roster.stops.indexWhere((s) => s.stopId == stop.stopId) + 1;

/// 운행 상태 알약 + 위치 전송 상태 알약.
class _DriveStatusRow extends StatelessWidget {
  const new({required this.moving, required this.availability});

  final bool moving;
  final PositionAvailability? availability;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        BaraedaStatusPill(
          status: moving ? BaraedaStatus.moving : BaraedaStatus.idle,
          label: moving ? '운행 중' : '운행 전',
          size: BaraedaStatusPillSize.lg,
        ),
        if (positionGuidance(availability) != null)
          const BaraedaStatusPill(
            status: BaraedaStatus.missed,
            label: '전송 안 됨',
            size: BaraedaStatusPillSize.lg,
          )
        else
          const PositionLinkChip(),
      ],
    );
  }
}
