import 'package:baraeda_app/baraeda_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('비밀번호는 UTF-8 72바이트까지 — 한글은 24자', () {
    expect(passwordLengthError('a' * 72), isNull);
    expect(passwordLengthError('a' * 73), isNotNull);
    expect(passwordLengthError('가' * 24), isNull);
    expect(passwordLengthError('가' * 25), isNotNull);
  });

  test('아이디는 앞뒤 공백을 뺀 50자까지', () {
    expect(loginIdLengthError(' ${'a' * 50} '), isNull);
    expect(loginIdLengthError('a' * 51), isNotNull);
  });
}
