import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/route/domain/route_detail.dart';
import 'package:parent_app/features/route/domain/route_repository.dart';
import 'package:parent_app/features/route/presentation/route_detail_screen.dart';

/// `routeRepositoryProvider` 대신 넣는 가짜 — **실제 서버 응답이 아니라
/// 이 시험이 손으로 만든 원본 JSON**을 그대로 돌려준다.
///
/// **판단 근거 — 왜 진짜 서버로 확인하지 않는가**: 실 서버
/// (`StudentRouteQueryService.java:178`)는 이미 창을 좁혀 보내므로, 그
/// 서버를 시험 대상으로 삼으면 "서버가 옳게 자른다" 만 검증되고 "서버
/// 계약이 깨지거나 다른 소비자가 안 좁힌 응답을 줘도 화면이 버티는가"
/// 는 확인할 수 없다(팀 리드 지시). 그래서 창을 넘는 목록·`eta`·
/// `student_count`·기사 `phone` 을 **일부러 포함한** 원본 JSON을
/// `RouteDetail.fromJson` 에 직접 먹여 그 결과를 돌려준다.
class _FakeRouteRepository implements RouteRepository {
  _FakeRouteRepository(this.response);

  final RouteDetail response;

  @override
  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  }) async => response;
}

/// 정차 1개의 원본 JSON — 모든 필드를 채운다(`RouteStop.fromJson` 이
/// 요구하는 대로).
///
/// `stopId` 가 `null` 이면 Ruling 288 이 합성하는 학원 항목처럼
/// `stop_id: null` 로 보낸다. `address`/`lat`/`lng` 를 안 주면 기본값을
/// 채우고, 명시적으로 넘기면(학원 항목처럼 `null` 포함) 그대로 쓴다.
Map<String, dynamic> _stopJson({
  required int seq,
  required String name,
  String? stopId,
  Object? address = _unset,
  Object? lat = _unset,
  Object? lng = _unset,
}) => {
  'stop_id': stopId,
  'seq': seq,
  'name': name,
  'address': identical(address, _unset) ? '$name 주소' : address,
  'lat': identical(lat, _unset) ? 37.5 + seq * 0.001 : lat,
  'lng': identical(lng, _unset) ? 127.0 + seq * 0.001 : lng,
};

/// `_stopJson` 의 선택 인자가 "안 줬다" 와 "명시적으로 null 을 줬다" 를
/// 가르기 위한 표식.
const Object _unset = Object();

/// `RouteDetail.fromJson` 이 요구하는 필드를 전부 채운 기본 원본 JSON.
/// 각 시험은 이 값을 베이스로 `stops`·`driver`·부가 필드만 바꿔 쓴다.
Map<String, dynamic> _routeJson({
  required List<Map<String, dynamic>> stops,
  required String myStopId,
  Map<String, dynamic> driverExtra = const {},
  Map<String, dynamic> extraTopLevel = const {},
}) => {
  'run_id': 'r-1',
  // ⚠ 서버가 주는 값은 호차 이름 그 자체다(시드 '1호차'·'2호차' · `ERD varchar(20)`).
  // 맨 숫자 '7' 로 두면 화면이 "호차" 를 덧붙여도 시험이 못 잡는다 — "7호차호차" 가 그렇게 살아남았다.
  'bus_no': '7호차',
  'depart_time': '2026-09-14T08:00:00Z',
  'confirmed': true,
  'driver': {'name': '기사김', ...driverExtra},
  'escort': {'name': '동승자박', 'phone': '010-1111-2222'},
  'my_stop_id': myStopId,
  'stops': stops,
  ...extraTopLevel,
};

