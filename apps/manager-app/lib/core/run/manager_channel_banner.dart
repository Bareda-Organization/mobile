import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// `/topic/manager/runs/{runId}` 연결 상태 배너 — DriveMode·StopRoster
/// 화면이 공유한다(두 화면 다 [managerRunChannelProvider] 를 그대로
/// 노출하지 않고 이 위젯을 통해서만 그린다 — 배지 문구·색을 한 곳에서
/// 관리하기 위함).
///
/// [ManagerChannelStatus.connected] 면 아무것도 그리지 않는다 — 정상
/// 상태는 화면을 침해하지 않는다는 관례(`DriveModeScreen`의
/// `_errorMessage` 배너와 같다).
///
/// ⚠ 호출부는 이 위젯을 `rosterAsync.when(loading/error/data)` 의 **모든
/// 분기 바깥**에 둬야 한다 — `data` 분기 안에만 두면 "명단이 비어 있다"
/// (정상, `data` 분기)와 "연결이 끊겨 아무것도 못 받는다"(비정상, 이
/// 배너가 다루는 것)가 화면에서 구별되지 않는다(목표 9).
class ManagerChannelBanner extends ConsumerWidget {
  const ManagerChannelBanner({required this.runId, super.key});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(managerRunChannelProvider(runId));
    final banner = switch (status) {
      ManagerChannelStatus.connected => null,
      ManagerChannelStatus.connecting => const AlertBanner(
        tone: AlertTone.moving,
        title: '실시간 연결 중',
        body: '잠시만 기다려 주세요',
      ),
      ManagerChannelStatus.reconnecting => const AlertBanner(
        tone: AlertTone.moving,
        title: '실시간 연결이 끊어져 재연결 중',
        body: '자동으로 다시 붙습니다 — 그동안 목록이 늦게 반영될 수 있습니다',
      ),
      ManagerChannelStatus.gaveUp => const AlertBanner(
        tone: AlertTone.missed,
        title: '실시간 연결 실패',
        body: '자동 재연결이 중단됐습니다. 새로고침해 다시 시도하세요',
      ),
      ManagerChannelStatus.forbidden => const AlertBanner(
        tone: AlertTone.missed,
        title: '이 운행에 배정되지 않았습니다',
        body: '홈 화면에서 배정 현황을 다시 확인하세요',
      ),
    };
    if (banner == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: banner);
  }
}
