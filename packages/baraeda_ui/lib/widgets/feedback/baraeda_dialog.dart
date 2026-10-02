// 확정이 필요한 행동 확인 — 삭제, 강제 추가, 지연 알림 전송 확인.
// 원본: `frontend/design-system/components/feedback/Dialog.jsx`.
//
// Flutter `material.Dialog` 와 이름이 겹쳐 `Baraeda` 접두를 붙인다
// (CONVENTIONS_FLUTTER 회차 지시 — BottomSheet 와 같은 규칙).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/button.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 화면 전체를 덮는 확인 대화상자.
///
/// 반드시 [Stack] 의 직계 자식으로 두어야 한다 — 내부에서 [Positioned.fill] 로
/// 스스로를 부모 크기만큼 펼친다(React 원본의 `position:absolute; inset:0`와 동일한 전제).
/// 확인·취소 대화상자를 라우트로 띄우려면 [showBaraedaConfirmDialog] 를 쓴다.
///
/// 본문이 길거나 글자가 커도 넘치지 않고 **본문만 스크롤**된다(버튼은 고정).
/// 안드로이드 뒤로가기는 [onClose] 로 가고, 뒤 화면은 낭독기에서 가려진다.
class BaraedaDialog extends StatelessWidget {
  const new({
    super.key,
    this.title,
    this.body,
    this.content,
    this.footer,
    this.onClose,
    this.width = 420,
  });

  final String? title;

  /// 본문. React 쪽 `children`에 대응.
  final String? body;

  /// 문자열이 아닌 본문(예: 비동기로 채워지는 문구). [body] 와 함께 주면 이쪽이 이긴다.
  final Widget? content;

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

    final bodyWidget =
        content ??
        (body == null
            ? null
            : WordWrapText(
                body!,
                style: BaraedaTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ));

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
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 제목은 위 Semantics(namesRoute) 라벨이 이미 읽는다.
                                    if (title != null)
                                      ExcludeSemantics(
                                        child: Text(
                                          title!,
                                          style: BaraedaTypography.h3.copyWith(
                                            fontSize: 22,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    if (bodyWidget != null)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: title != null ? 10 : 0,
                                        ),
                                        child: bodyWidget,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (footer != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: footer,
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
          ),
        ),
      ),
    );
  }
}

/// 확인·취소 대화상자를 라우트로 띄운다 — 확인이면 `true`, 취소·바깥 탭·뒤로가기면 `false`.
///
/// Material `AlertDialog` 대신 쓰는 공용판이다.
/// 낭독 배경 차단·본문 스크롤·뒤로가기 처리는 [BaraedaDialog] 가 맡는다.
/// [dismissible] 이 `false` 면 바깥 탭·뒤로가기로 닫히지 않는다 — 버튼으로만 닫힌다.
/// 문자열이 아닌 본문(비동기로 채워지는 문구)은 [content] 로 준다.
Future<bool> showBaraedaConfirmDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String? body,
  Widget? content,
  String cancelLabel = '취소',
  bool dismissible = true,
}) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: title,
    // 스크림은 BaraedaDialog 가 직접 그린다 — 라우트 배리어는 투명으로 둔다.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (dialogContext, _, _) => Stack(
      children: [
        BaraedaDialog(
          title: title,
          body: body,
          content: content,
          onClose: dismissible
              ? () => Navigator.of(dialogContext).pop(false)
              : null,
          // Wrap 은 버튼을 가로 전체로 늘리므로 Row 로 둔다(버튼은 내용 너비).
          footer: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BaraedaButton(
                label: cancelLabel,
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(width: BaraedaSpacing.space2),
              BaraedaButton(
                label: confirmLabel,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
