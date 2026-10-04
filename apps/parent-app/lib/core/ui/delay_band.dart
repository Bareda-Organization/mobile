import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';

/// `버스가 10분 늦어요 · 교통 체증` — 홈과 전체 지도가 같이 쓴다(`delay` 가 원천이고 ETA 가 아니다).
class DelayBand extends StatelessWidget {
  const new({required this.delay, super.key});

  final BusDelay delay;

  @override
  Widget build(BuildContext context) {
    return AlertBanner(
      tone: AlertTone.moving,
      title: '버스가 ${delay.minutes}분 늦어요',
      body: delay.reason,
    );
  }
}
