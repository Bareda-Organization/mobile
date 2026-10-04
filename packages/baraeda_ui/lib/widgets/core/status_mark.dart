// 상태 칩 맨 앞 모양 — 종료 ■ · 이동 중 ▶ · 확정 ● · 대기 ○ · 위험 ▲.
// 시안 `.m-chip::before`(9×9) 대응.

import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:flutter/widgets.dart';

/// 상태 모양 하나. 장식이라 낭독하지 않는다 — 문구는 칩이 읽는다.
class BaraedaStatusMark extends StatelessWidget {
  const new({
    required this.shape,
    required this.color,
    super.key,
    this.size = 9,
  });

  final BaraedaStatusShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(shape, color),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const new(this.shape, this.color);

  final BaraedaStatusShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case BaraedaStatusShape.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
          fill,
        );
      case BaraedaStatusShape.triangleRight:
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(w, h / 2)
            ..lineTo(0, h)
            ..close(),
          fill,
        );
      case BaraedaStatusShape.circle:
        canvas.drawCircle(Offset(w / 2, h / 2), w / 2, fill);
      case BaraedaStatusShape.ring:
        // 시안 `border:2px solid` — 바깥 지름이 9 가 되도록 반지름에서 1 을 뺀다.
        canvas.drawCircle(
          Offset(w / 2, h / 2),
          w / 2 - 1,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      case BaraedaStatusShape.triangleUp:
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, 0)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.shape != shape || old.color != color;
}
