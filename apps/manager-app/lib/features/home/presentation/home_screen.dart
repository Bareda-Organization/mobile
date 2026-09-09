import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

/// 자리표시 화면 — ManagerHome (IMPLEMENTATION_PLAN.md §3.2, M-02·M-07).
///
/// 역할 분기 예시로 도착 알림 전송 진입점을 여기 붙인다 — 실제 구현이 아니라
/// `roleCapabilitiesProvider` 로 진입점을 감추는 자리만 보여 준다(§1.1).
class ManagerHomeScreen extends ConsumerWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('오늘 운행')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ManagerHomeScreen — 자리표시'),
            if (capabilities?.canSendArrivalNotification ?? false)
              const Text('도착 알림 전송 진입점 (기사만 보임)'),
          ],
        ),
      ),
    );
  }
}
