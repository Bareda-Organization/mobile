// 바래다 의미 색 계층 — 컴포넌트는 항상 이 레이어만 참조한다.
// `frontend/design-system/tokens/semantic.css` 의 `:root`(라이트)와
// `[data-theme="dark"]`(다크) 두 벌을 1:1 로 이식한 것.
//
// 상태 색 매핑은 이 파일 한 곳에서만 정한다(CONVENTIONS_FLUTTER.md §3) —
// boarded 그린 · moving 앰버 · missed 레드 · idle 스톤. 위젯은 여기 정의된
// `statusBoarded` 등의 이름만 쓰고 원시 팔레트를 직접 고르지 않는다.

import 'package:baraeda_ui/tokens/colors.dart';
import 'package:flutter/material.dart';

/// 의미 색 세트. `ThemeExtension` 으로 노출해 위젯이 `context.colors.statusBoarded`
/// 처럼 테마를 거쳐 참조하게 한다.
@immutable
class BaraedaColors extends ThemeExtension<BaraedaColors> {
  const BaraedaColors({
    required this.bgBase,
    required this.bgSubtle,
    required this.surfaceCard,
    required this.surfaceRaised,
    required this.surfaceInverse,
    required this.surfaceSunken,
    required this.surfaceChrome,
    required this.textOnChrome,
    required this.textOnChromeMuted,
    required this.borderChrome,
    required this.navText,
    required this.navActiveBg,
    required this.navActiveText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.textOnInverseMuted,
    required this.textBrand,
    required this.textLink,
    required this.textLinkHover,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.borderInverse,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.accentPrimaryPress,
    required this.accentPrimarySoft,
    required this.accentSecondary,
    required this.accentSecondarySoft,
    required this.statusBoarded,
    required this.statusBoardedSoft,
    required this.statusMoving,
    required this.statusMovingSoft,
    required this.statusMissed,
    required this.statusMissedSoft,
    required this.statusIdle,
    required this.statusIdleSoft,
    required this.focusRing,
    required this.overlayScrim,
    required this.mapRoute,
    required this.mapBus,
  });

  // 면
  final Color bgBase;
  final Color bgSubtle;
  final Color surfaceCard;
  final Color surfaceRaised;
  final Color surfaceInverse;
  final Color surfaceSunken;

  // 크롬 — 헤더·사이드바
  final Color surfaceChrome;
  final Color textOnChrome;
  final Color textOnChromeMuted;
  final Color borderChrome;
  final Color navText;
  final Color navActiveBg;
  final Color navActiveText;

  // 텍스트
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color textOnInverseMuted;
  final Color textBrand;
  final Color textLink;
  final Color textLinkHover;

  // 테두리
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;
  final Color borderInverse;

  // 액션
  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color accentPrimaryPress;
  final Color accentPrimarySoft;
  final Color accentSecondary;
  final Color accentSecondarySoft;

  // 상태 — 세 제품에서 같은 상태는 항상 같은 색.
  final Color statusBoarded;
  final Color statusBoardedSoft;
  final Color statusMoving;
  final Color statusMovingSoft;
  final Color statusMissed;
  final Color statusMissedSoft;
  final Color statusIdle;
  final Color statusIdleSoft;

  final Color focusRing;
  final Color overlayScrim;
  final Color mapRoute;
  final Color mapBus;

  /// `semantic.css` `:root` — 라이트.
  static const BaraedaColors light = BaraedaColors(
    bgBase: BaraedaPalette.pageTint,
    bgSubtle: BaraedaPalette.green100,
    surfaceCard: BaraedaPalette.white,
    surfaceRaised: BaraedaPalette.white,
    surfaceInverse: BaraedaPalette.green600,
    surfaceSunken: BaraedaPalette.green50,
    surfaceChrome: BaraedaPalette.offWhite,
    textOnChrome: BaraedaPalette.ink,
    textOnChromeMuted: BaraedaPalette.stone500,
    borderChrome: Color(0xFFE2E6E3),
    navText: BaraedaPalette.stone600,
    navActiveBg: BaraedaPalette.green100,
    navActiveText: BaraedaPalette.green600,
    textPrimary: BaraedaPalette.ink,
    textSecondary: Color(0xFF5C665F),
    // 옅은 면(`bgSubtle`) 위에서도 4.5:1 이상 — 예전 stone400 은 흰 카드 위에서 2.93 이었다(F07-09).
    textTertiary: Color(0xFF626D69),
    textInverse: BaraedaPalette.white,
    textOnInverseMuted: BaraedaPalette.green200,
    textBrand: BaraedaPalette.green600,
    textLink: BaraedaPalette.green600,
    textLinkHover: BaraedaPalette.green700,
    borderSubtle: BaraedaPalette.stone200,
    borderDefault: BaraedaPalette.stone300,
    borderStrong: BaraedaPalette.green600,
    borderInverse: Color(0x2EFFFFFF), // rgba(255,255,255,.18)
    accentPrimary: BaraedaPalette.green600,
    accentPrimaryHover: BaraedaPalette.green700,
    accentPrimaryPress: BaraedaPalette.green800,
    accentPrimarySoft: BaraedaPalette.green100,
    accentSecondary: BaraedaPalette.amber500,
    accentSecondarySoft: BaraedaPalette.amber100,
    statusBoarded: BaraedaPalette.green600,
    statusBoardedSoft: BaraedaPalette.green100,
    statusMoving: BaraedaPalette.amberInk,
    statusMovingSoft: BaraedaPalette.amber100,
    statusMissed: BaraedaPalette.redInk,
    statusMissedSoft: BaraedaPalette.red100,
    statusIdle:
        BaraedaPalette.stone600, // stone500 은 stone100 알약 위 4.04 — F07-09
    statusIdleSoft: BaraedaPalette.stone100,
    focusRing: BaraedaPalette.green500,
    overlayScrim: Color(0x7A12211C), // rgba(18,33,28,.48)
    mapRoute: BaraedaPalette.green600,
    mapBus: BaraedaPalette.amber500,
  );

