// 확정이 필요한 행동 확인 — 삭제, 강제 추가, 지연 알림 전송 확인.
// 원본: `frontend/design-system/components/feedback/Dialog.jsx`.
//
// Flutter `material.Dialog` 와 이름이 겹쳐 `Baraeda` 접두를 붙인다
// (CONVENTIONS_FLUTTER 회차 지시 — BottomSheet 와 같은 규칙).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 화면 전체를 덮는 확인 대화상자.
///
/// 반드시 [Stack] 의 직계 자식으로 두어야 한다 — 내부에서 [Positioned.fill] 로
/// 스스로를 부모 크기만큼 펼친다(React 원본의 `position:absolute; inset:0`와 동일한 전제).
class BaraedaDialog extends StatelessWidget {
  const BaraedaDialog({
    super.key,
    this.title,
    this.body,
    this.footer,
    this.onClose,
    this.width = 420,
  });

  final String? title;

  /// 본문. React 쪽 `children`에 대응.
  final String? body;

  /// 버튼 영역 — 취소는 ghost, 확정은 primary 또는 danger.
  final Widget? footer;

  final VoidCallback? onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? BaraedaShadows.raisedDark
        : BaraedaShadows.raisedLight;

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: colors.overlayScrim,
          padding: const EdgeInsets.all(BaraedaSpacing.space5),
          alignment: Alignment.center,
          child: GestureDetector(
            // 안쪽 카드 탭은 스크림 탭(닫기)으로 전파하지 않는다.
            onTap: () {},
            child: Semantics(
              namesRoute: true,
              label: title,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(BaraedaSpacing.space6),
                  decoration: BoxDecoration(
                    color: colors.surfaceCard,
                    borderRadius: BorderRadius.circular(BaraedaRadius.xl),
                    boxShadow: shadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: BaraedaTypography.h3.copyWith(
                            fontSize: 22,
                            height: 1.35,
                          ),
                        ),
                      if (body != null)
                        Padding(
                          padding: EdgeInsets.only(top: title != null ? 10 : 0),
                          child: Text(
                            body!,
                            style: BaraedaTypography.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      if (footer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [footer!],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
