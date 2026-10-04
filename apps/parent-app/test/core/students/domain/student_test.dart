import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/students/domain/student.dart';

/// §3.1 (`Ruling 824`) — 설정의 자녀 행 "초5 · 수학 A반" 이 쓰는 학년.
void main() {
  Map<String, dynamic> body({Object? grade = 'unset'}) => {
    'student_id': 's-1',
    'name': '이하준',
    'class_name': '수학 A반',
    'linked_at': '2026-09-28T00:00:00Z',
    if (grade != 'unset') 'grade': grade,
  };

  test('grade 를 읽는다', () {
    expect(Student.fromJson(body(grade: '초5')).grade, '초5');
  });

  test('grade 가 없거나 null 이면 null 이다(서버가 아직 안 줄 때 줄을 숨긴다)', () {
    expect(Student.fromJson(body()).grade, isNull);
    expect(Student.fromJson(body(grade: null)).grade, isNull);
  });
}
