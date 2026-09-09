import 'package:flutter/material.dart';

/// 자리표시 화면 — P-07 (IMPLEMENTATION_PLAN.md §3.1, §3.11 · §7 WebSocket).
/// 실시간 버스 위치 지도는 이번 범위가 아니다.
class LiveMapScreen extends StatelessWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('LiveMapScreen — 자리표시')),
    );
  }
}
