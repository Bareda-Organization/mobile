import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';

/// §3.14 — 설정 화면 진입 시 초기 조회. 쓰기(PATCH) 성공 뒤에는 화면이
/// 서버 응답값을 직접 반영하고, 이 provider 는 화면을 새로 열 때만 다시
/// 부른다(`weeklyAddressProvider` 와 달리 무효화하지 않는다 — 필드 3개
/// 전부가 매번 함께 오가므로 화면이 이미 최신 값을 들고 있다).
final notificationSettingsProvider = FutureProvider<NotificationSettings>((
  ref,
) {
  // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
  ref.watch(currentUserRoleProvider);
  final repository = ref.watch(notificationSettingsRepositoryProvider);
  return repository.getNotificationSettings();
});

/// 설정 맨 위 계정 카드가 읽는 내 정보(§2.10) — 이름 · 소속 학원 · 로그인 아이디.
final myProfileProvider = FutureProvider<MeResponse>((ref) {
  // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
  ref.watch(currentUserRoleProvider);
  return ref.watch(authRepositoryProvider).me();
});
