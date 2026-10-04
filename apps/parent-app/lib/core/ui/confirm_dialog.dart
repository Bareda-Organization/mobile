import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';

/// 되돌리기 어려운 조작 앞의 확인 창 — 확인이면 `true`, 취소·창 밖 탭이면 `false`.
///
/// 호출부는 `false` 일 때 요청을 보내지 않는다. [danger] 면 확인이 위험색(빨강)이 되고 닫기가 그 아래에 온다 —
/// 되돌릴 수 없거나 바로 반영되는 동작에만 쓴다(요청만 보내는 단추는 위험색이 아니다).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = '취소',
  bool danger = false,
}) => showBaraedaConfirmDialog(
  context: context,
  title: title,
  body: body,
  confirmLabel: confirmLabel,
  cancelLabel: cancelLabel,
  danger: danger,
);
