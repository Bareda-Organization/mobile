import 'package:flutter/material.dart';

/// 자리표시 화면 — DelayScreen (IMPLEMENTATION_PLAN.md §3.2, M-05).
/// 지연 사유 입력·전송은 이번 범위가 아니다.
class DelayScreen extends StatelessWidget {
  const DelayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('DelayScreen — 자리표시')),
    );
  }
}
