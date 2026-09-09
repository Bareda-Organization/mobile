import 'package:flutter/material.dart';

/// 자리표시 화면 — 오프라인 큐 (IMPLEMENTATION_PLAN.md §3.2, M-06, 킷 부재).
/// 대기 중인 요청 목록·재전송 흐름은 이번 범위가 아니다.
/// 저장소는 `data/offline_queue_database.dart` (drift) 가 담당한다.
class OfflineQueueScreen extends StatelessWidget {
  const OfflineQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('OfflineQueueScreen — 자리표시')),
    );
  }
}
