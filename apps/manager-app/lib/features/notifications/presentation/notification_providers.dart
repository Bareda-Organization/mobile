import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

final StateProvider<NotificationFilter> notificationFilterProvider =
    StateProvider<NotificationFilter>((ref) {
      ref.watch(currentUserRoleProvider); // 계정이 바뀌면 [전체] 로
      return NotificationFilter.all;
    });

/// §3.12 — 알림 목록(공통 동작은 `baraeda_app` 의 [NotificationFeedNotifierBase]).
final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeed>(
      NotificationFeedNotifier.new,
    );

/// 이 앱의 계정 · 걸러 보기 · 저장소 · 시계를 공통 알림 목록에 이어 준다.
class NotificationFeedNotifier extends NotificationFeedNotifierBase {
  @override
  void watchAccount() => ref.watch(currentUserRoleProvider);

  @override
  NotificationFilter watchFilter() => ref.watch(notificationFilterProvider);

  @override
  NotificationFilter readFilter() => ref.read(notificationFilterProvider);

  @override
  NotificationRepository get repository =>
      ref.read(notificationRepositoryProvider);

  @override
  DateTime now() => ref.read(clockProvider).now();
}
