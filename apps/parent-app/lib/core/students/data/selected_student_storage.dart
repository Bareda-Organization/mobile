import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 학부모가 마지막으로 고른 자녀 — 앱을 다시 켜도 이어 간다(R46 B2 #13).
///
/// 저장 위치는 이미 쓰는 기기 보안 저장소다(새 의존성을 더하지 않는다). 값은 자녀 식별자 하나뿐이고,
/// 읽고 쓰기가 실패해도 화면은 첫 자녀로 그려지면 되므로 예외는 삼킨다.
class SelectedStudentStorage {
  SelectedStudentStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'selected_student_id';

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

  Future<void> save(String studentId) async {
    try {
      await _storage.write(key: _key, value: studentId);
    } on PlatformException {
      // 기억하지 못해도 이번 실행의 선택은 메모리에 남는다.
    } on MissingPluginException {
      // 위젯 시험처럼 저장소 플러그인이 없는 환경.
    }
  }
}
