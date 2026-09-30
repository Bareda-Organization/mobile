import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

/// 테스트 전용 대역 — §4.11 ack-changes 호출 여부·인자만 기록하고, §4.7
/// 되돌리기(`revertRiderStatus`)·§4.6 승하차 갱신(`updateRiderStatus`)도
/// 성공·실패를 주입할 수 있다. 미탑승 연락 기록만 이 파일의 시험 대상이
/// 아니라 호출되면 실패하도록 둔다.
class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository({
    required this.roster,
    this.ackResult,
    this.ackFailure,
    this.revertFailure,
    this.updateOutcome,
    this.updateFailure,
  });

  final RosterResponse roster;
  final AckChangesResult? ackResult;
  final Failure? ackFailure;
  final Failure? revertFailure;

  /// §1.7 오프라인 큐 시험용 — [Sent]·[Queued] 중 어느 쪽을 돌려줄지.
  final SendOutcome<RiderUpdateResult>? updateOutcome;
  final Failure? updateFailure;
  String? lastAckRunId;

  /// 즉시 전송·재생이 같은 client_key 를 쓰는지 검증하는 시험이 읽는다.
  String? lastUpdateClientKey;

  /// M3 — 실패 시 명단이 **다시 조회됐는지**(재조회 1회) 확인하는 시험이 읽는다.
  int fetchRosterCallCount = 0;

  @override
  Future<RosterResponse> fetchRoster(String runId) async {
    fetchRosterCallCount++;
    return roster;
  }

  @override
  Future<AckChangesResult> ackChanges({required String runId}) async {
    lastAckRunId = runId;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고) — delay_screen_test.dart 와
    // 같은 패턴.
    // ignore: only_throw_errors
    if (ackFailure != null) throw ackFailure!;
    return ackResult!;
  }

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) async {
    lastUpdateClientKey = request.clientKey;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다(위 ackChanges
    // 주석과 같은 이유).
    // ignore: only_throw_errors
    if (updateFailure != null) throw updateFailure!;
    return updateOutcome!;
  }

  @override
  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) async {
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다(위 ackChanges
    // 주석과 같은 이유).
    // ignore: only_throw_errors
    if (revertFailure != null) throw revertFailure!;
    return RevertResult(
      status: RiderStatus.waiting,
      revertedAt: DateTime(2026, 9, 12, 9),
    );
  }

  @override
  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

/// 목표 9 검사용 대역 — `managerRunChannelProvider` 는 구체 클래스
/// `ManagerRunChannelController` 로 타입이 고정돼 있어(`overrideWith` 가
/// 정확히 그 타입만 받는다) 그 컨트롤러 자체를 가짜로 바꿔치기할 수
/// 없다(리버팟 3.4.3 `$FunctionalFamilyOverride` — 생성자가 여는 실제
/// WebSocket 연결도 그대로 남는다). 대신 그 생성자가 유일하게 주입받는
/// `TokenStorage.readAccessToken()` 을 영원히 끝나지 않는 대기로 만들어,
/// `_doConnect()` 의 `await` 지점에서 실행이 멈추게 한다 — `StompClient`
/// 생성·소켓 연결·재연결 타이머가 전부 그 이후 코드라 하나도 실행되지
/// 않는다. 결과는 `ManagerChannelStatus.connecting`(생성자가 그 값으로
/// 시작한다)이 고정되고, 실제 컨트롤러 코드를 그대로 쓰면서도 부수효과가
/// 없는 결정적 시험 상태를 얻는다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// §4.2 응답 — 정류장·탑승자별 `change` 는 초록 하이라이트·빨강 취소선
/// 표시(UF-D-02)에만 쓰인다. 배너 노출 근거는 더 이상 이 값이 아니라
/// [_managerRun] 의 `ackRequired`(§4.1) 다.
RosterResponse _roster({
  String? photoUrl = 'https://example/1.jpg',
  RiderChange? studentChange,
  StopChange? stopChange,
  RiderStatus studentStatus = RiderStatus.waiting,
}) {
  return RosterResponse(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    counts: const RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
    stops: [
      RosterStop(
        stopId: 'stop-1',
        seq: 1,
        name: 'A정류장',
        change: stopChange,
        students: [
          RosterStudent(
            riderId: 'r1',
            studentId: 's1',
            name: '김바래',
            photoUrl: photoUrl,
            guardianPhone: '010-2XXX-8814',
            canGoAlone: false,
            status: studentStatus,
            change: studentChange,
          ),
        ],
      ),
    ],
  );
}

/// §4.1 `GET /manager/runs` 항목 — `ackRequired` 가 §4.11 배너 노출의
/// 근거값(RUN-07).
ManagerRun _managerRun({required bool ackRequired}) {
  final now = DateTime(2026, 9, 12, 8);
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now,
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: RunStatus.confirmed,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 10)),
    startWindowTo: now.add(const Duration(minutes: 10)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: ackRequired,
  );
}

