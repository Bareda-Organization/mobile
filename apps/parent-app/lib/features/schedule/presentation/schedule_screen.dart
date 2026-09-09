import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/auth/auth_providers.dart';

/// 자리표시 화면 — P-05·P-06 (IMPLEMENTATION_PLAN.md §3.1, §3.7·3.8·3.9).
///
/// 탑승 위치 변경 진입점을 역할로 감추는 자리 — 등원 예정 조회는 전 역할
/// 공통이지만 변경은 학부모만(§1.1). 실제 변경 요청 흐름은 이번 범위가 아니다.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('등하원 일정')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ScheduleScreen — 자리표시'),
            if (capabilities?.canChangeBoardingLocation ?? false)
              const Text('탑승 위치 변경 진입점 (학부모만 보임)'),
            if (capabilities?.canGenerateLinkCode ?? false)
              const Text('부모 연결 코드 생성 진입점 (학생만 보임, S-05)'),
          ],
        ),
      ),
    );
  }
}
