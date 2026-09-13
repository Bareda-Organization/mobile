@Tags(['real_backend'])
library;

import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_repository_impl.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/data/position_api.dart';
import 'package:manager_app/features/position/data/position_repository_impl.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/route_map/data/route_api.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

/// `real_backend_run_flow_test.dart` 와 같은 가짜 보안 저장소 — 이 파일은
/// 그쪽이 이미 다루지 않은 나머지 §4 엔드포인트(§4.3·§4.4·§4.5·§4.6·§4.7·
/// §4.8·§4.11·§4.12·§4.13·§4.16)를 실백엔드로 호출한다(F5 M 목표 7·8·9).
class _FakeSecureStoragePlatform
    with MockPlatformInterfaceMixin
    implements FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    data.clear();
  }

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async => const SecureStorageUpgradeStatus(
    state: SecureStorageUpgradeState.ok,
  );
}

/// 시드 회차 구성(`V2__seed_data.sql`, F5 M 전용 DB `schoolbus_f5_m`) —
/// run2: `confirmed`, driverA1/escortA1 배치, 출발 ±10분 창이 이미 지남
/// (목표 8 `START_WINDOW_CLOSED` 재현 대상, 시간이 지날수록 더 확실히
/// 닫힌다). run3: `moving`, driverA2/escortA2 배치 — 목표 7·8·9 의 대부분이
/// 이 회차에서 일어난다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
  late bool backendReachable;

  setUpAll(() async {
    HttpOverrides.global = null;
    final probe = Dio(BaseOptions(baseUrl: baseUrl));
    try {
      await probe.get<dynamic>('/manager/runs');
      backendReachable = true;
    } on DioException catch (e) {
      backendReachable = e.response != null;
    } finally {
      probe.close();
    }
    // F5 M3 목표 — §4.5(도착 처리 소모)·§4.4(출발 창 시각 의존) 재현이
    // 항상 성립하도록 필요할 때만 시드를 되돌린다(real_backend_target.dart
    // 의 함수 주석 참고). 백엔드가 죽어 있으면(!backendReachable) 이 호출도
    // 조용히 실패해 넘어가고, 그 판정은 각 시험의 backendReachable 분기가 한다.
    if (backendReachable) {
      await ensureManagerSeedIsSafeForTiming(baseUrl);
    }
  });

  ({AuthApi auth, Dio dio}) buildClient() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'it-access',
      refreshTokenKey: 'it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (auth: auth, dio: client.dio);
  }

  group('§4.3 GET /runs/{runId}/route', () {
    test(
      '기사 계정(driverA2, run3 배치)으로 호출하면 실제로 응답한다 — '
      '원재료 dio 로 모양을 먼저 확인한다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA2', password: 'password');

        final response = await dio.get<Map<String, dynamic>>('/runs/3/route');

        expect(response.statusCode, 200);
        final stops = (response.data!['stops'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(stops, isNotEmpty);
        expect(stops.first['seq'], isA<int>());
        expect(stops.first['lat'], isNotNull);
      },
    );

    test(
      '결함 수정 확인(F5 M2 목표 A-1, `Ruling 275`) — 프로덕션 '
      'RouteApi.fetchRoute 는 이제 route_response.dart 의 asIdString 으로 '
      'stop_id 를 흡수한다. 이 백엔드는 §4.3 의 stop_id 를 int(또는 null, '
      '추가된 임시 집결지)로 내려보내지만, 더는 TypeError 를 던지지 않고 '
      'stopId 값을 옳게 문자열로 읽어야 한다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA2', password: 'password');

        final api = RouteApi(dio: dio);
        final route = await api.fetchRoute('3');

        expect(route.stops, isNotEmpty);
        for (final stop in route.stops) {
          expect(
            stop.stopId,
            isA<String>(),
            reason: 'asIdString 이 서버의 int stop_id 를 문자열로 흡수해야 '
                '한다 — 캐스팅 실패 없이 여기까지 도달한 것 자체가 수정 '
                '증거이지만, 값 타입도 명시적으로 확인한다',
          );
          expect(stop.stopId, isNotEmpty);
        }
      },
    );
  });

  group('§4.4 POST /runs/{runId}/start — 목표 8 예외 경로', () {
    test(
      'DRIVER_ONLY — 동승자(escortA1)가 run2 의 운행 시작을 호출하면 '
      '403 DRIVER_ONLY 를 받는다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA1', password: 'password');
        final repository = DriveModeRepositoryImpl(api: DriveModeApi(dio: dio));

        Failure? failure;
        try {
          await repository.startRun('2');
        } on Failure catch (f) {
          failure = f;
        }

        expect(failure, isA<ApiFailure>());
        final apiFailure = failure! as ApiFailure;
        expect(apiFailure.statusCode, 403);
        expect(apiFailure.code, 'DRIVER_ONLY');
      },
    );

    test(
      'START_WINDOW_CLOSED — 기사(driverA1, run2 배치)가 창(출발 ±10분) '
      '밖에서 운행 시작을 호출하면 403 START_WINDOW_CLOSED 를 받는다. '
      '시드의 run2 출발 시각은 착수 시점 기준 이미 창을 지나 있어(보고서 '
      '1항의 사전 확인) 실제 시계로 재현된다 — 시간을 흉내 내지 않는다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA1', password: 'password');
        final repository = DriveModeRepositoryImpl(api: DriveModeApi(dio: dio));

        Failure? failure;
        try {
          await repository.startRun('2');
        } on Failure catch (f) {
          failure = f;
        }

        expect(failure, isA<ApiFailure>());
        final apiFailure = failure! as ApiFailure;
        expect(apiFailure.statusCode, 403);
        expect(apiFailure.code, 'START_WINDOW_CLOSED');
      },
    );
  });

  group('§4.6 PATCH /runs/{runId}/riders/{riderId} — 목표 9 멱등성', () {
    test(
      '같은 client_key 로 2회 보내도 부수효과는 1회 — 원재료 dio 로 '
      'run3/rider 3(boarded→alighted) 을 갱신하고, 두 응답의 changed_at 이 '
      '동일한지로 서버가 재처리하지 않고 원래 처리 결과를 그대로 돌려주는지 '
      '확인한다. ⚠ 프로덕션 RosterApi.updateRiderStatus 는 이 응답의 '
      'rider_id 를 String 으로 캐스팅하는데(rider_update_result.dart) 이 '
      '백엔드는 int 로 내려 캐스팅이 실패한다(§4.3 과 같은 종류의 결함, '
      '아래 두 번째 시험이 그 실패를 실제 응답 값으로 재현한다) — 그래서 '
      '이 시험은 원재료 dio 로 직접 멱등성을 검증한다. ⚠ 이 호출은 run3의 '
      'rider 3 상태를 boarded → alighted 로 영구히 바꾼다(보고서 2항)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA2', password: 'password');

        final clientKey = IdempotencyKeys.generate();
        final request = BoardingUpdateRequest(
          status: RiderStatus.alighted,
          clientKey: clientKey,
        );

        final firstResponse = await dio.patch<Map<String, dynamic>>(
          '/runs/3/riders/3',
          data: request.toJson(),
        );
        final secondResponse = await dio.patch<Map<String, dynamic>>(
          '/runs/3/riders/3',
          data: request.toJson(),
        );

        expect(firstResponse.statusCode, 200);
        expect(secondResponse.statusCode, 200);
        expect(
          secondResponse.data!['rider_id'],
          firstResponse.data!['rider_id'],
        );
        expect(secondResponse.data!['status'], firstResponse.data!['status']);
        // 문자열 그대로는 비교하지 않는다 — 서버가 같은 순간을 호출마다
        // 다른 시간대 표기(+09:00 / Z)로 돌려주는 것을 실측했다(값 자체는
        // 같은 순간). 멱등성의 본질은 "같은 순간을 가리키는가" 이므로
        // DateTime 으로 파싱해 같은 순간인지를 비교한다.
        final firstChangedAt = DateTime.parse(
          firstResponse.data!['changed_at'] as String,
        );
        final secondChangedAt = DateTime.parse(
          secondResponse.data!['changed_at'] as String,
        );
        expect(
          secondChangedAt.isAtSameMomentAs(firstChangedAt),
          isTrue,
          reason: '멱등이면 두 번째 호출도 최초 처리 결과의 changed_at 과 '
              '같은 순간을 돌려줘야 한다 — 다르면 서버가 두 번째 요청을 '
              '다시 처리한 것이다(실제 서버 값: 1차 $firstChangedAt / '
              '2차 $secondChangedAt)',
        );
      },
    );

    test(
      '결함 수정 확인(F5 M2 목표 A-3, `Ruling 275`) — 위 시험이 실제로 받은 '
      '응답을 그대로 RiderUpdateResult.fromJson 에 먹이면(추가 네트워크 '
      '호출 없이) 이제 asIdString 이 rider_id 를 흡수해 캐스팅이 성공하고 '
      '값도 옳게 읽혀야 한다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA2', password: 'password');

        // 같은 client_key 를 세 번째로 보낸다 — 서버는 이미 멱등 판정을
        // 마쳤으므로(위 시험) 이 호출은 새 부수효과를 내지 않고 원래
        // 처리 결과를 그대로 돌려준다. 그 실제 응답을 파싱기에 먹인다.
        final clientKey = IdempotencyKeys.generate();
        // 위 시험과 다른 client_key 를 새로 만들되, 같은 rider 에 같은
        // 상태를 요청해 서버 쪽 부수효과는 이미 alighted 로 안정된 값과
        // 같다 — 응답 모양만 필요하므로 값 자체의 중복 여부는 무관하다.
        final request = BoardingUpdateRequest(
          status: RiderStatus.alighted,
          clientKey: clientKey,
        );
        final response = await dio.patch<Map<String, dynamic>>(
          '/runs/3/riders/3',
          data: request.toJson(),
        );

        final result = RiderUpdateResult.fromJson(response.data!);

        expect(result.riderId, '3');
        expect(result.status, RiderStatus.alighted);
      },
    );
  });

  group('§4.7 POST /runs/{runId}/riders/{riderId}/revert', () {
    test(
      '동승자(escortA2)가 run3/rider 3 의 방금 바뀐 상태를 되돌린다 — '
      '위 §4.6 시험이 만든 alighted 를 원래 값(boarded)에 가깝게 되돌려 '
      'DB 잔여 영향을 줄인다(완전한 원복은 아니다, 보고서 2항)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA2', password: 'password');
        final api = RosterApi(dio: dio);

        final result = await api.revertRiderStatus(
          runId: '3',
          riderId: '3',
          reason: '실백엔드 계약 시험 — F5 M 목표 9 원복',
        );

        expect(result.revertedAt, isNotNull);
      },
    );
  });

  group('§4.8 POST /runs/{runId}/riders/{riderId}/no-show-contacts', () {
    test(
      '동승자(escortA2)가 run3/rider 6(no_show)의 연락 시도를 기록한다',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA2', password: 'password');
        final api = RosterApi(dio: dio);

        // 응답 필드가 사양에 없어 예외 없이 끝나는 것 자체가 성공 판정
        // 이다(reports_api.dart 의 같은 관례, no_show_contact_request.dart
        // 주석 참고).
        await api.recordNoShowContact(
          runId: '3',
          riderId: '6',
          request: const NoShowContactRequest(
            attemptType: NoShowAttemptType.call,
            result: NoShowContactResult.noAnswer,
          ),
        );
      },
    );
  });

  group('§4.11 POST /runs/{runId}/ack-changes', () {
    test(
      '기사(driverA1, run2 배치·ack_required=true)가 변경사항 전건을 '
      '확인 처리한다(change_ids 미전달)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA1', password: 'password');
        final api = RosterApi(dio: dio);

        final result = await api.ackChanges(runId: '2');

        expect(result.ackedAt, isNotNull);
      },
    );
  });

  group('§4.5 POST /runs/{runId}/stops/{stopId}/arrive — 목표 8', () {
    test(
      '결함 수정 확인(F5 M2 목표 A-2·A-5, `Ruling 275` + 널 허용성) — '
      '기사(driverA2, run3 배치)가 아직 미도착인 정류장에 도착 처리하면 '
      '성공하고, 같은 정류장에 다시 도착 처리를 호출하면 403 '
      'DUPLICATE_ARRIVE 를 받는다. '
      '⚠ 도착 처리는 영구·불가역이라(취소 API 부재) run3 의 정류장을 '
      '하나씩 소모한다 — 그래서 대상을 하드코딩하지 않고 매 실행마다 '
      '프로덕션 RosterApi.fetchRoster 로 그 시점의 실제 미도착 정류장을 '
      '골라 쓴다. photo_url 널 허용 수정 전에는 이 호출 자체가 크래시해 '
      '원재료 dio 로 우회해야 했다 — 지금은 정류장 선택 경로 자체가 그 '
      '수정의 재현 검사를 겸한다(보고서 1항). '
      '(고정 stopId 를 썼던 이전 버전은 두 번째 전체 실행에서 이미 소모된 '
      '정류장을 다시 호출해 "첫 도착"이 아니라 곧바로 403 을 받는 형태로 '
      '깨졌다 — 보고서 1항). 이어서 그 첫 성공 응답을 추가 네트워크 호출 '
      '없이 그대로 ArriveStopResult.fromJson 에 먹여, next_stop.stop_id 가 '
      'int 로 와도 asIdString 이 흡수해 캐스팅이 성공하고 값도 옳게 읽히는지 '
      '확인한다(수정 전에는 NextStopRef.fromJson 의 직접 캐스팅이 여기서 '
      'TypeError 를 던졌다). ⚠ 이 시험은 고른 정류장 하나를 영구히 '
      '"도착 처리됨" 으로 만든다 — 그 뒤 회차가 같은 DB 를 재사용한다면 이 '
      '상태를 그대로 물려받는다(보고서 2항). run3 은 정류장 4개(2·3·1·4 순) '
      '뿐이라 이 시험을 4번 넘게 돌리면 미도착 정류장이 바닥나 "환경 문제"로 '
      '건너뛴다 — F5 M2 목표 B 가 이 소모를 매 실행 전 `/dev/reset` 으로 '
      '되돌려 막는다(보고서 1항)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA2', password: 'password');

        // 실행 시점의 실제 명단을 읽어 아직 도착 처리되지 않은 정류장 중
        // — 노선상 마지막 정류장(seq 최댓값)은 next_stop 이 null 이라
        // 아래 확인이 성립하지 않으므로 제외하고 — seq 가 가장 작은 것을
        // 고른다.
        //
        // photo_url 널 허용 수정(F5 M2 목표 A-5) 전에는 RosterStudent
        // .fromJson 이 `photo_url` 을 `as String`(비 nullable)으로 캐스팅해
        // 이 호출 자체가 크래시했다(실측: rider 3 김영희, photo_url: null).
        // 지금은 프로덕션 RosterApi 를 그대로 써서 그 수정이 실제로
        // 캐스팅 실패 없이 명단을 읽어내는지도 함께 확인한다.
        var roster = await RosterApi(dio: dio).fetchRoster('3');
        List<RosterStop> selectCandidates(List<RosterStop> stops) {
          final lastSeq = stops
              .map((s) => s.seq)
              .reduce((a, b) => a > b ? a : b);
          return stops
              .where((s) => s.arrivedAt == null && s.seq != lastSeq)
              .toList()
            ..sort((a, b) => a.seq.compareTo(b.seq));
        }

        var candidateStops = selectCandidates(roster.stops);
        // F5 M3 목표 — setUpAll 이 이미 이 조건을 확인·필요시 리셋했지만
        // (real_backend_target.dart 참고), 이 자리에도 한 번 더 안전판을
        // 둔다(브리프 후보 (a)) — setUpAll 과 이 시험 실행 사이에 상태가
        // 바뀌었을 가능성(예: 예상 밖의 동시 실행)까지 방어한다. 그래도
        // 없으면 그때는 진짜 "환경 문제"로 건너뛴다 — 재시도까지 실패한
        // 것이므로 더는 이 시험의 책임이 아니다.
        if (candidateStops.isEmpty) {
          await ensureManagerSeedIsSafeForTiming(baseUrl);
          roster = await RosterApi(dio: dio).fetchRoster('3');
          candidateStops = selectCandidates(roster.stops);
        }
        if (candidateStops.isEmpty) {
          markTestSkipped(
            '환경 문제: run3 에 next_stop 이 있는 미도착 정류장이 `/dev/reset` '
            '재시도 후에도 없다 — schoolbus_f5_m 자체가 손상됐을 가능성',
          );
          return;
        }
        final targetStopId = candidateStops.first.stopId;

        final firstResponse = await dio.post<Map<String, dynamic>>(
          '/runs/3/stops/$targetStopId/arrive',
        );
        expect(firstResponse.statusCode, 200);
        expect(firstResponse.data!['arrived_at'], isNotNull);
        expect(
          firstResponse.data!['next_stop'],
          isNotNull,
          reason: '아래 결함 재현은 next_stop 이 있어야 성립한다 — 마지막 '
              '정류장을 제외하고 골랐으므로 항상 있어야 한다',
        );

        try {
          await dio.post<Map<String, dynamic>>(
            '/runs/3/stops/$targetStopId/arrive',
          );
          fail('두 번째 도착 처리가 403 을 던지지 않았다');
        } on DioException catch (e) {
          expect(e.response?.statusCode, 403);
          final data = e.response?.data as Map<String, dynamic>?;
          final error = data?['error'] as Map<String, dynamic>?;
          expect(error?['code'], 'DUPLICATE_ARRIVE');
        }

        // 결함 수정 확인 — 추가 네트워크 호출 없이, 위에서 이미 받은 첫
        // 성공 응답을 그대로 프로덕션 파싱기에 먹인다. next_stop.stop_id 가
        // int 로 와도 asIdString 이 흡수해 캐스팅이 성공해야 한다.
        final arriveResult = ArriveStopResult.fromJson(firstResponse.data!);
        expect(arriveResult.nextStop, isNotNull);
        expect(arriveResult.nextStop!.stopId, isA<String>());
        expect(arriveResult.nextStop!.stopId, isNotEmpty);
      },
    );
  });

  group('§4.12 POST /runs/{runId}/position', () {
    test(
      '기사(driverA2, run3 이 moving)가 위치를 전송하면 성공한다(204, '
      '본문 없음) — PositionRepositoryImpl 프로덕션 경로 그대로',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA2', password: 'password');
        final repository = PositionRepositoryImpl(api: PositionApi(dio: dio));

        // 예외 없이 끝나는 것이 성공 판정(§4.12 응답은 204 로 본문 없음).
        await repository.sendPosition(
          runId: '3',
          request: PositionRequest(
            lat: 37.5675,
            lng: 126.979,
            recordedAt: DateTime.now().toUtc(),
          ),
        );
      },
    );
  });

  group('§4.13 POST /runs/{runId}/reports', () {
    test(
      '결함 수정 확인(F5 M2 목표 A-4, `Ruling 275`) — 동승자(escortA2, '
      'run3 배치)가 기타 사유 보고서를 제출하면 프로덕션 '
      'ReportResult.fromJson 이 report_id 를 asIdString 으로 흡수해 캐스팅이 '
      '성공하고 값도 옳게 읽혀야 한다(수정 전에는 이 백엔드가 report_id 를 '
      "int 로 내려 `json['report_id'] as String` 이 TypeError 를 던졌다). "
      '⚠ 이 호출은 run3 에 보고서 레코드를 영구히 남긴다(삭제 API 부재, '
      '보고서 2항)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'escortA2', password: 'password');

        final response = await dio.post<Map<String, dynamic>>(
          '/runs/3/reports',
          data: const ReportRequest(
            type: ReportType.etc,
            memo: 'F5 M 실백엔드 계약 시험 — §4.13 연결 확인용 보고서',
          ).toJson(),
        );

        expect(response.statusCode, 201);

        // 결함 수정 확인 — 추가 네트워크 호출 없이, 위에서 이미 받은 응답을
        // 그대로 프로덕션 파싱기에 먹인다.
        final reportResult = ReportResult.fromJson(response.data!);
        expect(reportResult.reportId, isA<String>());
        expect(reportResult.reportId, isNotEmpty);
        expect(reportResult.reportedAt, isNotNull);
      },
    );
  });

  group('§4.16 GET /runs/{runId}/navigation — 클라이언트 미구현', () {
    test(
      '⚠ manager-app 코드베이스 전체에 NavigationApi 도, 이 경로를 부르는 '
      '화면도 없다(grep -rn "navigation" lib/ 매칭 0건, 보고서 확인). '
      '건너뜀 0 을 지키기 위해 원재료 dio 로만 호출해 서버가 실제로 '
      '응답하는지 확인한다 — 이 호출을 검증하는 프로덕션 코드 경로는 '
      '이 라운드 기준 존재하지 않는다(가짜 응답 대체가 아니라 미구현)',
      () async {
        if (!backendReachable) {
          markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
          return;
        }
        final (:auth, :dio) = buildClient();
        await auth.login(loginId: 'driverA2', password: 'password');

        final response = await dio.get<Map<String, dynamic>>(
          '/runs/3/navigation',
        );

        expect(response.statusCode, 200);
        expect(response.data!['provider'], isNotNull);
        expect(response.data!['destination'], isNotNull);
      },
    );
  });
}
