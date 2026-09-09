// 바래다 `ThemeData` — 라이트(학부모 앱 기본) / 다크(매니저 앱 기본 · 야간 하원 화면).
// CONVENTIONS_FLUTTER.md §3: "다크는 매니저 앱의 기본값" — `ThemeMode` 선택은
// 앱(`apps/*`) 쪽 책임이고, 이 패키지는 두 `ThemeData` 를 만들어 제공하기만 한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 라이트/다크 `ThemeData` 를 만드는 정적 팩토리 모음.
abstract final class BaraedaTheme {
  static ThemeData light() =>
      _build(brightness: Brightness.light, semantic: BaraedaColors.light);

  static ThemeData dark() =>
      _build(brightness: Brightness.dark, semantic: BaraedaColors.dark);

  static ThemeData _build({
    required Brightness brightness,
    required BaraedaColors semantic,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: semantic.accentPrimary,
      onPrimary: semantic.textInverse,
      secondary: semantic.accentSecondary,
      onSecondary: semantic.textInverse,
      error: semantic.statusMissed,
      onError: semantic.textInverse,
      surface: semantic.surfaceCard,
      onSurface: semantic.textPrimary,
    );

    final textTheme = TextTheme(
      displayLarge: BaraedaTypography.display.copyWith(
        color: semantic.textPrimary,
      ),
      headlineLarge: BaraedaTypography.h1.copyWith(color: semantic.textPrimary),
      headlineMedium: BaraedaTypography.h2.copyWith(
        color: semantic.textPrimary,
      ),
      headlineSmall: BaraedaTypography.h3.copyWith(color: semantic.textPrimary),
      bodyLarge: BaraedaTypography.bodyLg.copyWith(color: semantic.textPrimary),
      bodyMedium: BaraedaTypography.body.copyWith(color: semantic.textPrimary),
      bodySmall: BaraedaTypography.bodySm.copyWith(
        color: semantic.textSecondary,
      ),
      labelLarge: BaraedaTypography.label.copyWith(color: semantic.textPrimary),
      labelSmall: BaraedaTypography.labelSm.copyWith(
        color: semantic.textSecondary,
      ),
      // CSS `--text-caption`·`--fs-micro` 는 Material 기본 슬롯에 깔끔히
      // 대응하지 않아 캡션류는 `BaraedaTypography.caption`/`micro` 를 위젯이
      // 직접 참조한다 (M3 TextTheme 은 caption 슬롯을 두지 않는다 — bodySmall 로 흡수됨).
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: semantic.bgBase,
      canvasColor: semantic.bgBase,
      fontFamily: BaraedaFontFamily.sans,
      textTheme: textTheme,
      dividerColor: semantic.borderSubtle,
      splashFactory: NoSplash.splashFactory, // readme.md: 색 반전 없는 프레스만
      cardTheme: CardThemeData(
        color: semantic.surfaceCard,
        elevation: 0, // 그림자는 BaraedaShadows 로 직접 그린다 (Material elevation 미사용)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: semantic.surfaceChrome,
        foregroundColor: semantic.textOnChrome,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: BaraedaTypography.h3.copyWith(
          color: semantic.textOnChrome,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: semantic.accentPrimary,
          foregroundColor: semantic.textInverse,
          // 세로만 최소 터치 영역(48)으로 잡는다. Size.fromHeight 는 가로를
          // double.infinity 로 두어 Row 안에 놓으면 무한 폭 예외가 난다 —
          // 가로 100% 는 화면이 정할 일이지 테마 기본값이 아니다.
          minimumSize: const Size(0, BaraedaSpacing.tapMin),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BaraedaRadius.control),
          ),
          textStyle: BaraedaTypography.label,
        ),
      ),
      focusColor: semantic.focusRing,
      extensions: [semantic],
    );
  }
}