  /// `semantic.css` `[data-theme="dark"]` — 매니저 앱 기본값 · 야간 하원 화면.
  static const BaraedaColors dark = BaraedaColors(
    bgBase: Color(0xFF0F1412),
    bgSubtle: Color(0xFF171E1B),
    surfaceCard: Color(0xFF181F1D),
    surfaceRaised: Color(0xFF212927),
    surfaceInverse: BaraedaPalette.green600,
    surfaceSunken: Color(0xFF0A0E0D),
    surfaceChrome: Color(0xFF131917),
    textOnChrome: Color(0xFFEDF2EF),
    textOnChromeMuted: Color(0xFFA3AFAA),
    borderChrome: Color(0x21EDF2EF), // rgba(237,242,239,.13)
    navText: Color(0xFFA3AFAA),
    navActiveBg: Color(0x2EF5A623), // rgba(245,166,35,.18)
    navActiveText: BaraedaPalette.amber400,
    textPrimary: Color(0xFFEDF2EF),
    textSecondary: Color(0xFFA3AFAA),
    textTertiary: Color(0xFF7D8884),
    textInverse: Color(0xFF1A1206),
    textOnInverseMuted: BaraedaPalette.green200,
    textBrand: BaraedaPalette.amber500,
    textLink: BaraedaPalette.amber500,
    textLinkHover: BaraedaPalette.amber300,
    borderSubtle: Color(0x21EDF2EF), // rgba(237,242,239,.13)
    borderDefault: Color(0x3DEDF2EF), // rgba(237,242,239,.24)
    borderStrong: BaraedaPalette.amber500,
    borderInverse: Color(0x21EDF2EF), // rgba(237,242,239,.13)
    accentPrimary: BaraedaPalette.amber500,
    accentPrimaryHover: BaraedaPalette.amber400,
    accentPrimaryPress: BaraedaPalette.amber600,
    accentPrimarySoft: Color(0x29F5A623), // rgba(245,166,35,.16)
    accentSecondary: Color(0xFF5FD0AC),
    accentSecondarySoft: Color(0x295FD0AC), // rgba(95,208,172,.16)
    statusBoarded: Color(0xFF5FD0AC),
    statusBoardedSoft: Color(0x295FD0AC), // rgba(95,208,172,.16)
    statusMoving: BaraedaPalette.amber500,
    statusMovingSoft: Color(0x29F5A623), // rgba(245,166,35,.16)
    statusMissed: BaraedaPalette.red300,
    statusMissedSoft: Color(0x2EF08A7A), // rgba(240,138,122,.18)
    statusIdle: Color(0xFF93A09B),
    statusIdleSoft: Color(0x17EDF2EF), // rgba(237,242,239,.09)
    focusRing: BaraedaPalette.amber400,
    overlayScrim: Color(0xA9040807), // rgba(4,8,7,.66)
    mapRoute: Color(0xFF5FD0AC),
    mapBus: BaraedaPalette.amber500,
  );

