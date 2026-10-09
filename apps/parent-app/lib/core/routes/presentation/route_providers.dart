import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';

/// 어느 학생의 어느 회차 노선인가 — `runId` 가 `null` 이면 서버 기본값
/// (당일 다음 회차).
typedef RouteRequest = ({String studentId, String? runId});

/// API_SPEC §3.10 — 지도(홈 미리보기 · 실시간 위치)와 노선 자세히 화면이 쓴다. 화면을 나가면 버린다(F05-06 —
/// 확정·③구간 제외가 반영되도록 들어올 때마다 새로 받는다).
///
/// 이미 끝난 회차의 종료 화면이 "지나온 구간"을 그리려면 기본값(다음 회차)이 아니라 그 회차의 노선이어야 하고
/// (`Ruling 831`), 지도에서 넘어간 노선 자세히도 같은 회차를 봐야 한다(M-P2).
/// `runId` 가 `null` 이면 서버 기본값이다.
// `FutureProvider.family` 의 반환형은 `flutter_riverpod` 가 공개하지 않는 내부 타입이라 명시할 수 없다.
// ignore: specify_nonobvious_property_types
final routeForRunProvider = FutureProvider.autoDispose
    .family<RouteDetail, RouteRequest>((ref, request) {
      // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
      ref.watch(currentUserRoleProvider);
      return ref
          .watch(routeRepositoryProvider)
          .getRoute(request.studentId, runId: request.runId);
    });
