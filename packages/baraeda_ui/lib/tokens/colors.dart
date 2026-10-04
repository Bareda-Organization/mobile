// 바래다 색상 — 원시 팔레트.
// `frontend/design-system/tokens/colors.css` 를 1:1 로 이식한 것.
// 위젯은 이 파일을 직접 참조하지 않는다 — 의미 계층(`theme/baraeda_colors.dart`)만 참조한다.
// (CONVENTIONS_FLUTTER.md §3 "토큰은 하드코딩하지 않는다")

import 'package:flutter/widgets.dart';

/// 바래다 원시 팔레트. 브랜드 6색은 PDF 값 그대로이고 나머지는 그 6색에서 파생한 명도 단계다.
abstract final class BaraedaPalette {
  // 그린 — 신뢰·보호. 브랜드 메인은 [green600].
  static const Color green900 = Color(0xFF12211C);
  static const Color green800 = Color(0xFF17362D);
  static const Color green700 = Color(0xFF1A4A3E);
  static const Color green600 = Color(0xFF1F5C4D);
  static const Color green500 = Color(0xFF2B7A66);
  static const Color green400 = Color(0xFF4A9C87);
  static const Color green300 = Color(0xFF7BBAA6);
  static const Color green200 = Color(0xFFA8CFC2);
  static const Color green100 = Color(0xFFE8F0EC);
  static const Color green50 = Color(0xFFF1F7F4);

  // 앰버 — 버스·이동 중. 마커·면은 [amber500], 흰 배경 위 글자는 [amberInk].
  static const Color amber700 = Color(0xFF9E6410);
  static const Color amber600 = Color(0xFFC77E12);
  static const Color amber500 = Color(0xFFF5A623);
  static const Color amber400 = Color(0xFFF8BC58);
  static const Color amber300 = Color(0xFFFBD08A);
  static const Color amber100 = Color(0xFFFDF0D8);
  // 글자 잉크 — 자기 옅은 면([amber100]) 위에서도 4.5:1 이상이 되게 어둡게 잡았다(F07-09).
  // R48: 시안(`mkit` `--t-move`)의 `#8A560C` 로 맞췄다.
  static const Color amberInk = Color(0xFF8A560C);

  // 레드 — 미탑승·긴급. 라이트는 [red500], 다크는 [red300].
  static const Color red600 = Color(0xFFC24634);
  static const Color red500 = Color(0xFFE05C4B);
  static const Color red300 = Color(0xFFF08A7A);
  static const Color red100 = Color(0xFFFBE3DF);
  // [red100] 위 글자 4.5:1 이상(F07-09). R48: 시안(`mkit` `--t-bad`)의 `#A8301F` 로 맞췄다.
  static const Color redInk = Color(0xFFA8301F);
  // 위험 단추 면 · 위험 칩의 ▲ 모양(`mkit` `--bad-solid` · `--c-bad`).
  // 웹 `--red-ink` 와 같은 값.
  // 글자로 쓰지 않는다 — 글자는 [redInk].
  static const Color redSolid = Color(0xFFC93F2C);

  // 스톤 — 보조 텍스트·구분선.
  static const Color stone800 = Color(0xFF2A312E);
  static const Color stone700 = Color(0xFF3D4441);
  static const Color stone600 = Color(0xFF545C58);
  static const Color stone500 = Color(0xFF6B7672);
  static const Color stone400 = Color(0xFF8F9995);
  static const Color stone300 = Color(0xFFB7BEBB);
  static const Color stone200 = Color(0xFFD7DBD9);
  static const Color stone100 = Color(0xFFECEEED);

  // 중립 바탕.
  static const Color offWhite = Color(0xFFFAFAF7);
  static const Color white = Color(0xFFFFFFFF);
  static const Color darkShade = Color(0xFF12211C);
  static const Color darkBody = Color(0xFFE7EFEA);
  static const Color pageTint = Color(0xFFF4F5F2);
  static const Color ink = Color(0xFF0F1D18);

  // 브랜드 별칭 (문서상 이름 — readme.md 의 이름 열과 대응).
  static const Color baraedaGreen = green600;
  static const Color mistGreen = green100;
  static const Color busAmber = amber500;
  static const Color signalRed = red500;
  static const Color stoneGray = stone500;
}
