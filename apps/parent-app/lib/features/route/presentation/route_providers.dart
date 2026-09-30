import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/features/route/domain/route_detail.dart';

/// API_SPEC §3.10 — `studentId` 로 키를 삼는다. 화면을 나가면 버린다(F05-06 — 확정·③구간 제외가
/// 반영되도록 들어올 때마다 새로 받는다). `date`·`runId` 는 항상
/// 생략해 서버 기본값(당일 다음 회차)에 맡긴다 — 이 화면 진입 동선에는
/// 특정 회차를 지정해야 할 요구가 아직 없다.
// `FutureProvider.family` 의 반환형 `FutureProviderFamily<...>` 는
// `flutter_riverpod` 가 공개 API 로 export 하지 않는 내부 타입이라
// 명시할 수 없다(`run_providers.dart` 와 같은 이유).
// ignore: specify_nonobvious_property_types
final routeDetailProvider = FutureProvider.autoDispose
    .family<RouteDetail, String>((
      ref,
      studentId,
    ) {
      // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
      ref.watch(currentUserRoleProvider);
      return ref.watch(routeRepositoryProvider).getRoute(studentId);
    });
