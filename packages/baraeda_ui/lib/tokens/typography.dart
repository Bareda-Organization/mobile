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

/// 글자 크기 — **시안 8단계**(`mkit` `--t-cap` ~ `--t-count`)만 쓴다. 이 밖의 크기는 만들지 않는다.
///
/// 13 칩·힌트·탭 이름 · 14 보조 줄·작은 단추 · 16 본문·목록 제목·단추·입력 · 20 시트·대화상자·빈 상태 제목·큰 단추 ·
/// 24 화면 제목 · 30 숫자 칸·운행 중 다음 승하차지 · 40 큰 숫자(출발 시각) · 52 카운트다운.
/// 예전 15·18·32 는 가까운 단계로 옮겼다(15→14·16, 18→16, 32→30).
abstract final class BaraedaFontSize {
  static const double cap = 13;
  static const double sub = 14;
  static const double bodyBase = 16;
  static const double title = 20;
  static const double h1Screen = 24;
  static const double disp = 30;
  static const double num = 40;
  static const double count = 52;

  /// 8단계 전체 — 시험이 모든 [BaraedaTypography] 스타일의 크기가 여기에 속하는지 본다.
  static const List<double> scale = [
    cap,
    sub,
    bodyBase,
    title,
    h1Screen,
    disp,
    num,
    count,
  ];

  // 예전 이름 — 같은 8단계 값을 가리킨다. 위젯 쪽 호출부를 안 깨려고 이름을 남겼다.
  static const double display = count;
  static const double h1 = num;
  static const double h2 = disp;
  static const double h3 = h1Screen;
  static const double bodyLg = bodyBase;
  static const double body = bodyBase;
  static const double bodySm = bodyBase;
  static const double caption = sub;
  static const double micro = cap;
  static const double label = sub;
  static const double labelSm = cap;
  static const double numeric = title;
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
    letterSpacing: -0.6,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.h3,
    height: 1.25,
    letterSpacing: -0.36,
  );

  /// 시트·대화상자·빈 상태 제목(20) — 시안 `.m-sheet__h h2` · `.m-dialog h2`.
  static const TextStyle title = TextStyle(
    fontFamily: BaraedaFontFamily.serif,
    fontWeight: BaraedaFontWeight.bold,
    fontSize: BaraedaFontSize.title,
    height: 1.3,
    letterSpacing: -0.2,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.bodyLg,
    height: 1.5,
  );

  static const TextStyle body = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.body,
    height: 1.5,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.bodySm,
    height: 1.45,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.caption,
    height: 1.4,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.regular,
    fontSize: BaraedaFontSize.micro,
    height: 1.3,
  );

  static const TextStyle label = TextStyle(
    fontFamily: BaraedaFontFamily.sans,
    fontWeight: BaraedaFontWeight.medium,
    fontSize: BaraedaFontSize.label,
    height: 1.3,
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
