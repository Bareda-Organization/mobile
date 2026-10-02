import 'package:dio/dio.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';

/// API_SPEC §3.7.
class WeeklyAddressApi {
  new({required this._dio});

  final Dio _dio;

  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/students/$studentId/weekly-address',
    );
    return _parseEntries(response.data);
  }

  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/students/$studentId/weekly-address',
      data: {'entries': entries.map((entry) => entry.toJson()).toList()},
    );
    return _parseEntries(response.data);
  }

  List<WeeklyAddressEntry> _parseEntries(Map<String, dynamic>? data) {
    final entries = data?['entries'] as List<dynamic>? ?? [];
    return entries
        .cast<Map<String, dynamic>>()
        .map(WeeklyAddressEntry.fromJson)
        .toList();
  }
}
