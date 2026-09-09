import 'package:flutter/material.dart';

/// 자리표시 화면 — P-08 (IMPLEMENTATION_PLAN.md §3.1, §3.10).
/// 노선 상세(경유 승하차지 순서)는 이번 범위가 아니다.
class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('RouteDetailScreen — 자리표시')),
    );
  }
}
