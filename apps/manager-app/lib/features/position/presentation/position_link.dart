import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

/// 위치 송신이 서버에 **실제로 닿고 있는지** — 기사 단말의 GPS 값(화면의 버스 점)과는 별개다. 터널·지하에서
/// GPS 는 그대로인데 전송만 실패하면 버스 점은 정상처럼 움직이고 학부모 화면만 "마지막 확인 위치 N분 전"이 된다.
///
/// [PositionTransmission] 과 **따로** 둔다 — 성공할 때마다(2초) 값이 바뀌므로 같은 상태에 넣으면 지도·운행 화면
/// 전체가 2초마다 다시 그려진다(F06-17).
@immutable
class PositionLink {
  const PositionLink({this.startedAt, this.lastSentAt});

  /// 이 송신이 시작된 시각 — 송신 중이 아니면 `null`(칩을 그리지 않는다).
  final DateTime? startedAt;

  /// 서버가 받았다고 답한 마지막 시각 — 아직 한 번도 못 보냈으면 `null`.
  final DateTime? lastSentAt;

  @override
  bool operator ==(Object other) =>
      other is PositionLink &&
      other.startedAt == startedAt &&
      other.lastSentAt == lastSentAt;

  @override
  int get hashCode => Object.hash(startedAt, lastSentAt);
}

/// [PositionLink] 를 들고 있다가 송신기가 성공할 때마다 [markSent] 를 받는다. 송신 대상 회차가 바뀌거나
/// 없어지면(`transmittingRunIdProvider`) 새로 시작한다.
class PositionLinkNotifier extends Notifier<PositionLink> {
  @override
  PositionLink build() {
    final runId = ref.watch(transmittingRunIdProvider);
    return runId == null
        ? const PositionLink()
        : PositionLink(startedAt: ref.read(clockProvider).now());
  }

  /// 위치 전송이 서버에서 성공했다.
  void markSent() => state = PositionLink(
    startedAt: state.startedAt,
    lastSentAt: ref.read(clockProvider).now(),
  );
}

/// [PositionLinkNotifier] — 앱 전역에 하나.
final NotifierProvider<PositionLinkNotifier, PositionLink>
positionLinkProvider = NotifierProvider<PositionLinkNotifier, PositionLink>(
  PositionLinkNotifier.new,
);

/// 전송 상태 세 갈래.
enum PositionLinkKind { normal, delayed, lost }

/// 칩이 보여줄 판정 — [secondsSinceSent] 는 마지막 성공 전송이 있을 때만 채운다.
@immutable
class PositionLinkStatus {
  const PositionLinkStatus(this.kind, this.secondsSinceSent);

  final PositionLinkKind kind;
  final int? secondsSinceSent;
}

/// 마지막 성공 전송(없으면 송신 시작) 이후 지난 시간으로 상태를 정한다 — 기준 시간은
/// [PositionConstants.linkHealthyWithin]·[PositionConstants.linkLostAfter].
/// 송신 중이 아니면 `null`.
PositionLinkStatus? judgePositionLink({
  required DateTime now,
  required PositionLink link,
}) {
  final startedAt = link.startedAt;
  if (startedAt == null) return null;
  final elapsed = now.difference(link.lastSentAt ?? startedAt);
  final kind = elapsed <= PositionConstants.linkHealthyWithin
      ? PositionLinkKind.normal
      : elapsed < PositionConstants.linkLostAfter
      ? PositionLinkKind.delayed
      : PositionLinkKind.lost;
  return PositionLinkStatus(
    kind,
    link.lastSentAt == null ? null : elapsed.inSeconds,
  );
}

/// 운행 화면의 위치 전송 상태 칩 — 1초마다 시계만 다시 읽는다(전송이 안 오는 동안에도 "N초 전"이 올라가야 한다).
class PositionLinkChip extends ConsumerStatefulWidget {
  const PositionLinkChip({super.key});

  @override
  ConsumerState<PositionLinkChip> createState() => _PositionLinkChipState();
}

class _PositionLinkChipState extends ConsumerState<PositionLinkChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = judgePositionLink(
      now: ref.watch(clockProvider).now(),
      link: ref.watch(positionLinkProvider),
    );
    if (status == null) return const SizedBox.shrink();
    final seconds = status.secondsSinceSent;
    final since = seconds == null
        ? null
        : seconds >= 60
        ? '${seconds ~/ 60}분 ${seconds % 60}초 전 마지막 전송'
        : '$seconds초 전 마지막 전송';
    final (tone, text) = switch (status.kind) {
      PositionLinkKind.normal => (BaraedaStatus.boarded, '위치 전송 중'),
      PositionLinkKind.delayed => (
        BaraedaStatus.moving,
        since == null ? '위치 전송 지연' : '위치 전송 지연 · $since',
      ),
      PositionLinkKind.lost => (
        BaraedaStatus.missed,
        since == null ? '위치 전송 안 됨' : '위치 전송 안 됨 · $since',
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: BaraedaStatusPill(status: tone, label: text),
    );
  }
}
