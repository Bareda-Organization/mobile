import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';

/// 이 기기가 실제로 푸시를 받을 수 있는가 — 토큰이 있고 자리표시가 아닐 때만 `true`.
///
/// Firebase 를 붙이기 전에는 토큰 공급자가 기기별 자리표시 값을 주고(`Ruling 510`), 서버는 그 값을 FCM 에 보냈다가
/// 거부당한다. 그 기기에 "푸시로도 알려 드려요" 라고 약속하지 않으려고 화면이 이 값을 본다(M-P3, `UF-X-09` ④).
// `FutureProvider.autoDispose` 의 반환형은 `flutter_riverpod` 가 공개하지 않는
// 내부 타입이라 명시할 수 없다.
// ignore: specify_nonobvious_property_types
final pushReceivableProvider = FutureProvider.autoDispose<bool>((ref) async {
  final token = await ref.watch(pushTokenSourceProvider).currentToken();
  return token != null && !PlaceholderPushTokenSource.isPlaceholder(token);
});
