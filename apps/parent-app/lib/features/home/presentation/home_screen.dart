import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/auth/auth_providers.dart';

/// 자리표시 화면 — P-02·P-03·P-04 (IMPLEMENTATION_PLAN.md §3.1).
///
/// 역할 분기 예시로 등원 여부 토글 진입점을 여기 붙인다 — 실제 구현이 아니라
/// `roleCapabilitiesProvider` 로 진입점을 감추는 자리만 보여 준다(§1.1).
/// 실제 명단 조회·토글 동작은 이번 범위가 아니다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('오늘 운행')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('HomeScreen — 자리표시'),
            if (capabilities?.canToggleAttendance ?? false)
              const Text('등원 여부 변경 진입점 (학부모만 보임)'),
          ],
        ),
      ),
    );
  }
}
