import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/domain/student_repository.dart';

/// [StudentRepository] 의 `data` 계층 구현 — `auth_repository_impl.dart`
/// 와 같은 `_guard` 패턴(`DioException` → [Failure]).
class StudentRepositoryImpl implements StudentRepository {
  const new({required this._studentApi});

  final StudentApi _studentApi;

  @override
  Future<List<Student>> getMyStudents() => _guard(_studentApi.getMyStudents);

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계 — dart:core 예외 체계를
      // 흉내 내지 않는다). 이 지점의 `only_throw_errors` 는 예외로 둔다.
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
