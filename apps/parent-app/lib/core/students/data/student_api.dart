import 'package:dio/dio.dart';
import 'package:parent_app/core/students/domain/student.dart';

/// API_SPEC §3.1 — `ApiClient.dio`(인터셉터 부착)를 그대로 받는다.
/// `baraeda_core` 는 건드리지 않는다(이 앱만 쓰는 도메인이라 공유 패키지에
/// 둘 이유가 없다).
class StudentApi {
  StudentApi({required this._dio});

  final Dio _dio;

  /// §3.1 — 응답은 `_EnvelopeInterceptor` 가 `data` 봉투를 벗긴 뒤라
  /// `items` 를 바로 읽는다.
  Future<List<Student>> getMyStudents() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/students');
    final items = response.data?['items'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>().map(Student.fromJson).toList();
  }
}
