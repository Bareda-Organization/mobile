// 화면이 닫혔는지는 isMounted 콜백으로 확인한 뒤에만 context 를 쓴다.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

/// 운행 화면의 [도착 처리] 한 번의 흐름 — 마지막 승하차지 확인 · 서버 요청 · 결과별 갱신과 토스트.
///
/// 화면 상태(처리 중 · 오류 문구 · 단추 잠금)는 화면이 갖고, 이 클래스는 콜백으로만 바꾼다.
class ArriveStopFlow {
  const new({
    required this.context,
    required this.ref,
    required this.isMounted,
    required this.onBegin,
    required this.onEnd,
    required this.onError,
    required this.lockArriveButton,
  });

  /// 토스트가 도착 처리 단추 줄 위에 뜨는 높이 — 위 여백 12 + 단추 64 + 아래 여백 12 + 간격 8.
  static const toastAboveActionBar = 96.0;

  final BuildContext context;
  final WidgetRef ref;

  /// 화면이 아직 트리에 있는지 — 요청이 오가는 동안 닫혔을 수 있다.
  final bool Function() isMounted;

  /// 요청을 보내기 직전 — 처리 중으로 바꾸고 이전 오류 문구를 지운다.
  final VoidCallback onBegin;

  /// 요청이 끝났다(성공 · 실패 모두).
  final VoidCallback onEnd;

  final void Function(String message) onError;

  /// 도착이 접수된 직후 단추를 잠시 잠근다.
  final VoidCallback lockArriveButton;

  Future<void> run(
    String runId,
    String stopId, {
    required String name,
    required RunDirection direction,
    bool isLast = false,
    bool hasBoardedRiders = false,
  }) async {
    // 마지막 승하차지의 도착 처리는 등원이면 곧 운행 종료다(C-15) — 되돌릴 수 없어 한 번 묻는다.
    // 하원은 도착만 기록되고 남은 학생이 있으면 종료가 보류된다. 그 앞 승하차지는 운전 중에 자주 누르는 조작이라
    // 묻지 않는다.
    if (isLast) {
      final toAcademy = direction == RunDirection.toAcademy;
      final confirmed = await showConfirmDialog(
        context,
        title: '마지막 승하차지예요',
        body: toAcademy
            ? '도착 처리가 곧 운행 종료예요. 되돌릴 수 없어요.\n'
                  // 타고 있는 학생이 없으면 자동 하차할 사람이 없다 — 그 줄을 내지 않는다.
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
      if (!confirmed || !isMounted()) return;
    }
    final container = ProviderScope.containerOf(context);
    onBegin();
    try {
      final outcome = await ref
          .read(driveModeRepositoryProvider)
          .arriveStop(runId: runId, stopId: stopId);
      // 요청 중에 화면이 닫혀도 서버는 이미 도착을 반영했다 — 화면 생존과 무관한 갱신은 컨테이너로 한다
      // (닫힌 화면의 `ref` 는 쓸 수 없다). 큐에 쌓인 도착이 이번 요청 앞에서 비워졌을 수 있다.
      container.invalidate(pendingRequestsProvider);
      switch (outcome) {
        case Queued():
          // 서버에 닿지 못해 기기에 저장만 됐다(859) — 아직 반영되지 않았으니 서버 응답을 가정한 갱신은 하지 않는다.
          // 저장된 곳은 다음 곳을 가리키는 데 쓰이고([queuedArrivalStopIdsProvider]),
          // 연결되면 큐가 순서대로 보낸다.
          if (!isMounted()) return;
          lockArriveButton();
          showBaraedaToast(
            context,
            // 하원은 도착이 서버에 닿아도 남은 학생이 있으면 종료가 보류된다 — 운행이 끝난다고 약속하지 않는다.
            message: isLast && direction == RunDirection.toAcademy
                ? '마지막 승하차지 도착을 저장했어요 · 연결되면 보내고 운행이 끝나요'
                : isLast
                ? '마지막 승하차지 도착을 저장했어요 · 연결되면 보내요'
                : '$name 도착을 저장했어요 · 연결되면 보내요',
            aboveTabBar: false,
            bottomOffset: toastAboveActionBar,
          );
        case Sent(value: final result):
          container.invalidate(todayRunsProvider);
          if (result.isFinal) {
            // 종점에 닿았다 — 운행이 끝났으면 위치 송신은 여기서 끝난다. 하원 잔류로 종료가 보류됐으면 송신은
            // 계속된다(`Ruling 855`). 송신기가 보류 여부를 스냅샷에서 읽으므로 스냅샷을 먼저 채운다.
            container.read(lastArriveResultProvider.notifier).state = result;
            container.read(transmissionEndedRunIdProvider.notifier).state =
                runId;
            if (!isMounted()) return;
            unawaited(context.push(AppRoutes.runEnd));
          } else {
            container.invalidate(driveModeRosterProvider);
            if (!isMounted()) return;
            // 같은 자리 단추의 이름만 다음 승하차지로 바뀌면 처리된 줄 모른다 — 처리 사실을 토스트로 알린다.
            // 시각은 서버가 적은 도착 시각(§4.5 `arrived_at`)이다.
            lockArriveButton();
            showBaraedaToast(
              context,
              message: '$name 도착 처리했어요 · ${hhmm(result.arrivedAt)}',
              aboveTabBar: false,
              // 도착 처리 단추 줄(여백 + 단추 64 + 여백) 바로 위 — 토스트가 단추를 가리면 다음 누름을 가로챈다.
              bottomOffset: toastAboveActionBar,
            );
          }
      }
    } on Failure catch (failure) {
      // 이미 처리된 도착(`403 DUPLICATE_ARRIVE` — 상태와 코드가 짝일 때만)은 실패가 아니라
      // 명단이 낡았다는 신호다 — 큐 재생과 같이 성공으로 취급하고, 서버 명단을 다시 받아 다음 승하차지를 가리킨다.
      if (failure case ApiFailure(statusCode: 403, code: 'DUPLICATE_ARRIVE')) {
        container
          ..invalidate(driveModeRosterProvider)
          ..invalidate(todayRunsProvider);
        return;
      }
      if (!isMounted()) return;
      onError(describeFailure(failure));
    } finally {
      if (isMounted()) onEnd();
    }
  }
}
