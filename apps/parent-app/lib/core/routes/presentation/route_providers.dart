import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';

/// API_SPEC §3.10 — `studentId` 로 키를 삼는다. 화면을 나가면 버린다(F05-06 — 확정·③구간 제외가
/// 반영되도록 들어올 때마다 새로 받는다). `date`·`runId` 는 항상
/// 생략해 서버 기본값(당일 다음 회차)에 맡긴다 — 이 화면 진입 동선에는
/// 특정 회차를 지정해야 할 요구가 아직 없다.
// `FutureProvider.family` 의 반환형 `FutureProviderFamily<...>` 는
// `flutter_riverpod` 가 공개 API 로 export 하지 않는 내부 타입이라
// 명시할 수 없다(`run_providers.dart` 와 같은 이유).
// ignore: specify_nonobvious_property_types
final routeDetailProvider = FutureProvider.autoDispose
    .family<RouteDetail, String>((ref, studentId) {
      // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
      ref.watch(currentUserRoleProvider);
      return ref.watch(routeRepositoryProvider).getRoute(studentId);
    });

/// 어느 학생의 어느 회차 노선인가 — `runId` 가 `null` 이면 서버 기본값
/// (당일 다음 회차).
typedef RouteRequest = ({String studentId, String? runId});

/// API_SPEC §3.10 을 **회차를 지정해** 읽는다 — 지도(홈 미리보기 · 실시간 위치)가 쓴다. 이미 끝난 회차의 종료 화면이
/// "지나온 구간"을 그리려면 기본값(다음 회차)이 아니라 그 회차의 노선이어야 한다(`Ruling 831`).
///
/// `routeDetailProvider` 는 노선 자세히 화면이 쓴다 — 거기는 지정이 필요 없어 그대로 둔다.
// 반환형을 명시할 수 없는 사정은 위 `routeDetailProvider` 와 같다.
// ignore: specify_nonobvious_property_types
final routeForRunProvider = FutureProvider.autoDispose
    .family<RouteDetail, RouteRequest>((ref, request) {
      // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
      ref.watch(currentUserRoleProvider);
      return ref
          .watch(routeRepositoryProvider)
          .getRoute(request.studentId, runId: request.runId);
    });
