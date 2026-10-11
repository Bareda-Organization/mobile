import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 서버가 거절해 지워진 비상 신고의 요약 — 건수 · 마지막 시각 · 그때의 학원 전화번호(Ruling 886).
/// 학생 이름이 없는 정보라 계정을 정리해도 지우지 않는다.
class UnsentEmergency {
  const new({required this.count, required this.lastAt, this.contact});

  factory fromJson(Map<String, dynamic> json) => UnsentEmergency(
    count: json['count'] as int,
    lastAt: DateTime.parse(json['last_at'] as String),
    contact: json['contact'] as String?,
  );

  /// 전송되지 못한 비상 신고 건수.
  final int count;

  /// 가장 마지막으로 지워진 시각.
  final DateTime lastAt;

  /// 그때의 학원 전화번호 — 없으면 `null`.
  final String? contact;

  Map<String, dynamic> toJson() => {
    'count': count,
    'last_at': lastAt.toIso8601String(),
    'contact': contact,
  };
}

/// [UnsentEmergency] 를 이 기기에 남기고 사용자가 [확인] 할 때 지운다.
/// 로그아웃 · 세션 만료 · 앱 종료로는 지우지 않는다.
abstract interface class UnsentEmergencyStore {
  Future<UnsentEmergency?> read();

  Future<void> write(UnsentEmergency value);

  Future<void> clear();
}

/// 기본 구현 — `flutter_secure_storage`(Keychain · EncryptedSharedPreferences).
class SecureUnsentEmergencyStore implements UnsentEmergencyStore {
  const new();

  static const _key = 'baraeda_manager_unsent_emergency';
  static const _storage = FlutterSecureStorage();

  @override
  Future<UnsentEmergency?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return UnsentEmergency.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // 읽지 못하거나 모양이 틀리면 "남긴 안내 없음" 으로 본다.
      return null;
    }
  }

  @override
  Future<void> write(UnsentEmergency value) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(value.toJson()));
    } on Object {
      // 저장 실패여도 이번 실행 동안은 메모리 안내가 남는다.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // 지우지 못하면 다음 실행에 안내가 다시 보일 뿐이다.
    }
  }
}

/// 시험은 이 provider 를 메모리 대역으로 바꾼다(플랫폼 채널이 없다).
final Provider<UnsentEmergencyStore> unsentEmergencyStoreProvider =
    Provider<UnsentEmergencyStore>((ref) => const SecureUnsentEmergencyStore());
