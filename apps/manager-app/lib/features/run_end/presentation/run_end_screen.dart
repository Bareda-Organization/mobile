import 'package:flutter/material.dart';

/// 자리표시 화면 — RunEndScreen (IMPLEMENTATION_PLAN.md §3.2, M-11).
/// 운행 종료 처리 흐름은 이번 범위가 아니다.
class RunEndScreen extends StatelessWidget {
  const RunEndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('RunEndScreen — 자리표시')),
    );
  }
}
