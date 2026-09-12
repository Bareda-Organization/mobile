import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';

// `changeRequestsProvider`(§3.9)는 `home`(처리 대기 건수 배지, P-06) 도
// 함께 쓰므로 `core/change_requests` 로 옮겼다 — `home_providers.dart` 가
// `core/runs`·`core/students` 를 재노출하는 것과 같은 이유다. `export` 로
// 그대로 다시 노출해 기존 import 경로(`schedule_providers.dart`)를 쓰는
// 위젯을 고치지 않아도 되게 한다.
export 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';

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
