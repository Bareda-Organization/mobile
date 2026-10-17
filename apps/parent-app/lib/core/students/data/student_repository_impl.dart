import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/domain/student_repository.dart';

/// [StudentRepository] 의 `data` 계층 구현 — `auth_repository_impl.dart`
/// 와 같은 `_guard` 패턴(`DioException` → [Failure]).
class StudentRepositoryImpl implements StudentRepository {
  const new({required this._studentApi});

  final StudentApi _studentApi;

  @override
  Future<List<Student>> getMyStudents() => guardDio(_studentApi.getMyStudents);
}
