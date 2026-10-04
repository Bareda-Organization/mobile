import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 마지막으로 알게 된 학원 문의처 — 차단된 계정은 로그인이 실패해 토큰이 없어 소속 학원을 모른다
/// (`Ruling 825`). 그래서 승인 대기 화면이 받은 `academy_contact` 를 기기에 남겨 두고 차단 화면이 쓴다.
///
/// 저장 위치는 이미 쓰는 기기 보안 저장소다(새 의존성 없음). 읽고 쓰기가 실패해도 화면은 "다니는 학원에 문의해 주세요"
/// 로 그려지면 되므로 예외는 삼킨다.
class AcademyContactStorage {
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'last_academy_contact';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> save(String contact) async {
    try {
      await _storage.write(key: _key, value: contact);
    } on PlatformException {
      // 기억하지 못해도 이번 화면은 그려진다.
    } on MissingPluginException {
      // 위젯 시험처럼 저장소 플러그인이 없는 환경.
    }
  }
}

/// 기기에 남긴 문의처 저장소 — 시험이 메모리 대역으로 바꾼다.
final academyContactStorageProvider = Provider<AcademyContactStorage>(
  (ref) => AcademyContactStorage(),
);

/// 차단 화면이 읽는 마지막 학원 문의처. 저장된 것이 없으면 `null`.
final FutureProvider<String?> savedAcademyContactProvider =
    FutureProvider.autoDispose<String?>(
      (ref) => ref.watch(academyContactStorageProvider).read(),
    );

/// 문의처 글자(`academy_contact` 는 자유 글자다)에서 전화번호 모양만 뽑는다 — 없으면 `null`.
/// 번호 모양이 없으면 전화 단추를 그리지 않는다(`Ruling 827`).
String? phoneNumberOf(String? contact) {
  if (contact == null) return null;
  final match = RegExp(
    r'(?:0\d{1,2}|1\d{3})-\d{3,4}-\d{4}|1\d{3}-\d{4}|0\d{9,10}',
  ).firstMatch(contact);
  return match?.group(0);
}
