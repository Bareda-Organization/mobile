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
import 'package:manager_app/core/run/manager_connection.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
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
  new({
    required this.roster,
    this.ackResult,
    this.ackFailure,
    this.revertFailure,
    this.updateOutcome,
    this.updateFailure,
    this.failFetchFromCall,
  });

  final RosterResponse roster;
  final AckChangesResult? ackResult;
  final Failure? ackFailure;
  final Failure? revertFailure;

  /// §1.7 오프라인 큐 시험용 — [Sent]·[Queued] 중 어느 쪽을 돌려줄지.
  final SendOutcome<RiderUpdateResult>? updateOutcome;
  final Failure? updateFailure;

  /// R46 — 이 번째(1부터) 명단 조회부터 실패시킨다. 갱신 실패 뒤 마지막 명단이 남는지 보는 시험용.
  final int? failFetchFromCall;
  String? lastAckRunId;

  /// 즉시 전송·재생이 같은 client_key 를 쓰는지 검증하는 시험이 읽는다.
  String? lastUpdateClientKey;
  DateTime? lastUpdateOccurredAt;

  /// M3 — 실패 시 명단이 **다시 조회됐는지**(재조회 1회) 확인하는 시험이 읽는다.
  int fetchRosterCallCount = 0;

  /// 되돌리기 요청이 서버로 나간 횟수 — 확인 창 앞에서는 0 이어야 한다.
  int revertCallCount = 0;

  @override
  Future<RosterResponse> fetchRoster(String runId) async {
    fetchRosterCallCount++;
    if (failFetchFromCall != null &&
        fetchRosterCallCount >= failFetchFromCall!) {
      // Failure 는 Exception/Error 를 상속하지 않는다(위 ackChanges 와 같은 패턴).
      // ignore: only_throw_errors
      throw const NetworkFailure();
    }
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
    lastUpdateOccurredAt = request.occurredAt;
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
    revertCallCount++;
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
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
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
  testWidgets('상대 경로 photo_url 은 호스트에 붙여 토큰 헤더와 함께 학생 사진으로 그린다', (
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

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(
      provider.url,
      '${Uri.parse(ApiConstants.baseUrl).origin}/api/v1/files/photos/a.jpg',
    );
    expect(provider.headers, {'Authorization': 'Bearer tok-1'});
  });

  // R39 Ruling 400 — 서버 seq 는 경유 지점 자리(2)를 비운 채 1·3 으로 온다. 명단 머리가 그 값을 그대로 쓰면
  // "1. A · 3. B" 로 번호가 건너뛰고 지도 핀(경유 지점을 뺀 연속 번호 1·2)과 어긋난다.
  testWidgets('정류장 머리 번호는 서버 seq 가 아니라 경유 지점을 뺀 연속 번호다', (tester) async {
    const roster = RosterResponse(
      runId: 'run-1',
      busNo: '3호차',
      direction: RunDirection.toAcademy,
      counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
      stops: [
        RosterStop(stopId: 'a', seq: 1, name: 'A정류장', students: []),
        RosterStop(stopId: 'b', seq: 3, name: 'B정류장', students: []),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(roster: roster, ackRequired: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A정류장'), findsOneWidget);
    expect(find.text('B정류장'), findsOneWidget);
    // 번호 원은 이 목록의 순번 1 · 2 다 — 서버 seq(3)가 아니다.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  // 미경유 승하차지는 타임라인(`StopTimeline`)·지도 핀과 같이 이름에 취소선을 긋는다 — 빨간 글씨만으로는 구분이 약하다.
  testWidgets('미경유 승하차지 이름에는 취소선이 그어지고 경유하는 곳에는 없다', (tester) async {
    const roster = RosterResponse(
      runId: 'run-1',
      busNo: '3호차',
      direction: RunDirection.toAcademy,
      counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
      stops: [
        RosterStop(stopId: 'a', seq: 1, name: 'A정류장', students: []),
        RosterStop(
          stopId: 'b',
          seq: 2,
          name: 'B정류장',
          change: StopChange.skipped,
          students: [],
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(roster: roster, ackRequired: false),
      ),
    );
    await tester.pumpAndSettle();

    TextDecoration? decorationOf(String name) =>
        tester.widget<Text>(find.text(name)).style?.decoration;
    expect(decorationOf('B정류장'), TextDecoration.lineThrough);
    expect(decorationOf('A정류장'), isNot(TextDecoration.lineThrough));
  });

  testWidgets('ack_required 가 false 면 변경 확인 배너를 보여주지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(roster: _roster(), ackRequired: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('변경 확인'), findsNothing);
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

    expect(find.text('노선이 바뀌었어요'), findsOneWidget);
    expect(find.text('변경 확인'), findsOneWidget);
  });

  testWidgets('변경 목록 확인을 누르면 ack-changes 를 호출하고 배너를 닫는다', (tester) async {
    final overrides = overridesFor(
      roster: _roster(stopChange: StopChange.added),
      ackRequired: true,
      ackResult: AckChangesResult(ackedAt: DateTime(2026, 9, 12, 9)),
    );

    await tester.pumpWidget(_wrap(const RosterScreen(), overrides));
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 확인'));
    await tester.pumpAndSettle();

    expect(find.text('변경 확인'), findsNothing);
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

    await tester.tap(find.text('변경 확인'));
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

    await tester.tap(find.text('변경 확인'));
    await tester.pumpAndSettle();

    expect(find.text('아직 확정되지 않은 운행입니다'), findsOneWidget);
    expect(find.text('변경 확인'), findsOneWidget);
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
    // 되돌리기는 확인 창을 거친다 — 창의 [되돌리기] 를 눌러야 요청이 나가고 실패 사유가 보인다.
    await tester.tap(
      find.descendant(
        of: find.byType(BaraedaBottomSheet),
        matching: find.widgetWithText(BaraedaButton, '되돌리기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('되돌리기 가능 시간이 지났습니다'), findsOneWidget);
  });

  group('되돌리기 확인 창 (시안 undo)', () {
    Future<_FakeRosterRepository> pumpRoster(
      WidgetTester tester,
      RiderStatus status,
    ) async {
      final fakeRepo = _FakeRosterRepository(
        roster: _roster(studentStatus: status),
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
      return fakeRepo;
    }

    Finder sheetButton(String label) => find.descendant(
      of: find.byType(BaraedaBottomSheet),
      matching: find.widgetWithText(BaraedaButton, label),
    );

    testWidgets('[되돌리기] 를 누르면 무엇이 어떻게 바뀌는지 묻고 요청은 아직 나가지 않는다', (tester) async {
      final fakeRepo = await pumpRoster(tester, RiderStatus.boarded);

      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();

      expect(find.text('승차 처리를 되돌릴까요?'), findsOneWidget);
      expect(find.text('김바래'), findsWidgets);
      expect(find.text('처리 기록은 지워지지 않고 남아요'), findsOneWidget);
      // 승차 취소 알림은 폐지됐다(Ruling 308) — 시트가 알림을 약속하지 않는다.
      expect(find.textContaining('승차 취소'), findsNothing);
      expect(fakeRepo.revertCallCount, 0, reason: '확인 전에는 요청이 없다');
    });

    testWidgets('창의 [되돌리기] 를 눌러야 요청이 한 번 나간다', (tester) async {
      final fakeRepo = await pumpRoster(tester, RiderStatus.boarded);

      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      await tester.tap(sheetButton('되돌리기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.revertCallCount, 1);
    });

    testWidgets('[닫기] 는 요청을 보내지 않고 창만 닫는다', (tester) async {
      final fakeRepo = await pumpRoster(tester, RiderStatus.boarded);

      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      await tester.tap(sheetButton('닫기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.revertCallCount, 0);
      expect(find.byType(BaraedaBottomSheet), findsNothing);
    });

    testWidgets('하차 처리는 하차 → 탑승, 미승차 처리는 미승차 → 대기로 되돌린다고 알린다', (tester) async {
      await pumpRoster(tester, RiderStatus.alighted);
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect(find.text('하차 처리를 되돌릴까요?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BaraedaBottomSheet),
          matching: find.text('탑승'),
        ),
        findsOneWidget,
      );
    });
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
        // 큐에 실제로 쌓인 것으로 답한다 — 안내는 큐 목록에서 그린다(R46).
        pendingRequestsProvider.overrideWith(
          (ref) async => [
            PendingRequestSummary(
              id: 1,
              endpoint: '/runs/$runId/riders/r1',
              method: 'PATCH',
              payload: '{"status":"boarded"}',
              createdAt: DateTime(2026, 9, 12, 9),
            ),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // 큐에 이미 쌓인 학생 행은 [탑승] 대신 "전송 대기" 다(R46) — 이 시험은 안내 문구만 본다.
    expect(find.text('처리되지 않았어요 · 대기 중 1건'), findsOneWidget);
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

    expect(find.text('처리되지 않았어요 · 대기 중'), findsNothing);
    expect(fakeRepo.lastUpdateClientKey, isNotNull);
  });

  // F06-05 — 오프라인으로 쌓였다 나중에 재생되는 승하차 처리도 누른 시각을 서버가 알아야 한다
  // (미승차 3분 대기 · 학부모 알림 시각의 기준). 비상 발신은 이미 보내고 있었다.
  testWidgets('승하차 처리 요청에 누른 시각(occurred_at)이 clockProvider 값으로 실린다', (
    tester,
  ) async {
    final pressedAt = DateTime(2026, 9, 30, 8, 42, 3);
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
        clockProvider.overrideWithValue(_FixedClock(pressedAt)),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdateOccurredAt, pressedAt);
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

    expect(find.text('처리되지 않았어요 · 대기 중'), findsNothing);
    expect(find.textContaining('운행 중'), findsWidgets);
  });

  // M3(Ruling 345) — 같은 상태 재요청 포함, 서버가 409
  // RIDER_TRANSITION_NOT_ALLOWED 로 거절하면 전용 문구를 보여주고 명단을
  // 다시 불러와야 한다(재요청 사이 다른 사람이 이미 처리했을 수 있어서).
  testWidgets('409 RIDER_TRANSITION_NOT_ALLOWED 면 전용 문구 + 명단을 다시 불러온다', (
    tester,
  ) async {
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
  });

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

      expect(find.byType(BaraedaSkeleton), findsWidgets);
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
        counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
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

  // R46 A — 갱신이 실패해도 마지막 명단을 지우지 않는다. 오류는 목록 위에 따로 알린다.
  testWidgets('R46 명단 갱신이 실패해도 마지막 명단이 남고 오류와 [다시 시도] 를 알린다', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(),
      failFetchFromCall: 2,
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
    expect(find.text('김바래'), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(RosterScreen)))
        .invalidate(rosterProvider);
    await tester.pumpAndSettle();

    expect(find.text('김바래'), findsOneWidget);
    expect(find.textContaining('최신 명단을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  // R46 A — 글자 버튼 4개가 제목을 밀어내 제목이 사라졌다. 앱바에는 비상만 남긴다.
  testWidgets('R46 머리줄에는 제목과 비상만 있고 나머지 단추는 본문 위 줄에 있다', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fakeRepo = _FakeRosterRepository(roster: _roster());
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

    final appBar = find.byType(ManagerHeader);
    expect(
      find.descendant(of: appBar, matching: find.text('명단')),
      findsOneWidget,
    );
    for (final label in ['예외 보고', '지연 알림', '대기열']) {
      expect(
        find.descendant(of: appBar, matching: find.text(label)),
        findsNothing,
      );
      expect(find.text(label), findsOneWidget);
    }
  });

  group('연결 끊김 띠 (시안 roster-escort--offline)', () {
    Future<void> pumpRoster(
      WidgetTester tester, {
      DateTime? offlineSince,
    }) async {
      await tester.pumpWidget(
        _wrap(const RosterScreen(), [
          selectedRunIdProvider.overrideWith((ref) => runId),
          rosterRepositoryProvider.overrideWithValue(
            _FakeRosterRepository(roster: _roster()),
          ),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith(
            (ref) async => [_managerRun(ackRequired: false)],
          ),
          managerOfflineSinceProvider(runId)
              .overrideWith((ref) => offlineSince),
        ]),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('끊겨 있으면 맨 위에 언제부터인지 띠로 알린다', (tester) async {
      await pumpRoster(tester, offlineSince: DateTime(2026, 9, 12, 8, 41));

      expect(find.text('인터넷 연결 없음 · 08:41 부터'), findsOneWidget);
      // 띠는 머리줄(제목) 위에 있다.
      expect(
        tester.getTopLeft(find.text('인터넷 연결 없음 · 08:41 부터')).dy,
        lessThan(tester.getTopLeft(find.text('명단')).dy),
      );
    });

    testWidgets('연결돼 있으면 띠가 없다', (tester) async {
      await pumpRoster(tester);

      expect(find.byType(BaraedaConnectionStrip), findsNothing);
    });
  });
}
