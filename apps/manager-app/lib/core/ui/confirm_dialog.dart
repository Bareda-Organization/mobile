import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';

/// 되돌릴 수 없는 조작 앞의 확인 창(R32) — 확인하면 `true`, 취소하거나 창 밖을 눌러 닫으면
/// `false`. 호출부는 `true` 일 때만 요청을 보낸다.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? body,
  String cancelLabel = '취소',
}) => showBaraedaConfirmDialog(
  context: context,
  title: title,
  body: body,
  confirmLabel: confirmLabel,
  cancelLabel: cancelLabel,
);
