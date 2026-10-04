import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

/// 내 이름·학원 이름 — 머리줄 부제와 내 정보 화면이 읽는다(`/me`). 역할이 바뀌면(로그인·로그아웃) 다시 받는다.
final meProvider = FutureProvider<MeResponse>((ref) {
  if (ref.watch(currentUserRoleProvider) == null) {
    throw StateError('로그인 전입니다');
  }
  return ref.watch(authRepositoryProvider).me();
});

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 머리줄 부제 — `10월 3일 (토) · 하늘수학 · 기사 박정훈`. 이름을 아직 못 받았으면 날짜만.
final managerHeaderSubtitleProvider = Provider<String>((ref) {
  final now = ref.watch(clockProvider).now().toLocal();
  final date = '${now.month}월 ${now.day}일 (${_weekdays[now.weekday - 1]})';
  final me = ref.watch(meProvider).value;
  if (me == null) return date;
  final roleLabel = switch (me.role) {
    AccountRole.driver => '기사',
    AccountRole.escort => '동승자',
    _ => '',
  };
  return [
    date,
    ?me.academy?.name,
    if (roleLabel.isNotEmpty) '$roleLabel ${me.name}' else me.name,
  ].join(' · ');
});
