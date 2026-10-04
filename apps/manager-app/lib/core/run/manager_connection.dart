import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// 이 회차의 실시간 연결이 끊겨 있으면 **언제부터**인지, 연결돼 있으면(또는 처음 연결하는 중이면) `null`.
///
/// 명단 화면이 맨 위 띠(`인터넷 연결 없음 · HH:mm 부터`)를 그릴지 정하는 근거다. 상태가 바뀔 때마다 다시 계산되고,
/// 시각은 컨트롤러가 처음 끊긴 때를 기억한 값이라 화면을 다시 그려도 바뀌지 않는다.
// 타입 이름을 적지 않고 추론에 맡긴다(family 타입 이름이 이 import 로 닿지 않았다).
// ignore: specify_nonobvious_property_types
final managerOfflineSinceProvider = Provider.autoDispose
    .family<DateTime?, String>((ref, runId) {
      final status = ref.watch(managerRunChannelProvider(runId));
      if (status != ManagerChannelStatus.reconnecting) return null;
      return ref.read(managerRunChannelProvider(runId).notifier).offlineSince ??
          ref.read(clockProvider).now();
    });
