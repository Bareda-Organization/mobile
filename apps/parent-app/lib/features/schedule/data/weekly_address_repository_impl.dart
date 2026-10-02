import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/features/schedule/data/weekly_address_api.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_repository.dart';

class WeeklyAddressRepositoryImpl implements WeeklyAddressRepository {
  const new({required this._weeklyAddressApi});

  final WeeklyAddressApi _weeklyAddressApi;

  @override
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) =>
      _guard(() => _weeklyAddressApi.getWeeklyAddress(studentId));

  @override
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) => _guard(
    () => _weeklyAddressApi.updateWeeklyAddress(studentId, entries),
  );

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
