// 바래다 타이포그래피 — 제목 나눔명조(세리프) / 본문 Noto Sans KR(산세리프).
// `frontend/design-system/tokens/typography.css` 를 1:1 로 이식한 것.
//
// ⚠ 폰트 바이너리는 이 저장소에 없다 (팀 리드 지시 — 다운로드 금지).
// `fonts.css` 원본은 Google Fonts CDN(`@import`)에서 로드하는데, Flutter 는 CDN
// `@import` 를 쓸 수 없어 두 가지 중 하나가 필요하다:
//   1) 자체 호스팅 — 나눔명조·Noto Sans KR 의 .ttf(또는 .otf)를
//      `assets/fonts/` 에 넣고 `pubspec.yaml` 의 주석 처리된 `fonts:` 블록을 활성화한다.
//   2) `google_fonts` 패키지를 의존성에 추가해 런타임에 내려받는다 — 단 오프라인
//      기동이 안 되므로 이 프로젝트의 정책(로컬 폰트 고정)과는 맞지 않을 수 있다.
// 파일이 없는 지금은 [BaraedaFontFamily.serif] · [BaraedaFontFamily.sans] 이름만
// 시스템 폴백 폰트로 렌더링된다 — 폰트가 없다고 컴파일이나 테스트가 깨지지는 않는다.

import 'package:flutter/widgets.dart';

/// 폰트 패밀리 이름. 실제 글리프는 위 안내를 따라 넣기 전까지 시스템 폴백을 쓴다.
abstract final class BaraedaFontFamily {
  static const String serif = 'Nanum Myeongjo';
  static const String sans = 'Noto Sans KR';
  // --font-mono 는 현재 어떤 컴포넌트도 참조하지 않지만 CSS 원본과의
  // 1:1 대응을 위해 이름만 옮겨 둔다 (Flutter 기본 모노스페이스로 폴백).
  static const String mono = 'SFMono-Regular';
}

/// 글자 두께. Dart 관례상 `FontWeight` 상수를 그대로 노출한다.
abstract final class BaraedaFontWeight {
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight black = FontWeight.w800;
}

/// 글자 크기 — CSS `--fs-*` 를 논리 픽셀로 그대로 옮긴 값.
abstract final class BaraedaFontSize {
  static const double display = 52;
  static const double h1 = 40;
  static const double h2 = 32;
  static const double h3 = 24;
  static const double bodyLg = 18;
  static const double body = 16;
  static const double bodySm = 15;
  static const double caption = 14;
  static const double micro = 13;
  static const double label = 15;
  static const double labelSm = 13;
  static const double numeric = 20;
}

/// 완성된 텍스트 스타일 — 위젯은 이 클래스만 참조한다.
///
/// CSS 의 `line-height` 는 단위 없는 배수라 Flutter `TextStyle.height` 와
/// 그대로 대응한다. `letter-spacing` 은 CSS 가 `em`(폰트 크기 비례)인데
/// Flutter 는 논리 픽셀 절댓값이라 `em * fontSize` 로 환산해 옮겼다
/// (예: display -0.02em × 52px = -1.04).
abstract final class BaraedaTypography {
  static const TextStyle display = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.display,
    height: 1.16,
    letterSpacing: -1.04,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.h1,
    height: 1.2,
    letterSpacing: -0.8,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.h2,
    height: 1.2,
    letterSpacing: -0.48,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.h3,
    height: 1.3,
    letterSpacing: -0.24,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.bodyLg,
    height: 1.7,
  );

  static const TextStyle body = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.body,
    height: 1.75,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.bodySm,
    height: 1.7,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.light,
    fontSize: BaraedaFontSize.caption,
    height: 1.55,
    letterSpacing: -0.14,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.light,
    fontSize: BaraedaFontSize.micro,
    height: 1.5,
    letterSpacing: -0.13,
  );

  static const TextStyle label = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.medium,
    fontSize: BaraedaFontSize.label,
    height: 1.2,
    letterSpacing: -0.15,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.medium,
    fontSize: BaraedaFontSize.labelSm,
    height: 1.2,
  );

  /// 시각·호차 표기용. readme.md VISUAL FOUNDATIONS: "시각·호차 700 + tabular-nums".
  static const TextStyle numeric = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.numeric,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
