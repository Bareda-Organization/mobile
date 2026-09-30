import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/auth/user_role.dart';

/// 로그인 결과로 채워지는 현재 역할. `null` 은 로그인 전.
/// 값을 채우는 곳은 `features/auth` — 로그인 성공 응답의 `role` 필드를 옮긴다.
final StateProvider<UserRole?> currentUserRoleProvider =
    StateProvider<UserRole?>((ref) => null);

/// 로그인·`/me` 응답의 학원 대표 연락처 — 통신 두절로 비상 신고가 못 나갔을 때 학원에 전화를 거는 번호다
/// (R46-MGR). 학원이 등록하지 않았으면 `null`. 로그아웃하면 비운다.
final StateProvider<String?> academyContactProvider = StateProvider<String?>(
  (ref) => null,
);

/// 화면이 실제로 읽는 것 — 역할이 아니라 **권한**.
/// 화면은 `ref.watch(roleCapabilitiesProvider)?.canDecideBoardingStatus` 처럼
/// 쓰고 `currentUserRoleProvider` 를 직접 보지 않는다(§1.1 "판정은 한 곳에서").
final Provider<RoleCapabilities?> roleCapabilitiesProvider =
    Provider<RoleCapabilities?>((ref) {
      final role = ref.watch(currentUserRoleProvider);
      return role == null ? null : RoleCapabilities.of(role);
    });
