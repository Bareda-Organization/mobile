import 'package:flutter/material.dart';

/// 자리표시 화면 — 비상 알림 (IMPLEMENTATION_PLAN.md §3.2, M-15, 킷 부재).
/// 비상 발신 흐름·멱등 키 부착은 이번 범위가 아니다.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('EmergencyScreen — 자리표시')),
    );
  }
}
