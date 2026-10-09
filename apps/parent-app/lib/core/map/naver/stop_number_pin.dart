import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 승하차지 번호 마커 — 동그라미 안에 승하차지 번호(실제 `seq`)를 쓴다(`Ruling 831`, 시안 `live-map`).
///
/// 어댑터가 이 위젯을 이미지로 굳혀 마커 아이콘으로 쓴다. 동그라미라 기준점은
/// 이미지 **가운데**(`NPoint.relativeCenter`)다.
///
/// **모양은 하나다** — 흰 바탕 · 짙은 회색 둘레 · 번호. 지나간 곳 표시나 "다음 곳" 강조는 없다. 번호와 함께 두면
/// 학부모가 "내 승하차지까지 몇 곳 남았는지" 를 짐작하게 되는데, 서버가 그 값을 주지 않는다(C-08, M-P1).
///
/// **내 승하차지**는 그 위에 초록 옅은 원과 점선 고리를 더해 더 크게 보인다.
///
/// 색은 시안(`baraeda2/parent/live-map.html`)의 값을 그대로 옮겼다. 지도 어댑터는 `BuildContext` 의 테마를 못 읽는
/// 자리(이미지로 굳히는 시점)라 값을 이 파일에 둔다 — 같은 사정의 `_stopMarkerTint` 와 같다.
class StopNumberPin extends StatelessWidget {
  const new({required this.seq, this.mine = false, super.key});

  final int seq;
  final bool mine;

  static const _green = Color(0xFF1F5C4D);
  static const _ink = Color(0xFF3D4441);

  /// 이미지 크기(논리 픽셀) — 안의 동그라미와 둘레(고리)가 잘리지 않는 크기.
  static Size sizeOf({required bool mine}) =>
      mine ? const Size(52, 52) : const Size(30, 30);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: sizeOf(mine: mine),
      child: CustomPaint(
        painter: _PinPainter(mine: mine),
        child: Center(
          child: Text(
            '$seq',
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const new({required this.mine});

  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (mine) {
      canvas.drawCircle(
        center,
        24,
        Paint()..color = StopNumberPin._green.withValues(alpha: 0.16),
      );
      _dashedCircle(canvas, center, 19);
    }
    canvas
      ..drawCircle(center, 12, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        12,
        Paint()
          ..color = StopNumberPin._ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8,
      );
  }

  /// 점선 고리 — 4 그리고 3 쉬기를 한 바퀴 반복한다(시안 `stroke-dasharray="4 3"`).
  void _dashedCircle(Canvas canvas, Offset center, double radius) {
    const dash = 4.0;
    const gap = 3.0;
    final paint = Paint()
      ..color = StopNumberPin._green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final circumference = 2 * math.pi * radius;
    final step = (dash + gap) / radius;
    final sweep = dash / radius;
    for (var angle = 0.0; angle < 2 * math.pi - 1e-6; angle += step) {
      if (angle * radius >= circumference) break;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) =>
      oldDelegate.mine != mine;
}
