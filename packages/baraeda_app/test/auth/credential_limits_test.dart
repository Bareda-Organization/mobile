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

  test('비밀번호는 8자 이상 — 7자는 이유를 돌려주고 8자와 빈 값은 통과', () {
    expect(passwordLengthError('a' * 7), '비밀번호는 8자 이상이어야 합니다');
    expect(passwordLengthError('가' * 7), '비밀번호는 8자 이상이어야 합니다');
    expect(passwordLengthError('a' * 8), isNull);
    expect(passwordLengthError('가' * 8), isNull);
    expect(passwordLengthError(''), isNull, reason: '빈 칸은 "채우지 않음" 이 따로 알린다');
  });

  test('너무 짧은 새 비밀번호의 이유는 한 함수가 돌려준다', () {
    const message = '비밀번호는 8자 이상이어야 합니다';

    expect(passwordTooShortError('a' * 7), message);
    expect(passwordTooShortError('a' * 8), isNull);
    expect(passwordTooShortError(''), isNull);
    expect(passwordLengthError('a' * 7), passwordTooShortError('a' * 7));
  });
}