void main() {
  final student = Student(
    studentId: 's-1',
    name: '홍길동',
    linkedAt: DateTime(2026),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required RouteDetail response,
  }) async {
    // stops 목록이 창(3) + 학원 1개로 늘어나 기본 뷰포트를 넘긴다 —
    // ListView 는 화면 밖 항목을 늦게(스크롤 시점에) 그리므로, 뷰포트를
    // 넉넉히 키워 모든 타일이 즉시 그려지게 한다(스크롤 없이 검증).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.parent),
          ),
          myStudentsProvider.overrideWith((ref) async => [student]),
          routeRepositoryProvider.overrideWithValue(
            _FakeRouteRepository(response),
          ),
        ],
        child: const MaterialApp(home: RouteDetailScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('⓪호차 표기 — 서버 값을 그대로 쓴다', () {
    testWidgets('단위를 덧붙이지 않는다', (tester) async {
      final route = RouteDetail.fromJson(
        _routeJson(
          stops: [_stopJson(stopId: 's-stop-1', seq: 1, name: '정류장1')],
          myStopId: 's-stop-1',
        ),
      );
      await pumpScreen(tester, response: route);

      expect(find.textContaining('7호차 · '), findsOneWidget);
      expect(
        find.textContaining('7호차호차'),
        findsNothing,
        reason: '`bus_no` 가 이미 "7호차" 라 "호차" 를 붙이면 겹친다',
      );
    });
  });

  group('①표시 범위 — 서버가 보낸 stops 를 그대로 그린다(재절단 없음)', () {
    testWidgets(
      '서버가 4개를 보내면 화면도 4개를 그린다(목표 2 — visibleStops 삭제)',
      (tester) async {
        // Ruling 288 이후 서버는 창(최대 3개) + 합성 학원 항목 1개를
        // 함께 보낸다 — 총 4개. 클라이언트가 다시 자르면 이 중 일부가
        // 사라진다.
        final stops = [
          _stopJson(stopId: 's-stop-0', seq: 0, name: '정류장0'),
          _stopJson(stopId: 's-stop-1', seq: 1, name: '정류장1'),
          _stopJson(stopId: 's-stop-2', seq: 2, name: '정류장2'),
          // 학원 합성 항목 — stop_id 없음(API_SPEC §1.13 선례).
          _stopJson(seq: 3, name: '바래다학원 A'),
        ];
        final route = RouteDetail.fromJson(
          _routeJson(stops: stops, myStopId: 's-stop-2'),
        );

        await pumpScreen(tester, response: route);

        expect(find.text('정류장0'), findsOneWidget);
        expect(find.text('정류장1'), findsOneWidget);
        expect(find.text('정류장2'), findsOneWidget);
        expect(find.text('바래다학원 A'), findsOneWidget);
      },
    );

    testWidgets(
      '학원 합성 항목처럼 address 가 null 이어도 화면이 깨지지 않는다 '
      '(academy.address nullable)',
      (tester) async {
        final stops = [
          _stopJson(stopId: 's-stop-0', seq: 0, name: '정류장0'),
          _stopJson(
            seq: 1,
            name: '바래다학원 A',
            address: null,
            lat: null,
            lng: null,
          ),
        ];
        final route = RouteDetail.fromJson(
          _routeJson(stops: stops, myStopId: 's-stop-0'),
        );

        await pumpScreen(tester, response: route);

        expect(find.text('바래다학원 A'), findsOneWidget);
        // address 가 null 인 항목은 주소 줄 자체가 없어야 한다(널 텍스트
        // 렌더 방지) — 정류장0 의 주소만 보인다.
        expect(find.text('정류장0 주소'), findsOneWidget);
      },
    );
  });

  group('②eta·student_count — 응답에 있어도 화면에 없다', () {
    testWidgets('원본 JSON에 eta·student_count 가 있어도 그 값이 안 보인다', (
      tester,
    ) async {
      final stops = [
        _stopJson(stopId: 's-A', seq: 0, name: '정류장A'),
        _stopJson(stopId: 's-B', seq: 1, name: '정류장B')
          ..addAll({'eta': 'ETA_마커_07시55분', 'student_count': 4}),
      ];
      final route = RouteDetail.fromJson(
        _routeJson(
          stops: stops,
          myStopId: 's-B',
          // 정차별 필드뿐 아니라 응답 최상위에도 같이 심어 둔다 — 두
          // 자리 다 C-08 이 부재라고 규정한 값이다.
          extraTopLevel: const {
            'eta': 'ETA_마커_07시55분',
            'student_count': 4,
          },
        ),
      );

      await pumpScreen(tester, response: route);

      expect(find.textContaining('ETA_마커'), findsNothing);
      // 화면에 원래 뜨는 숫자(호차 "7호차"·시각 "08:00")와 안 겹치도록
      // student_count 는 마커 문자열로 대조한다.
      expect(find.text('4명'), findsNothing);
    });
  });

  group('③기사 연락처 — 응답에 있어도 연락 버튼은 동승자 것뿐이다', () {
    testWidgets('driver.phone 이 원본 JSON에 있어도 "전화하기" 버튼은 1개(동승자)뿐이다', (
      tester,
    ) async {
      final stops = [_stopJson(stopId: 's-A', seq: 0, name: '정류장A')];
      final route = RouteDetail.fromJson(
        _routeJson(
          stops: stops,
          myStopId: 's-A',
          driverExtra: const {'phone': '010-9999-8888'},
        ),
      );

      await pumpScreen(tester, response: route);

      expect(find.text('전화하기'), findsOneWidget);
    });
  });
}