void main() {
  const runId = 'run-1';

  List<Override> overridesFor({
    required RosterResponse roster,
    required bool ackRequired,
    AckChangesResult? ackResult,
    Failure? ackFailure,
  }) {
    final fakeRepo = _FakeRosterRepository(
      roster: roster,
      ackResult: ackResult,
      ackFailure: ackFailure,
    );
    return [
      selectedRunIdProvider.overrideWith((ref) => runId),
      rosterRepositoryProvider.overrideWithValue(fakeRepo),
      todayRunsProvider.overrideWith(
        (ref) async => [_managerRun(ackRequired: ackRequired)],
      ),
    ];
  }

  // Ruling 377 — 사진이 상대 경로면 호스트에 붙이고 저장된 토큰을 헤더로 넘긴다.
  testWidgets('상대 경로 photo_url 은 호스트에 붙여 토큰 헤더와 함께 StudentRow 에 넘긴다', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        ...overridesFor(
          roster: _roster(photoUrl: '/api/v1/files/photos/a.jpg'),
          ackRequired: false,
        ),
        rosterPhotoHeadersProvider.overrideWith(
          (ref) async => {'Authorization': 'Bearer tok-1'},
        ),
      ]),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<StudentRow>(find.byType(StudentRow));
    expect(
      row.photoUrl,
      '${Uri.parse(ApiConstants.baseUrl).origin}/api/v1/files/photos/a.jpg',
    );
    expect(row.photoHeaders, {'Authorization': 'Bearer tok-1'});
  });

  testWidgets('ack_required 가 false 면 변경 확인 배너를 보여주지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(roster: _roster(), ackRequired: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('변경 목록 확인'), findsNothing);
  });

  testWidgets('ack_required 가 true 면 변경 확인 배너·버튼을 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(
          roster: _roster(studentChange: RiderChange.added),
          ackRequired: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('승하차지·명단이 변경됐습니다'), findsOneWidget);
    expect(find.text('변경 목록 확인'), findsOneWidget);
  });

  testWidgets('변경 목록 확인을 누르면 ack-changes 를 호출하고 배너를 닫는다', (tester) async {
    final overrides = overridesFor(
      roster: _roster(stopChange: StopChange.added),
      ackRequired: true,
      ackResult: AckChangesResult(ackedAt: DateTime(2026, 9, 12, 9)),
    );

    await tester.pumpWidget(_wrap(const RosterScreen(), overrides));
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(find.text('변경 목록 확인'), findsNothing);
  });

  testWidgets('변경 목록 확인 호출 시 요청 본문 없이 전건 확인을 호출한다(Ruling 344)', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(stopChange: StopChange.added),
      ackResult: AckChangesResult(ackedAt: DateTime(2026, 9, 12, 9)),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: true)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastAckRunId, runId);
  });

  testWidgets('ack-changes 가 실패하면 실패 사유를 보여주고 배너는 남는다', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(stopChange: StopChange.added),
      ackFailure: const ApiFailure(
        statusCode: 409,
        code: 'RUN_NOT_CONFIRMED',
        message: '확정 전',
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: true)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(find.text('아직 확정되지 않은 운행입니다'), findsOneWidget);
    expect(find.text('변경 목록 확인'), findsOneWidget);
  });

  testWidgets('되돌리기(§4.7)가 실패하면 실패 사유를 보여준다', (tester) async {
    // 되돌리기 버튼은 canDecide(동승자 전용)일 때만 그려지고, waiting 상태의
    // 학생에는 아예 노출되지 않는다(roster_screen.dart `_StudentActions`) —
    // 그래서 이 시험만 role 을 동승자로 override 하고 학생 상태를 boarded
    // 로 바꿔 버튼을 실제로 그리게 한다.
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(studentStatus: RiderStatus.boarded),
      revertFailure: const ApiFailure(
        statusCode: 409,
        code: 'REVERT_WINDOW_EXPIRED',
        message: '되돌리기 가능 시간이 지났습니다',
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();

    expect(find.text('되돌리기 가능 시간이 지났습니다'), findsOneWidget);
  });

  testWidgets('승하차 상태 갱신이 통신 두절로 큐에 쌓이면 대기 안내를 보여준다', (tester) async {
    // §1.7 M-06 — sendOrQueue 가 Queued 를 돌려주는 경우(UF-E-07). "탑승"
    // 버튼은 canDecide(동승자 전용) + waiting 상태에서만 그려진다.
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(),
      updateOutcome: const Queued<RiderUpdateResult>(),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
    await tester.pumpAndSettle();

    expect(find.text('처리되지 않았습니다 · 대기 중'), findsOneWidget);
  });

  testWidgets('승하차 상태 갱신이 즉시 성공하면 대기 안내를 보여주지 않는다', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(),
      updateOutcome: Sent(
        RiderUpdateResult(
          riderId: 'r1',
          status: RiderStatus.boarded,
          changedAt: DateTime(2026, 9, 12, 9),
          stopSkipped: false,
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
    await tester.pumpAndSettle();

    expect(find.text('처리되지 않았습니다 · 대기 중'), findsNothing);
    expect(fakeRepo.lastUpdateClientKey, isNotNull);
  });

  testWidgets('승하차 상태 갱신이 서버 거절(4xx)로 실패하면 실패 사유를 보여준다', (tester) async {
    // NetworkFailure 가 아니라 ApiFailure 라 sendOrQueue 가 그대로 다시
    // 던진다(재시도해도 같은 응답이라 큐 대상이 아니다) — 화면은 기존
    // Failure 처리 경로(_errorMessage)를 그대로 탄다.
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(),
      updateFailure: const ApiFailure(
        statusCode: 409,
        code: 'RUN_NOT_MOVING',
        message: '운행 중이 아닙니다',
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
    await tester.pumpAndSettle();

    expect(find.text('처리되지 않았습니다 · 대기 중'), findsNothing);
    expect(find.textContaining('운행 중'), findsWidgets);
  });

  // M3(Ruling 345) — 같은 상태 재요청 포함, 서버가 409
  // RIDER_TRANSITION_NOT_ALLOWED 로 거절하면 전용 문구를 보여주고 명단을
  // 다시 불러와야 한다(재요청 사이 다른 사람이 이미 처리했을 수 있어서).
  testWidgets(
    '409 RIDER_TRANSITION_NOT_ALLOWED 면 전용 문구 + 명단을 다시 불러온다',
    (tester) async {
      final fakeRepo = _FakeRosterRepository(
        roster: _roster(),
        updateFailure: const ApiFailure(
          statusCode: 409,
          code: 'RIDER_TRANSITION_NOT_ALLOWED',
          message: '허용되지 않는 상태 전이입니다',
        ),
      );

      await tester.pumpWidget(
        _wrap(const RosterScreen(), [
          selectedRunIdProvider.overrideWith((ref) => runId),
          rosterRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith(
            (ref) async => [_managerRun(ackRequired: false)],
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(fakeRepo.fetchRosterCallCount, 1);

      await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
      await tester.pumpAndSettle();

      expect(find.text('이미 처리된 학생입니다 — 명단을 새로 불러왔습니다'), findsOneWidget);
      expect(fakeRepo.fetchRosterCallCount, 2);
    },
  );

  // M1(Ruling 341, BR-016) — 버스 간 이동으로 빠진 학생은 `status: absent` ·
  // `change: removed` 로 명단에 남는다(§4.2). 다른 버스로 옮긴 학생에게
  // [탑승]·[미승차] 버튼이 보이면 안 되고, "금일 삭제" 배지만 보여야 한다.
  testWidgets('금일 삭제(absent·removed) 학생은 배지만 보이고 조작 버튼이 없다', (tester) async {
    const roster = RosterResponse(
      runId: runId,
      busNo: '3호차',
      direction: RunDirection.toAcademy,
      counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 1),
      stops: [
        RosterStop(
          stopId: 'stop-1',
          seq: 1,
          name: 'A정류장',
          students: [
            RosterStudent(
              riderId: 'r1',
              studentId: 's1',
              name: '김바래',
              photoUrl: null,
              guardianPhone: null,
              canGoAlone: false,
              status: RiderStatus.absent,
              change: RiderChange.removed,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(
          _FakeRosterRepository(roster: roster),
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('금일 삭제'), findsOneWidget);
    expect(find.widgetWithText(BaraedaButton, '탑승'), findsNothing);
    expect(find.widgetWithText(BaraedaButton, '미승차'), findsNothing);
  });

  group('목표 9 — 연결 배너가 명단 상태와 무관하게 뜬다', () {
    // 실제 ManagerRunChannelController 를 그대로 쓰고 tokenStorageProvider
    // 만 영원히 응답하지 않는 대역으로 바꿔 connecting 상태에 고정한다 —
    // 클래스 주석 참고. 어느 상태로 고정하든 "배너가 rosterAsync.when()
    // 분기 바깥에 있다"는 구조를 확인하는 데는 같다.
    List<Override> overridesWithBanner(List<Override> base) => [
      ...base,
      tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
    ];

    testWidgets('명단이 로딩 중이어도 배너가 뜬다', (tester) async {
      final neverCompletes = Completer<RosterResponse>().future;
      await tester.pumpWidget(
        _wrap(
          const RosterScreen(),
          overridesWithBanner([
            selectedRunIdProvider.overrideWith((ref) => runId),
            rosterProvider.overrideWith((ref) => neverCompletes),
            todayRunsProvider.overrideWith(
              (ref) async => [_managerRun(ackRequired: false)],
            ),
          ]),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('실시간 연결 중'), findsOneWidget);
    });

    testWidgets('명단에 데이터가 있어도 배너가 뜬다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RosterScreen(),
          overridesWithBanner(
            overridesFor(roster: _roster(), ackRequired: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('실시간 연결 중'), findsOneWidget);
      // 데이터도 정상적으로 함께 그려진다 — 배너가 명단을 가리지 않는다.
      expect(find.text('김바래'), findsOneWidget);
    });

    testWidgets('명단이 비어 있어도 배너가 뜬다', (tester) async {
      const emptyRoster = RosterResponse(
        runId: runId,
        busNo: '3호차',
        direction: RunDirection.toAcademy,
        counts: RosterCounts(
          boarded: 0,
          waiting: 0,
          noShow: 0,
          absentN: 0,
        ),
        stops: [],
      );

      await tester.pumpWidget(
        _wrap(
          const RosterScreen(),
          overridesWithBanner(
            overridesFor(roster: emptyRoster, ackRequired: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('실시간 연결 중'), findsOneWidget);
    });
  });
}
