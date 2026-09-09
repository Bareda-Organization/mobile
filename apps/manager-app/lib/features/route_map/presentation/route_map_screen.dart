import 'package:flutter/material.dart';

/// 자리표시 화면 — RouteMapScreen (IMPLEMENTATION_PLAN.md §3.2, M-04·M-09).
/// 실시간 노선 지도는 이번 범위가 아니다(지도 패키지 미도입).
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('RouteMapScreen — 자리표시')),
    );
  }
}
