import 'package:baraeda_core/baraeda_core.dart';
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
  const new({required this.runId, this.hideReconnecting = false, super.key});

  final String runId;

  /// 재연결 중 안내를 숨긴다 — 같은 사건을 맨 위 연결 끊김 띠로 알리는
  /// 화면(명단)이 켠다. 그 띠가 없는 화면은 끄고(기본) 이 배너가 유일한
  /// 알림이다.
  final bool hideReconnecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(managerRunChannelProvider(runId));
    final content = managerChannelBannerContentFor(
      status,
      hideReconnecting: hideReconnecting,
    );
    if (content == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AlertBanner(
        tone: content.tone,
        title: content.title,
        body: content.body,
      ),
    );
  }
}

/// [ManagerChannelStatus] → 배너 문구·톤 매핑. [ManagerChannelBanner] 의
/// `build` 에서 분리한 순수 함수다 — [ManagerRunChannelController] 생성자가
/// 실제 WebSocket 연결을 여는 부수효과를 가지고 있어(`manager_run_channel.dart`
/// 문서 참고) `managerRunChannelProvider` 를 오버라이드하는 위젯 시험은
/// 가짜 컨트롤러를 만들기 어렵다 — 대신 이 함수만 떼어 Riverpod·Flutter
/// 없이 단위 시험한다(`mapConnectionState`·`dispatchManagerChannelEvent` 와
/// 같은 방식, 보고서 §1).
///
/// `null` 은 [ManagerChannelStatus.connected] 하나뿐 — 배너를 그리지 않는다.
ManagerChannelBannerContent? managerChannelBannerContentFor(
  ManagerChannelStatus status, {
  bool hideReconnecting = false,
}) => switch (status) {
  ManagerChannelStatus.connected => null,
  ManagerChannelStatus.connecting => const ManagerChannelBannerContent(
    tone: AlertTone.moving,
    title: '실시간 연결 중',
    body: '잠시만 기다려 주세요',
  ),
  ManagerChannelStatus.reconnecting when hideReconnecting => null,
  ManagerChannelStatus.reconnecting => const ManagerChannelBannerContent(
    tone: AlertTone.moving,
    title: WsConnectionNotice.reconnectingTitle,
    body: '연결이 돌아올 때까지 자동으로 계속 다시 붙습니다 — 그동안 다른 직원의 변경이 늦게 보일 수 있습니다',
  ),
  // 기본 재연결 정책은 포기하지 않는다(R46-FIXRT S-5) — 상한을 준 정책에서만 이 상태에 든다.
  ManagerChannelStatus.gaveUp => const ManagerChannelBannerContent(
    tone: AlertTone.missed,
    title: WsConnectionNotice.gaveUpTitle,
    body: '자동 재연결이 중단됐습니다. 새로고침해 다시 시도하세요',
  ),
  ManagerChannelStatus.forbidden => const ManagerChannelBannerContent(
    tone: AlertTone.missed,
    title: WsConnectionNotice.forbiddenTitle,
    body: '이 운행에 배정되지 않았습니다 — 홈 화면에서 배정 현황을 다시 확인하세요',
  ),
};

/// [managerChannelBannerContentFor] 의 반환 타입 — `AlertBanner` 생성에
/// 필요한 값만 담는다(위젯을 직접 만들지 않는 이유는 위 함수 문서 참고).
@immutable
class ManagerChannelBannerContent {
  const new({
    required this.tone,
    required this.title,
    required this.body,
  });

  final AlertTone tone;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ManagerChannelBannerContent &&
      other.tone == tone &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(tone, title, body);
}
