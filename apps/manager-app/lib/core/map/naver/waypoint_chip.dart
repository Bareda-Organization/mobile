import 'package:flutter/material.dart';

/// 강제 경유 지점 칩(`Ruling 400`) — 번호 없는 흰 바탕 · 회색 테두리 둥근
/// 사각형 + "경유" 글자.
///
/// 관계자 웹(`markerIcon.tsx` 의 `waypointChipHtml`)과 같은 모양·색이다.
/// 승하차지 핀(초록 물방울 + 번호)과 출발·도착 칩(어두운 채움)과 모양이 달라,
/// 색을 못 보는 사람도 글자와 모양으로 가른다.
///
/// 어댑터가 이 위젯을 이미지로 굳혀 마커 아이콘으로 쓰며, 칩의 **가운데**가
/// 좌표에 온다(어댑터가 기준점을 가운데로 둔다).
class WaypointChip extends StatelessWidget {
  const new({super.key});

  /// 폭 40 · 높이 22 — 이미지로 굳힐 때 크기를 고정한다.
  static const size = Size(40, 22);

  /// 웹의 경유 지점 색(`MARKER_COLOR.waypoint`)과 같은 값.
  static const color = Color(0xFF57534E);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color, width: 2),
        ),
        child: const Center(
          child: Text(
            '경유',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: color,
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
