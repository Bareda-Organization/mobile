import 'package:baraeda_core/auth/models/academy_ref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로그인·me 응답의 academy.contact 를 읽는다', () {
    final academy = AcademyRef.fromJson(const {
      'id': '7',
      'name': '바른학원',
      'contact': '02-555-0101',
    });

    expect(academy.contact, '02-555-0101');
  });

  test('contact 가 null 이거나 키가 없어도 읽힌다(학원이 연락처를 등록하지 않은 경우)', () {
    expect(
      AcademyRef.fromJson(const {'id': '7', 'name': '바른학원', 'contact': null})
          .contact,
      isNull,
    );
    expect(
      AcademyRef.fromJson(const {'id': '7', 'name': '바른학원'}).contact,
      isNull,
    );
  });
}
