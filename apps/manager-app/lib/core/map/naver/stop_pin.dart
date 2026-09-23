import 'package:flutter/material.dart';

/// 정차지 핀 — 끝이 좌표를 가리키는 물방울 모양, 머리 안에 순번(사용자 지시 2026-09-23).
///
/// 관계자 웹(`academy-web/.../markerIcon.tsx` 의 `stopPinHtml`)과 같은 윤곽·색·크기다 — 같은
/// 정차지가 제품마다 다르게 생기면 기사와 관계자가 통화하며 같은 지점을 가리키기 어렵다.
///
/// 어댑터가 이 위젯을 이미지로 굳혀 마커 아이콘으로 쓴다. SDK 마커의 기준점이 이미지의
/// **아래 가운데**라 끝점을 위젯 아래 끝에 둔다 — 그래서 크기를 [size] 로 고정한다.
class StopPin extends StatelessWidget {
  const StopPin({super.key, this.seq});

  final int? seq;

  /// 폭 22 · 높이 29 — 웹 핀과 같다(윤곽 좌표계 26×34 를 폭 22 에 맞춘 값).
  static const size = Size(22, 29);

  /// 웹의 정차지 색(`MARKER_COLOR.stop`)과 같은 값.
  static const color = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: CustomPaint(
        painter: const _StopPinPainter(),
        child: Align(
          // 머리 원의 중심(윤곽 좌표 12.5/34)에 숫자를 둔다.
          alignment: const Alignment(0, -0.26),
          child: seq == null
              ? null
              : Text(
                  '$seq',
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 윤곽 — 머리는 (12,12) 중심 반지름 12 의 원, 끝점은 (12,32). 흰 테두리 두께만큼(1) 사방을
/// 넓힌 26×34 좌표계를 위젯 크기에 맞춰 늘린다.
class _StopPinPainter extends CustomPainter {
  const _StopPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 26, size.height / 34)
      ..translate(1, 1);
    final path = Path()
      ..moveTo(12, 32)
      ..cubicTo(12, 32, 0, 20.5, 0, 12)
      ..arcToPoint(const Offset(24, 12), radius: const Radius.circular(12))
      ..cubicTo(24, 20.5, 12, 32, 12, 32)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = StopPin.color)
      ..drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_StopPinPainter oldDelegate) => false;
}
