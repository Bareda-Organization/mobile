// 원본 `design-system/components/core/IconButton.jsx` 대응.
// 원본 prompt.md: "label은 필수입니다" — 아이콘만으로는 스크린 리더가 의미를
// 읽을 수 없어 [label]을 필수 파라미터로 두고 [Semantics]에 그대로 싣는다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 아이콘 버튼 톤. plain=배경 없음 · soft=미스트 원형 배경 ·
/// inverse=어두운 배경 위(예: 지도 오버레이).
enum BaraedaIconButtonTone { plain, soft, inverse }

/// 아이콘 단독 버튼 — 헤더 액션·목록 행의 전화 버튼 등.
///
/// 아이콘만으로 의미가 전달되므로 [label]이 필수다(스크린 리더용
/// `Semantics.label`). 텍스트와 함께 쓰는 장식 아이콘은 `BaraedaIcon`을
/// 직접 쓴다.
class BaraedaIconButton extends StatelessWidget {
  const BaraedaIconButton({
    required this.icon,
    required this.label,
    super.key,
    this.onPressed,
    this.tone = BaraedaIconButtonTone.plain,
    this.size = BaraedaSpacing.tapMin,
  });

  /// Lucide 아이콘 이름.
  final String icon;

  /// 스크린 리더가 읽을 동작 설명. 예: `'알림 열기'`.
  final String label;

  final VoidCallback? onPressed;
  final BaraedaIconButtonTone tone;

  /// 탭 영역 한 변. 기본은 터치 최소 `BaraedaSpacing.tapMin`(48) 이다.
  final double size;

  bool get _disabled => onPressed == null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _paletteFor(tone, colors);
    final iconSize = size * 0.45;

    return Semantics(
      button: true,
      label: label,
      enabled: !_disabled,
      child: Opacity(
        opacity: _disabled ? 0.42 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _disabled ? null : onPressed,
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            hoverColor: Colors.black.withValues(alpha: 0.06),
            highlightColor: Colors.black.withValues(alpha: 0.1),
            focusColor: colors.focusRing.withValues(alpha: 0.32),
            mouseCursor: _disabled
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.click,
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: palette.background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: BaraedaIcon(
                  icon,
                  size: iconSize,
                  color: palette.foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButtonPalette {
  const _IconButtonPalette({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

_IconButtonPalette _paletteFor(BaraedaIconButtonTone tone, BaraedaColors c) {
  switch (tone) {
    case BaraedaIconButtonTone.plain:
      return _IconButtonPalette(
        background: Colors.transparent,
        foreground: c.textPrimary,
      );
    case BaraedaIconButtonTone.soft:
      return _IconButtonPalette(
        background: c.accentPrimarySoft,
        foreground: c.textBrand,
      );
    case BaraedaIconButtonTone.inverse:
      return _IconButtonPalette(
        background: c.overlayScrim,
        foreground: c.textInverse,
      );
  }
}
