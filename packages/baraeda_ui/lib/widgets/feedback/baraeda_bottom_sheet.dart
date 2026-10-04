// 지도 위에서 정보를 겹쳐 보여줄 때 — 실시간 위치 화면의 운행 요약, 정류장 상세.
// 원본: `frontend/design-system/components/feedback/BottomSheet.jsx` + 시안 `.m-sheet`.
//
// Flutter `showModalBottomSheet`/`material.BottomSheet` 와 이름이 겹쳐
// `Baraeda` 접두를 붙인다(팀 리드 지시).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_drive_zone.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon_button.dart';
import 'package:flutter/material.dart';

/// 지도 위에 겹쳐 뜨는 바텀시트.
///
/// 반드시 [Stack] 의 직계 자식으로 두어야 한다 — 내부에서 [Positioned.fill] 로
/// 스스로를 부모 크기만큼 펼친다. 상단만 둥근 모서리이며, 세 제품 중
/// 유일하게 `--shadow-sheet`(위로 뻗는 그림자)를 쓴다.
/// 내용이 길면 내용만 스크롤되고, 키보드가 올라오면 시트가 그만큼 올라간다.
/// 안드로이드 뒤로가기는 [onClose] 로 가고, 뒤 화면은 낭독기에서 가려진다.
/// 라우트로 띄우려면 [showBaraedaBottomSheet] 를 쓴다.
class BaraedaBottomSheet extends StatelessWidget {
  const new({
    super.key,
    this.title,
    this.child,
    this.onClose,
    this.showCloseButton = false,
    this.entrance,
    this.motion = BaraedaOpenMotion.none,
  });

  final String? title;
  final Widget? child;
  final VoidCallback? onClose;

  /// 제목 줄 오른쪽에 닫기(X) 단추를 둔다(시안 `.m-sheet__h`). [title] 이 있어야 보인다.
  final bool showCloseButton;

  /// 열릴 때의 진행값(보통 라우트 애니메이션). 비우면 움직임 없이 바로 보인다.
  final Animation<double>? entrance;

  /// [entrance] 를 쓰는 방식 — full 은 240ms 서랍 곡선으로 올라오고, fadeOnly 는 투명도만 바뀐다.
  final BaraedaOpenMotion motion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mediaQuery = MediaQuery.of(context);
    final keyboard = mediaQuery.viewInsets.bottom;
    final animation = entrance;

    Widget scrim = GestureDetector(
      onTap: onClose,
      child: Container(color: colors.overlayScrim),
    );
    Widget panel = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          BaraedaSpacing.space4,
          BaraedaSpacing.space2,
          BaraedaSpacing.space4,
          // 홈 인디케이터 영역만큼 더 띄운다(키보드가 올라오면 0).
          BaraedaSpacing.space6 + mediaQuery.padding.bottom,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(BaraedaRadius.sheet),
            topRight: Radius.circular(BaraedaRadius.sheet),
          ),
          boxShadow: BaraedaShadows.sheet,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: BaraedaSpacing.space3),
                decoration: BoxDecoration(
                  color: colors.borderDefault,
                  borderRadius: BorderRadius.circular(BaraedaRadius.pill),
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: BaraedaSpacing.space3),
                child: Row(
                  children: [
                    Expanded(
                      // 제목은 위 Semantics(namesRoute) 라벨이 이미 읽는다.
                      child: ExcludeSemantics(
                        child: Text(
                          title!,
                          style: BaraedaTypography.title.copyWith(
                            height: 1.3,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (showCloseButton && onClose != null)
                      BaraedaIconButton(
                        icon: 'x',
                        label: '닫기',
                        size: BaraedaSpacing.tap,
                        onPressed: onClose,
                      ),
                  ],
                ),
              ),
            if (child != null)
              Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );

    if (animation != null && motion != BaraedaOpenMotion.none) {
      // 시안: 막은 160ms 로 어두워지고, 시트는 240ms 서랍 곡선으로 올라온다.
      scrim = FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Interval(
            0,
            BaraedaDuration.scrim.inMilliseconds /
                BaraedaDuration.sheet.inMilliseconds,
            curve: BaraedaCurve.easeOut,
          ),
        ),
        child: scrim,
      );
      panel = motion == BaraedaOpenMotion.full
          ? SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: BaraedaCurve.drawer,
                    ),
                  ),
              child: panel,
            )
          : FadeTransition(opacity: animation, child: panel);
    }

    return Positioned.fill(
      child: BlockSemantics(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onClose?.call();
          },
          // 라우트로 띄우면 Material 조상이 없다 — 글자 기본 서식·잉크·칩이 쓰도록 투명 Material 을 둔다.
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(child: scrim),
                // 키보드가 올라오면 그만큼 시트를 올리고, 남은 높이 안에서 내용만 스크롤한다.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: keyboard),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (mediaQuery.size.height - keyboard) * 0.92,
                      ),
                      child: panel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 바닥 시트를 라우트로 띄운다 — [builder] 안에서 `Navigator.pop(context, 값)` 으로 결과를 돌려주고,
/// 바깥 탭·뒤로가기로 닫으면 `null` 이다. Material `showModalBottomSheet` 대신 쓰는 공용판이다.
///
/// 열릴 때 240ms 서랍 곡선으로 올라온다. 움직임 줄이기가 켜져 있으면 투명도만, 운행 중
/// 다크 구역에서 부르면 움직임 없이 바로 뜬다.
Future<T?> showBaraedaBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool showCloseButton = false,
}) {
  final motion = BaraedaOpenMotion.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: title,
    // 스크림은 BaraedaBottomSheet 가 직접 그린다 — 라우트 배리어는 투명으로 둔다.
    barrierColor: Colors.transparent,
    transitionDuration: motion == BaraedaOpenMotion.none
        ? Duration.zero
        : BaraedaDuration.sheet,
    // 막 · 시트의 움직임은 BaraedaBottomSheet 가 직접 정한다.
    transitionBuilder: (context, animation, _, child) => child,
    pageBuilder: (sheetContext, animation, _) => BaraedaDriveZone.carry(
      context,
      Stack(
        children: [
          BaraedaBottomSheet(
            title: title,
            showCloseButton: showCloseButton,
            entrance: animation,
            motion: motion,
            onClose: () => Navigator.of(sheetContext).pop(),
            child: Builder(builder: builder),
          ),
        ],
      ),
    ),
  );
}
