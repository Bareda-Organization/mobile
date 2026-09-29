import 'package:flutter/material.dart';

/// 되돌리기 어려운 조작 앞의 확인 창 — 확인이면 `true`, 취소·창 밖 탭이면 `false`.
///
/// `confirmLogout` 과 같은 `AlertDialog` 모양이다. 호출부는 `false` 일 때 요청을 보내지 않는다.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = '취소',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
