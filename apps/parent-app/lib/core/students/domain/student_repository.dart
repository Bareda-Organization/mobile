import 'package:parent_app/core/students/domain/student.dart';

/// 화면이 보는 연결 자녀 계약 — `home`·`schedule` 공통(§3.1).
///
/// 메서드가 1개뿐이라 `one_member_abstracts` 가 걸리지만, 이 앱의 다른
/// repository(§3.2~§3.9)들과 같은 인터페이스+구현체 계층 구조를 유지하기
/// 위해 최상위 함수로 바꾸지 않는다(DI 조합근인 `di.dart` 의 `Provider`
/// 배선과도 일관된다).
// ignore: one_member_abstracts
abstract interface class StudentRepository {
  /// §3.1. 연결 자녀가 없으면 빈 리스트.
  Future<List<Student>> getMyStudents();
}
