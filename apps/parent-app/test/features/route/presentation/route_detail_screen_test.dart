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
Map<String, dynamic> _stopJson({
  required String stopId,
  required int seq,
  required String name,
}) => {
  'stop_id': stopId,
  'seq': seq,
  'name': name,
  'address': '$name 주소',
  'lat': 37.5 + seq * 0.001,
  'lng': 127.0 + seq * 0.001,
};

/// `RouteDetail.fromJson` 이 요구하는 필드를 전부 채운 기본 원본 JSON.
/// 각 시험은 이 값을 베이스로 `stops`·`driver`·부가 필드만 바꿔 쓴다.
Map<String, dynamic> _routeJson({
  required List<Map<String, dynamic>> stops,
  required String myStopId,
  Map<String, dynamic> driverExtra = const {},
  Map<String, dynamic> extraTopLevel = const {},
}) => {
  'run_id': 'r-1',
  'bus_no': '7',
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

  group('①표시 범위 — 서버가 창을 안 좁혀도 §3.10 범위만 그린다', () {
    testWidgets(
      '승차지 이전 정류장이 3개 이상 와도 화면은 이전 2개 · 승차지까지 '
      '3개만 그린다(개인정보 노출 방지)',
      (tester) async {
        // 승차지(정류장5) 이전에 5개(정류장0~4)를 둬 서버 계약(최대
        // 2개 이전)을 일부러 어긴 원본을 만든다.
        final stops = List.generate(
          6,
          (i) => _stopJson(stopId: 's-stop-$i', seq: i, name: '정류장$i'),
        );
        final route = RouteDetail.fromJson(
          _routeJson(stops: stops, myStopId: 's-stop-5'),
        );

        await pumpScreen(tester, response: route);

        // §3.10 창 = 승차지(5) 이전 2개(3·4) + 승차지(5) = {3,4,5}.
        expect(find.text('정류장3'), findsOneWidget);
        expect(find.text('정류장4'), findsOneWidget);
        expect(find.text('정류장5'), findsOneWidget);
        // 창 밖(0·1·2)은 서버가 실수로 보냈어도 화면에 없어야 한다.
        expect(find.text('정류장0'), findsNothing);
        expect(find.text('정류장1'), findsNothing);
        expect(find.text('정류장2'), findsNothing);
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
      // 화면에 원래 뜨는 숫자(호차 "7"·시각 "08:00")와 안 겹치도록
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
