import 'package:flutter/material.dart';

/// 자리표시 화면 — P-09 (IMPLEMENTATION_PLAN.md §3.1, §3.14 · §2.11).
/// 알림 on/off · 단말 등록 관리는 이번 범위가 아니다.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('SettingsScreen — 자리표시')),
    );
  }
}
