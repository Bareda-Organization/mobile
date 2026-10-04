// 앱 머리줄 — 화면 제목 24(나눔명조) + 부제 한 줄 + 오른쪽 행동(시안 `.m-appbar`).
// 원본: `frontend/design-system/components/navigation/AppHeader.jsx`.
//
// 긴 이름 규칙(시안 ⑤-4): 부제는 **한 줄에서 `…`** 로 자른다 — 비상 버튼 밑으로 흘러들지 않게.
// 부제가 잘려도 전체 이름은 내 정보 탭에 있다. 제목도 한 줄이다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// [AppHeader] 의 배경 톤.
///
/// brand=크롬 면(오프화이트 + 하단 선, 다크에선 딥) · plain=본문과 같은 바탕 ·
/// floating=지도 위에 떠 있는 줄(면 없음 + 제목은 흰 알약 안, 부제 없음).
enum AppHeaderTone { brand, plain, floating }

/// 앱 상단 바.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const new({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions,
    this.tone = AppHeaderTone.brand,
  });

  final String? title;

  /// 호차·매니저 등 메타 한 줄. 한 줄이 넘으면 `…` 로 자른다.
  final String? subtitle;

  /// 뒤로가기 동작. 비우면 뒤에 화면이 있을 때만 돌아가는 버튼을 그린다
  /// (Material `AppBar` 의 `automaticallyImplyLeading` 과 같은 규칙 —
  /// 2026-09-29, 화면마다 넘기게 두었더니 학부모 앱 5개 화면이 빠뜨렸다).
  final VoidCallback? onBack;

  /// 오른쪽 아이콘 버튼 영역(예: 비상 버튼).
  final Widget? actions;

  final AppHeaderTone tone;

  @override
  Size get preferredSize => Size.fromHeight(
    // 부제가 있으면 제목 24 + 부제 14 가 56 에 들어가지 않는다.
    subtitle != null && tone != AppHeaderTone.floating
        ? BaraedaSpacing.headerHeight + 8
        : BaraedaSpacing.headerHeight,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final floating = tone == AppHeaderTone.floating;
    final chrome = tone == AppHeaderTone.brand;
    final background = floating
        ? Colors.transparent
        : (chrome ? colors.surfaceChrome : colors.bgBase);
    final foreground = chrome ? colors.textOnChrome : colors.textPrimary;
    final borderColor = chrome ? colors.borderChrome : colors.borderSubtle;
    final back =
        onBack ??
        (Navigator.canPop(context) ? () => Navigator.maybePop(context) : null);

    final titleWidget = title == null
        ? null
        : (floating
              // 지도 위: 흰 알약 안의 16px 제목(지도 위 글자는 잉크 고정).
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.mapControlSurface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(BaraedaRadius.pill),
                    border: Border.all(color: colors.mapControlLine),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BaraedaTypography.label.copyWith(
                        fontSize: BaraedaFontSize.bodyBase,
                        fontWeight: BaraedaFontWeight.bold,
                        color: colors.onMapControl,
                        height: 1.25,
                      ),
                    ),
                  ),
                )
              : Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BaraedaTypography.h3.copyWith(color: foreground),
                ));

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
          constraints: BoxConstraints(minHeight: preferredSize.height),
          // 뒤로 버튼이 있으면 왼쪽을 4 로 줄여 쉐브론이 가장자리에 붙는다(시안 `.has-back`).
          padding: EdgeInsets.fromLTRB(
            back != null ? 6 : BaraedaSpacing.gutterMobile,
            BaraedaSpacing.space1,
            BaraedaSpacing.space2,
            BaraedaSpacing.space1,
          ),
          decoration: BoxDecoration(
            color: background,
            border: floating
                ? null
                : Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              if (back != null)
                IconButton(
                  onPressed: back,
                  tooltip: '뒤로',
                  icon: BaraedaIcon(
                    'chevron-left',
                    size: 24,
                    color: floating ? colors.onMapControl : foreground,
                  ),
                ),
              Expanded(
                // 머리줄 높이는 `preferredSize` 로 정해져 글자가 커져도 늘어날 수 없다 —
                // 글자 배율이 넘치지 않는 한도로 묶는다(제목 24 + 부제 14 가 64 에 들어가는 1.1배,
                // 부제가 없으면 1.6배). 부제 · 제목은 한 줄이라 잘려도 전체 이름은 다른 화면에 있다.
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: MediaQuery.textScalerOf(context).clamp(
                      maxScaleFactor: subtitle != null && !floating ? 1.1 : 1.6,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: floating
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      ?titleWidget,
                      if (subtitle != null && !floating)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BaraedaTypography.caption.copyWith(
                            height: 1.3,
                            color: chrome
                                ? colors.textOnChromeMuted
                                : colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ?actions,
            ],
          ),
        ),
      ),
    );
  }
}
