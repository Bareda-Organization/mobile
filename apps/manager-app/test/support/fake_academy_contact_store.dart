import 'package:manager_app/core/auth/academy_contact_store.dart';

/// [AcademyContactStore] 의 메모리 대역 — 시험에는 `flutter_secure_storage` 플랫폼 채널이 없다.
class FakeAcademyContactStore implements AcademyContactStore {
  new([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> save(String? contact) async {
    final value = contact?.trim();
    if (value == null || value.isEmpty) return;
    _value = value;
  }
}
