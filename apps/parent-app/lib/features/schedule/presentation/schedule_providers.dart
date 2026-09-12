import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/schedule/domain/change_request.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';

/// §3.7 — 학생별 요일×방향 주소. 쓰기(PATCH) 성공 뒤에는 이 provider 를
/// 무효화해 서버가 돌려준 `verified`·`lat`·`lng` 를 다시 받는다(C-10).
// `FutureProvider.family` 의 반환형 `FutureProviderFamily<...>` 는
// `flutter_riverpod` 가 공개 API 로 export 하지 않는 내부 타입이라
// 명시할 수 없다(riverpod-3.4.3/lib/src/internals.dart 확인).
// ignore: specify_nonobvious_property_types
final weeklyAddressProvider =
    FutureProvider.family<List<WeeklyAddressEntry>, String>((ref, studentId) {
      final repository = ref.watch(weeklyAddressRepositoryProvider);
      return repository.getWeeklyAddress(studentId);
    });

/// §3.9 — 학생별 일일 변경 신청 이력 + 대기 건수(`pending_count`).
// ignore: specify_nonobvious_property_types
final changeRequestsProvider =
    FutureProvider.family<ChangeRequestPage, String>((ref, studentId) {
      final repository = ref.watch(changeRequestRepositoryProvider);
      return repository.getChangeRequests(studentId);
    });
