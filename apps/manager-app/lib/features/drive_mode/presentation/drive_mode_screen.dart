import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

/// 자리표시 화면 — DriveMode (IMPLEMENTATION_PLAN.md §3.2, M-08·M-10·M-11).
///
/// 지연 알림 전송 진입점을 역할로 감추는 자리 — 실제 위치 전송·운행 진행
/// 흐름은 이번 범위가 아니다.
class DriveModeScreen extends ConsumerWidget {
  const DriveModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('운행 모드')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DriveModeScreen — 자리표시'),
            if (capabilities?.canSendDelayNotification ?? false)
              const Text('지연 알림 전송 진입점 (기사만 보임)'),
          ],
        ),
      ),
    );
  }
}