  @override
  BaraedaColors copyWith({
    Color? bgBase,
    Color? bgSubtle,
    Color? surfaceCard,
    Color? surfaceRaised,
    Color? surfaceInverse,
    Color? surfaceSunken,
    Color? surfaceChrome,
    Color? textOnChrome,
    Color? textOnChromeMuted,
    Color? borderChrome,
    Color? navText,
    Color? navActiveBg,
    Color? navActiveText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? textOnInverseMuted,
    Color? textBrand,
    Color? textLink,
    Color? textLinkHover,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? borderInverse,
    Color? accentPrimary,
    Color? accentPrimaryHover,
    Color? accentPrimaryPress,
    Color? accentPrimarySoft,
    Color? accentSecondary,
    Color? accentSecondarySoft,
    Color? statusBoarded,
    Color? statusBoardedSoft,
    Color? statusMoving,
    Color? statusMovingSoft,
    Color? statusMissed,
    Color? statusMissedSoft,
    Color? statusIdle,
    Color? statusIdleSoft,
    Color? focusRing,
    Color? overlayScrim,
    Color? mapRoute,
    Color? mapBus,
  }) {
    return BaraedaColors(
      bgBase: bgBase ?? this.bgBase,
      bgSubtle: bgSubtle ?? this.bgSubtle,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceChrome: surfaceChrome ?? this.surfaceChrome,
      textOnChrome: textOnChrome ?? this.textOnChrome,
      textOnChromeMuted: textOnChromeMuted ?? this.textOnChromeMuted,
      borderChrome: borderChrome ?? this.borderChrome,
      navText: navText ?? this.navText,
      navActiveBg: navActiveBg ?? this.navActiveBg,
      navActiveText: navActiveText ?? this.navActiveText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      textOnInverseMuted: textOnInverseMuted ?? this.textOnInverseMuted,
      textBrand: textBrand ?? this.textBrand,
      textLink: textLink ?? this.textLink,
      textLinkHover: textLinkHover ?? this.textLinkHover,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      borderInverse: borderInverse ?? this.borderInverse,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentPrimaryHover: accentPrimaryHover ?? this.accentPrimaryHover,
      accentPrimaryPress: accentPrimaryPress ?? this.accentPrimaryPress,
      accentPrimarySoft: accentPrimarySoft ?? this.accentPrimarySoft,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentSecondarySoft: accentSecondarySoft ?? this.accentSecondarySoft,
      statusBoarded: statusBoarded ?? this.statusBoarded,
      statusBoardedSoft: statusBoardedSoft ?? this.statusBoardedSoft,
      statusMoving: statusMoving ?? this.statusMoving,
      statusMovingSoft: statusMovingSoft ?? this.statusMovingSoft,
      statusMissed: statusMissed ?? this.statusMissed,
      statusMissedSoft: statusMissedSoft ?? this.statusMissedSoft,
      statusIdle: statusIdle ?? this.statusIdle,
      statusIdleSoft: statusIdleSoft ?? this.statusIdleSoft,
      focusRing: focusRing ?? this.focusRing,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      mapRoute: mapRoute ?? this.mapRoute,
      mapBus: mapBus ?? this.mapBus,
    );
  }

  @override
  BaraedaColors lerp(ThemeExtension<BaraedaColors>? other, double t) {
    if (other is! BaraedaColors) return this;
    return BaraedaColors(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgSubtle: Color.lerp(bgSubtle, other.bgSubtle, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceInverse: Color.lerp(surfaceInverse, other.surfaceInverse, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceChrome: Color.lerp(surfaceChrome, other.surfaceChrome, t)!,
      textOnChrome: Color.lerp(textOnChrome, other.textOnChrome, t)!,
      textOnChromeMuted: Color.lerp(
        textOnChromeMuted,
        other.textOnChromeMuted,
        t,
      )!,
      borderChrome: Color.lerp(borderChrome, other.borderChrome, t)!,
      navText: Color.lerp(navText, other.navText, t)!,
      navActiveBg: Color.lerp(navActiveBg, other.navActiveBg, t)!,
      navActiveText: Color.lerp(navActiveText, other.navActiveText, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      textOnInverseMuted: Color.lerp(
        textOnInverseMuted,
        other.textOnInverseMuted,
        t,
      )!,
      textBrand: Color.lerp(textBrand, other.textBrand, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      textLinkHover: Color.lerp(textLinkHover, other.textLinkHover, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderInverse: Color.lerp(borderInverse, other.borderInverse, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentPrimaryHover: Color.lerp(
        accentPrimaryHover,
        other.accentPrimaryHover,
        t,
      )!,
      accentPrimaryPress: Color.lerp(
        accentPrimaryPress,
        other.accentPrimaryPress,
        t,
      )!,
      accentPrimarySoft: Color.lerp(
        accentPrimarySoft,
        other.accentPrimarySoft,
        t,
      )!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      accentSecondarySoft: Color.lerp(
        accentSecondarySoft,
        other.accentSecondarySoft,
        t,
      )!,
      statusBoarded: Color.lerp(statusBoarded, other.statusBoarded, t)!,
      statusBoardedSoft: Color.lerp(
        statusBoardedSoft,
        other.statusBoardedSoft,
        t,
      )!,
      statusMoving: Color.lerp(statusMoving, other.statusMoving, t)!,
      statusMovingSoft: Color.lerp(
        statusMovingSoft,
        other.statusMovingSoft,
        t,
      )!,
      statusMissed: Color.lerp(statusMissed, other.statusMissed, t)!,
      statusMissedSoft: Color.lerp(
        statusMissedSoft,
        other.statusMissedSoft,
        t,
      )!,
      statusIdle: Color.lerp(statusIdle, other.statusIdle, t)!,
      statusIdleSoft: Color.lerp(statusIdleSoft, other.statusIdleSoft, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      mapRoute: Color.lerp(mapRoute, other.mapRoute, t)!,
      mapBus: Color.lerp(mapBus, other.mapBus, t)!,
    );
  }
}

/// `context.colors.statusBoarded` 처럼 테마를 거쳐 의미 색을 읽기 위한 확장.
extension BaraedaColorsContext on BuildContext {
  BaraedaColors get colors =>
      Theme.of(this).extension<BaraedaColors>() ?? BaraedaColors.light;
}
