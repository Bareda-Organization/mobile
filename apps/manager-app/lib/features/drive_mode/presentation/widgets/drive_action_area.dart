import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/domain/models/manager_run.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';

/// 승하차지 도착 처리를 시작하는 콜백 — 화면의 `_arriveStop` 이 받는다.
typedef ArriveStopCallback = Future<void> Function(
  String runId,
  String stopId, {
  required String name,
  required RunDirection direction,
  bool isLast,
  bool hasBoardedRiders,
});

/// 운행 화면 맨 아래 고정 영역의 조작 — 회차 상태에 따라 운행 준비 · 도착 처리 · 종료 보고서 단추를 보인다.
class DriveActionArea extends ConsumerWidget {
  const new({
    required this.runId,
    required this.run,
    required this.roster,
    required this.submitting,
    required this.arriveLocked,
    required this.onArrive,
    super.key,
  });

  final String runId;
  final ManagerRun? run;
  final RosterResponse roster;

  /// 도착 처리 요청이 나가 있는 중 — 단추를 잠근다.
  final bool submitting;

  /// 도착 직후 더블탭을 막는 잠금.
  final bool arriveLocked;
  final ArriveStopCallback onArrive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = this.run;
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
          // 이름이 길어도 동사(`도착 처리`)는 잘리지 않는다 — 이름만 `…` 로 줄어든다.
          BaraedaButton(
            name: nextStop.name,
            label: '도착 처리',
            icon: 'check',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: submitting || arriveLocked
                ? null
                : () => onArrive(
                    runId,
                    nextStop.stopId,
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
