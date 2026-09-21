// 앱 상단 바 — 홈은 brand(그린), 설정·상세는 plain.
// 원본: `frontend/design-system/components/navigation/AppHeader.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// [AppHeader] 의 배경 톤.
///
/// brand=크롬 면(오프화이트 + 하단 선, 다크에선 딥) · plain=본문과 같은 바탕.
enum AppHeaderTone { brand, plain }

/// 앱 상단 바.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions,
    this.tone = AppHeaderTone.brand,
  });

  final String? title;

  /// 호차·매니저 등 메타 한 줄.
  final String? subtitle;

  /// 지정하면 뒤로가기 버튼을 그린다.
  final VoidCallback? onBack;

  /// 오른쪽 아이콘 버튼 영역.
  final Widget? actions;

  final AppHeaderTone tone;

  @override
  Size get preferredSize => const Size.fromHeight(BaraedaSpacing.headerHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inverse = tone == AppHeaderTone.brand;
    final background = inverse ? colors.surfaceChrome : colors.bgBase;
    final foreground = inverse ? colors.textOnChrome : colors.textPrimary;
    final borderColor = inverse ? colors.borderChrome : colors.borderSubtle;

    return Semantics(
      header: true,
      // 상태 표시줄을 비켜선다 — Material `AppBar` 는 안쪽에서 이 일을 해 주지만 직접 만든
      // `PreferredSizeWidget` 은 스스로 해야 한다. `Scaffold` 가 머리말 자리를
      // `preferredSize.height + MediaQuery.padding.top` 으로 이미 잡아 두므로
      // 여기서 높이를 더하지 않고 **내용만 아래로 민다**.
      //
      // ⚠ 없으면 제목·뒤로 버튼이 시계·배터리 위에 겹쳐 그려진다(2026-09-20 iPhone 17 Pro
      // 실측 — 제목이 y=7.5 에서 시작, 상태 표시줄은 59). `bottom: false` 인 것은 이 위젯이
      // 화면 맨 위에만 놓이기 때문이다 — 아래 여백까지 먹으면 본문이 밀린다.
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: BaraedaSpacing.headerHeight,
          ),
          padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  tooltip: '뒤로',
                  icon: BaraedaIcon(
                    'chevron-left',
                    size: 22,
                    color: foreground,
                  ),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // 원본 17px/1.3 은 BaraedaTypography 프리셋과 정확히 맞는 값이
                        // 없어(label=15/h3=24) label 을 베이스로 크기만 보정한다.
                        style: BaraedaTypography.label.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          fontSize: 17,
                          height: 1.3,
                          letterSpacing: -0.17,
                          color: foreground,
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BaraedaTypography.micro.copyWith(
                          height: 1.4,
                          color: inverse
                              ? colors.textOnChromeMuted
                              : colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (actions != null) actions!,
            ],
          ),
        ),
      ),
    );
  }
}
