import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 학부모가 마지막으로 고른 자녀 — 앱을 다시 켜도 이어 간다(R46 B2 #13).
///
/// 저장 위치는 이미 쓰는 기기 보안 저장소다(새 의존성을 더하지 않는다). 값은 자녀 식별자 하나뿐이고,
/// 읽고 쓰기가 실패해도 화면은 첫 자녀로 그려지면 되므로 예외는 삼킨다.
class SelectedStudentStorage {
  new({FlutterSecureStorage? storage})
    : _slot = SecureSlot(
        'selected_student_id',
        storage: storage ?? const FlutterSecureStorage(),
      );

  final SecureSlot _slot;

  Future<String?> read() => _slot.read();

  // 기억하지 못해도 이번 실행의 선택은 메모리에 남는다.
  Future<void> save(String studentId) => _slot.write(studentId);
}
