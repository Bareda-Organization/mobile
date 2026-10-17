import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/features/schedule/data/weekly_address_api.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_repository.dart';

class WeeklyAddressRepositoryImpl implements WeeklyAddressRepository {
  const new({required this._weeklyAddressApi});

  final WeeklyAddressApi _weeklyAddressApi;

  @override
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) =>
      guardDio(() => _weeklyAddressApi.getWeeklyAddress(studentId));

  @override
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) =>
      guardDio(() => _weeklyAddressApi.updateWeeklyAddress(studentId, entries));
}
