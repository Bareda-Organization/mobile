import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// 마지막으로 받은 **오늘 회차 목록의 요약**을 이 기기에 남겨 둔다(R52 H2).
///
/// 통신이 끊긴 채 앱을 새로 켜면 회차 목록을 못 받아 홈의 선택 회차가 비고,
/// 저장 명단(회차 id 로 찾는다)과 비상 신고(후보 회차)에 닿지 못한다. 이 요약이
/// 있으면 목록 조회가 닿지 못할 때 대신 읽혀 홈 · 명단 · 비상이 열린다.
/// 담는 값은 §4.1 항목(회차 id · 호차 · 방향 · 시각 · 상태 · 인원 수)뿐이고
/// 학생 · 보호자 정보는 없다. 로그아웃 · 세션 만료 · 인증 거절 때 지운다.
abstract interface class RunSummaryStore {
  Future<({DateTime savedAt, List<ManagerRun> runs})?> read();

  Future<void> save(DateTime savedAt, List<ManagerRun> runs);

  Future<void> clear();
}

/// 기본 구현 — `flutter_secure_storage` 에 JSON 한 덩어리로 둔다(회차는 하루 몇
/// 건이라 표를 따로 만들지 않는다).
class SecureRunSummaryStore implements RunSummaryStore {
  const new();

  static const _key = 'baraeda_manager_run_summary';
  static const _storage = FlutterSecureStorage();

  @override
  Future<({DateTime savedAt, List<ManagerRun> runs})?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value == null) return null;
      final json = jsonDecode(value) as Map<String, dynamic>;
      final items = (json['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ManagerRun.fromJson)
          .toList();
      return (savedAt: DateTime.parse(json['saved_at'] as String), runs: items);
    } on Object {
      // 읽지 못하거나 손상됐으면 "요약 없음" — 목록 조회 실패가 그대로 보인다.
      return null;
    }
  }

  @override
  Future<void> save(DateTime savedAt, List<ManagerRun> runs) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'saved_at': savedAt.toIso8601String(),
          'items': [for (final run in runs) run.toJson()],
        }),
      );
    } on Object {
      // 저장 실패는 목록 조회를 막지 않는다 — 부가 기능이다.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // 지우지 못해도 로그아웃은 계속된다 — 토큰이 없으면 이 값은 쓰이지 않는다.
    }
  }
}

/// 시험은 이 provider 를 메모리 대역으로 바꾼다(플랫폼 채널이 없다).
final Provider<RunSummaryStore> runSummaryStoreProvider =
    Provider<RunSummaryStore>((ref) => const SecureRunSummaryStore());
