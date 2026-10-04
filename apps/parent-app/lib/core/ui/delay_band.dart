import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';

/// `버스가 10분 늦어요 · 교통 체증` — 홈과 전체 지도가 같이 쓴다(`delay` 가 원천이고 ETA 가 아니다).
class DelayBand extends StatelessWidget {
  const new({required this.delay, this.short = false, super.key});

  final BusDelay delay;

  /// 지도 시트 안에서는 "버스가" 를 뺀 `10분 늦어요` 로 쓴다
  /// (시안 `live-map` — 이미 버스 시트 안이라 주어가 분명하다).
  final bool short;

  @override
  Widget build(BuildContext context) {
    return AlertBanner(
      tone: AlertTone.moving,
      title: short ? '${delay.minutes}분 늦어요' : '버스가 ${delay.minutes}분 늦어요',
      body: delay.reason,
    );
  }
}
