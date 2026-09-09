import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

/// 자리표시 화면 — StopRoster (IMPLEMENTATION_PLAN.md §3.2, M-03·M-12·M-13·M-14).
///
/// **같은 화면에서 버튼 노출이 갈리는** 핵심 예시(§1.1) — 기사는 도착 알림
/// 전송, 동승자는 개인별 승하차 상태 결정 진입점을 본다. 실제 명단 조회·
/// 상태 변경 흐름은 이번 범위가 아니다.
class RosterScreen extends ConsumerWidget {
  const RosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('승하차 명단')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('RosterScreen — 자리표시'),
            if (capabilities?.canSendArrivalNotification ?? false)
              const Text('도착 알림 전송 진입점 (기사만 보임)'),
            if (capabilities?.canDecideBoardingStatus ?? false)
              const Text('개인별 승하차 상태 결정 진입점 (동승자만 보임)'),
          ],
        ),
      ),
    );
  }
}
