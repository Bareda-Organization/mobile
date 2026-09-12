import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';

/// `DioException` → `Failure` 변환을 반복하지 않으려고 뺀 공용 함수
/// (`AuthRepositoryImpl._guard` 와 같은 패턴 — 이번 라운드에 새로 생기는
/// repository 5개가 전부 이 변환만 반복하므로 여기 하나로 모은다).
/// `presentation` 은 이 함수를 거친 [Failure] 만 본다(CONVENTIONS_FLUTTER.md §6).
Future<T> guardDio<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (exception) {
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고).
    // ignore: only_throw_errors
    throw mapDioExceptionToFailure(exception);
  }
}
