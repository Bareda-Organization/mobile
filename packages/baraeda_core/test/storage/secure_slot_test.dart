import 'package:baraeda_core/storage/secure_slot.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 모든 호출에서 [error] 를 던지는 저장소 — 기기 저장소가 실패하는 상황을 만든다.
class _ThrowingStorage implements FlutterSecureStorage {
  const new(this.error);

  final Object error;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      // ignore: only_throw_errors, 시험이 던질 대상을 직접 고른다.
      throw error;
}

/// 기기 저장소가 던지는 오류(`PlatformException`)만 삼킨다 — 코드 결함(`StateError` 등)까지 삼키면
/// 원인이 사라진다.
void main() {
  final storageFailure = PlatformException(code: 'keystore');

  group('저장소 오류(PlatformException)', () {
    final slot = SecureSlot('k', storage: _ThrowingStorage(storageFailure));

    test('읽기는 null, 쓰기·지우기는 없던 일이다', () async {
      expect(await slot.read(), isNull);
      await slot.write('v');
      await slot.delete();
    });

    test('strict 로 읽거나 쓰면 그대로 던진다', () async {
      await expectLater(
        slot.read(strict: true),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        slot.write('v', strict: true),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('코드 결함(StateError)', () {
    final slot = SecureSlot('k', storage: _ThrowingStorage(StateError('bug')));

    test('읽기·쓰기·지우기 모두 삼키지 않고 던진다', () async {
      await expectLater(slot.read(), throwsStateError);
      await expectLater(slot.write('v'), throwsStateError);
      await expectLater(slot.delete(), throwsStateError);
    });
  });
}
