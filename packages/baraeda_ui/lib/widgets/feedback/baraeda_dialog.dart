// 확정이 필요한 행동 확인 — 삭제, 강제 추가, 지연 알림 전송 확인.
// 원본: `frontend/design-system/components/feedback/Dialog.jsx` + 시안 `.m-dialog`.
//
// Flutter `material.Dialog` 와 이름이 겹쳐 `Baraeda` 접두를 붙인다
// (CONVENTIONS_FLUTTER 회차 지시 — BottomSheet 와 같은 규칙).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_drive_zone.dart';
import 'package:baraeda_ui/tokens/motion.dart';
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
/// 확인·취소 대화상자를 라우트로 띄우려면 [showBaraedaConfirmDialog] 를,
/// 선택지가 셋 이상이면 [showBaraedaActionDialog] 를 쓴다.
///
/// 본문이 길거나 글자가 커도 넘치지 않고 **본문만 스크롤**된다(버튼은 고정).
/// 안드로이드 뒤로가기는 [onClose] 로 가고, **뒤 화면은 낭독기에서 가려진다**
/// (웹 `aria-modal` 대응, 시안 C5).
class BaraedaDialog extends StatelessWidget {
  const new({
    super.key,
    this.title,
    this.body,
    this.content,
    this.footer,
    this.actions,
    this.onClose,
    this.width = 420,
    this.entrance,
  });

  final String? title;

  /// 본문. React 쪽 `children`에 대응.
  final String? body;

  /// 문자열이 아닌 본문(예: 비동기로 채워지는 문구). [body] 와 함께 주면 이쪽이 이긴다.
  final Widget? content;

  /// 버튼 영역(오른쪽 정렬) — 옛 방식. 새 화면은 [actions] 를 쓴다.
  final Widget? footer;

  /// 세로로 쌓이는 단추들. 위에서 아래로 주 행동 → 위험 → 닫기 순서다(시안 `.m-btn-col`).
  /// 단추는 `block: true` 로 줘서 폭이 같게 한다. [footer] 와 함께 주면 이쪽이 이긴다.
  final List<Widget>? actions;

  final VoidCallback? onClose;
  final double width;

  /// 열릴 때 카드가 0.96 → 1 로 커지는 진행값(보통 라우트 애니메이션). 비우면 움직임 없음.
  final Animation<double>? entrance;

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
                style: BaraedaTypography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ));

    final actionColumn = actions == null || actions!.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(height: BaraedaSpacing.space2),
                  actions![i],
                ],
              ],
            ),
          );

    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
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
                        style: BaraedaTypography.title.copyWith(
                          height: 1.35,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  if (bodyWidget != null)
                    Padding(
                      padding: EdgeInsets.only(
                        top: title != null ? BaraedaSpacing.space3 : 0,
                      ),
                      child: bodyWidget,
                    ),
                ],
              ),
            ),
          ),
          if (actionColumn != null)
            actionColumn
          else if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Align(alignment: Alignment.centerRight, child: footer),
            ),
        ],
      ),
    );

    if (entrance != null) {
      card = ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: entrance!, curve: BaraedaCurve.easeOut),
        ),
        child: card,
      );
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
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                color: colors.overlayScrim,
                padding: const EdgeInsets.all(BaraedaSpacing.space6),
                alignment: Alignment.center,
                child: GestureDetector(
                  // 안쪽 카드 탭은 스크림 탭(닫기)으로 전파하지 않는다.
                  onTap: () {},
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: title,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      child: card,
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

/// [showBaraedaActionDialog] 의 선택지 하나. 누르면 [value] 로 닫힌다.
class BaraedaDialogAction<T> {
  const new({
    required this.label,
    required this.value,
    this.variant = BaraedaButtonVariant.primary,
  });

  final String label;
  final T value;
  final BaraedaButtonVariant variant;
}

/// 선택지를 세로로 쌓은 대화상자를 라우트로 띄운다 — 고른 [BaraedaDialogAction.value],
/// 바깥 탭·뒤로가기로 닫으면 `null`.
///
/// 열릴 때 200ms ease-out 로 나타난다. 운행 중 다크 구역에서 부르면 움직임 없이 바로 뜬다.
Future<T?> showBaraedaActionDialog<T>({
  required BuildContext context,
  required String title,
  required List<BaraedaDialogAction<T>> actions,
  String? body,
  Widget? content,
  bool dismissible = true,
}) {
  final motion = BaraedaOpenMotion.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: title,
    // 스크림은 BaraedaDialog 가 직접 그린다 — 라우트 배리어는 투명으로 둔다.
    barrierColor: Colors.transparent,
    transitionDuration: motion == BaraedaOpenMotion.none
        ? Duration.zero
        : BaraedaDuration.dialog,
    transitionBuilder: (context, animation, _, child) =>
        motion == BaraedaOpenMotion.none
        ? child
        : FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: BaraedaCurve.easeOut,
            ),
            child: child,
          ),
    pageBuilder: (dialogContext, animation, _) => BaraedaDriveZone.carry(
      context,
      Stack(
        children: [
          BaraedaDialog(
            title: title,
            body: body,
            content: content,
            onClose: dismissible
                ? () => Navigator.of(dialogContext).pop()
                : null,
            entrance: motion == BaraedaOpenMotion.full ? animation : null,
            actions: [
              for (final action in actions)
                BaraedaButton(
                  label: action.label,
                  variant: action.variant,
                  block: true,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(action.value),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 확인·취소 대화상자를 라우트로 띄운다 — 확인이면 `true`, 취소·바깥 탭·뒤로가기면 `false`.
///
/// Material `AlertDialog` 대신 쓰는 공용판이다. 단추는 세로로 쌓인다 —
/// 확인(위) · 취소(아래). [danger] 면 확인이 위험 면(빨강)이 되고 닫기가 그 아래에 온다
/// (시안: 위험 확인은 빨강 위 · 닫기 아래).
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
  bool danger = false,
}) async {
  final confirmed = await showBaraedaActionDialog<bool>(
    context: context,
    title: title,
    body: body,
    content: content,
    dismissible: dismissible,
    actions: [
      BaraedaDialogAction(
        label: confirmLabel,
        value: true,
        variant: danger
            ? BaraedaButtonVariant.danger
            : BaraedaButtonVariant.primary,
      ),
      BaraedaDialogAction(
        label: cancelLabel,
        value: false,
        variant: BaraedaButtonVariant.secondary,
      ),
    ],
  );
  return confirmed ?? false;
}
