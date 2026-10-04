import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 범례 한 칸 — 색 표식 + 이름(시안 `.m-legend`).
class MapLegendItem extends StatelessWidget {
  const new({
    required this.swatch,
    required this.label,
    required this.style,
    super.key,
  });

  final Widget swatch;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: 6),
      Text(label, style: style),
    ],
  );
}

/// 범례 색 표식 — 채운 점, [ring] 이면 속이 빈 고리(정차 안 함).
class MapLegendSwatch extends StatelessWidget {
  const new({required this.color, this.ring = false, super.key});

  final Color color;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: ring ? Colors.transparent : color,
      border: ring ? Border.all(color: color, width: 2) : null,
    ),
  );
}
