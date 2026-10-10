import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/data/manager_run_api.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/roster/data/drift_roster_cache.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_notification_repository.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/manager_run_fixture.dart';

/// 서버에 닿지 못하는 연결 — 어떤 요청이든 연결 두절로 실패한다.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: '테스트 — 통신 두절',
  );
}

class _OfflineMe implements AuthRepository {
  @override
  Future<MeResponse> me() => Future<MeResponse>.error(const Failure.network());

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

const Map<String, dynamic> _rosterJson = {
  'run_id': 'run-1',
  'bus_no': '3호차',
  'direction': 'to_academy',
  'counts': {'boarded': 0, 'waiting': 1, 'no_show': 0, 'absent_n': 0},
  'stops': [
    {
      'stop_id': 's1',
      'seq': 1,
      'name': 'A정류장',
      'students': [
        {
          'rider_id': 'r1',
          'student_id': 'st1',
          'name': '김바래',
          'photo_url': null,
          'guardian_phone': null,
          'can_go_alone': true,
          'status': 'waiting',
        },
      ],
    },
  ],
};

/// R52 H2(수정 라운드 1) — 통신이 끊긴 채 앱을 새로 켜면 **마지막 성공 응답의 회차 요약**으로 홈 · 선택 회차를 채워
/// 저장 명단이 열리고 비상 신고 후보 회차가 있어야 한다(NFR-01 · M-06 · UF-E-07). 회차 목록 · 명단 조회를 가리지
/// 않고 실제 통신 실패를 거친다.
void main() {
  final now = DateTime(2026, 10, 10, 10);

  Future<({ProviderContainer container, OfflineQueueDatabase database})>
  pumpOfflineApp(
    WidgetTester tester, {
    required FakeRunSummaryStore summary,
  }) async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final keys = FakeRosterKeyStore();
    await DriftRosterCache(database: database, cipher: RosterCipher(keys)).save(
      'run-1',
      jsonDecode(jsonEncode(_rosterJson)) as Map<String, dynamic>,
    );
    final offlineDio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _OfflineAdapter();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(_FixedClock(now)),
          tokenStorageProvider.overrideWithValue(
            FakeTokenStorage(seedRefreshToken: 'refresh'),
          ),
          authRepositoryProvider.overrideWithValue(_OfflineMe()),
          lastSessionStoreProvider.overrideWithValue(
            FakeLastSessionStore(AccountRole.escort),
          ),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
          runSummaryStoreProvider.overrideWithValue(summary),
          managerRunApiProvider.overrideWithValue(
            ManagerRunApi(dio: offlineDio),
          ),
          rosterApiProvider.overrideWithValue(RosterApi(dio: offlineDio)),
          offlineQueueDatabaseProvider.overrideWithValue(database),
          rosterKeyStoreProvider.overrideWithValue(keys),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(const []),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const BaraedaManagerApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container: container, database: database);
  }

  FakeRunSummaryStore savedToday() => FakeRunSummaryStore((
    savedAt: DateTime(2026, 10, 10, 9),
    runs: [
      managerRunFixture(
        departTime: DateTime(2026, 10, 10, 11),
        roleInRun: UserRole.escort,
      ),
    ],
  ));

  testWidgets('통신 두절로 새로 켜도 저장 회차 요약으로 저장 명단이 열리고 비상 신고 후보가 있다', (
    tester,
  ) async {
    final app = await pumpOfflineApp(tester, summary: savedToday());

    expect(find.text('저장된 명단을 보고 있어요'), findsOneWidget);
    expect(find.text('김바래'), findsOneWidget);
    final runs = app.container.read(todayRunsProvider).value!;
    expect(runs.where(EmergencyButton.canRaiseEmergency), hasLength(1));
    expect(runs.single.runStatus, RunStatus.confirmed);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('어제 저장한 회차 요약은 쓰지 않는다 — 목록 조회 실패가 그대로 보인다', (tester) async {
    final yesterday = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 9, 9),
      runs: [managerRunFixture(departTime: DateTime(2026, 10, 9, 11))],
    ));
    final app = await pumpOfflineApp(tester, summary: yesterday);

    expect(find.text('김바래'), findsNothing);
    expect(app.container.read(todayRunsProvider).hasError, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
