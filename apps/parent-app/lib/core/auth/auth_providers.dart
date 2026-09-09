import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';

/// 로그인 결과로 채워지는 현재 역할. `null` 은 로그인 전.
/// 값을 채우는 곳은 `features/auth` — 로그인 성공 응답의 `role` 필드를 옮긴다.
final StateProvider<UserRole?> currentUserRoleProvider =
    StateProvider<UserRole?>((ref) => null);

/// 화면이 실제로 읽는 것 — 역할이 아니라 **권한**.
/// 화면은 `ref.watch(roleCapabilitiesProvider)?.canToggleAttendance` 처럼 쓰고
/// `currentUserRoleProvider` 를 직접 보지 않는다(§1.1 "판정은 한 곳에서").
final Provider<RoleCapabilities?> roleCapabilitiesProvider =
    Provider<RoleCapabilities?>((ref) {
      final role = ref.watch(currentUserRoleProvider);
      return role == null ? null : RoleCapabilities.of(role);
    });
