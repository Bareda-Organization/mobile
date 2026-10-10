import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/roster/data/drift_roster_cache.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';
import 'package:manager_app/features/roster/data/roster_repository_impl.dart';

import '../../support/fake_roster_key_store.dart';

/// M-M3(M-06 · BRD-06 · UF-E-07 · `USER_FLOWS §12.2`) — 명단은 로컬에 저장돼 앱을 다시 켠 뒤
/// 오프라인이어도 마지막으로 받은 명단을 본다. 서버가 응답하지 못할 때(연결 없음 · 5xx)만
/// 저장본으로 돌아서고, 4xx 같은 서버의 판단(권한 없음 · 회차 없음)은 저장본으로 덮지 않는다.
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
          'class_name': '초3',
          'guardian_phone': '010-****-1234',
          'note': '견과류 알레르기',
          'can_go_alone': true,
          'status': 'waiting',
        },
      ],
    },
  ],
};

/// 첫 호출은 [first] 로, 그 뒤는 [then] 으로 답하는 서버 흉내.
class _Adapter implements HttpClientAdapter {
  new({required this.first, this.then});

  final Future<ResponseBody> Function(RequestOptions) first;
  final Future<ResponseBody> Function(RequestOptions)? then;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return calls == 1 || then == null ? first(options) : then!(options);
  }
}

Future<ResponseBody> _ok(RequestOptions _) async => ResponseBody.fromString(
  jsonEncode(_rosterJson),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Future<ResponseBody> _offline(RequestOptions options) async =>
    throw DioException.connectionError(
      requestOptions: options,
      reason: '테스트 — 통신 두절',
    );

Future<ResponseBody> _status(int status) async => ResponseBody.fromString(
  '{"error":{"code":"X","message":"m"}}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late OfflineQueueDatabase database;
  late DriftRosterCache cache;
  const clock = _FixedClock();

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    cache = DriftRosterCache(
      database: database,
      cipher: RosterCipher(FakeRosterKeyStore()),
      clock: clock,
    );
  });
  tearDown(() => database.close());

  RosterRepositoryImpl repositoryWith(_Adapter adapter) => RosterRepositoryImpl(
    api: RosterApi(
      dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = adapter,
    ),
    offlineQueue: _NoQueue(),
    cache: cache,
  );

  test('서버에서 받은 명단은 저장되고, 이어서 연결이 끊기면 저장본을 보인다', () async {
    final adapter = _Adapter(first: _ok, then: _offline);
    final repository = repositoryWith(adapter);

    final fresh = await repository.fetchRoster('run-1');
    expect(fresh.cachedAt, isNull, reason: '서버에서 받은 명단은 저장본이 아니다');

    final offline = await repository.fetchRoster('run-1');
    expect(offline.cachedAt, DateTime(2026, 10, 10, 8, 5));
    expect(offline.stops.single.students.single.name, '김바래');
    expect(offline.stops.single.students.single.note, '견과류 알레르기');
  });

  test('앱을 다시 켠 뒤(새 저장소 객체)에도 오프라인이면 마지막 명단을 본다', () async {
    await repositoryWith(_Adapter(first: _ok)).fetchRoster('run-1');

    final restarted = repositoryWith(_Adapter(first: _offline));
    final roster = await restarted.fetchRoster('run-1');

    expect(roster.runId, 'run-1');
    expect(roster.cachedAt, isNotNull);
  });

  test('서버가 5xx 로 응답해도 저장본을 보인다', () async {
    await repositoryWith(_Adapter(first: _ok)).fetchRoster('run-1');

    final roster = await repositoryWith(_Adapter(first: (_) => _status(502)))
        .fetchRoster('run-1');

    expect(roster.cachedAt, isNotNull);
  });

  test('저장본이 없으면 연결 실패를 그대로 알린다', () async {
    final repository = repositoryWith(_Adapter(first: _offline));

    expect(repository.fetchRoster('run-1'), throwsA(isA<NetworkFailure>()));
  });

  test('서버의 4xx 판단(권한 없음 등)은 저장본으로 덮지 않는다', () async {
    await repositoryWith(_Adapter(first: _ok)).fetchRoster('run-1');

    final repository = repositoryWith(_Adapter(first: (_) => _status(403)));

    expect(repository.fetchRoster('run-1'), throwsA(isA<ApiFailure>()));
  });

  test('다른 회차의 저장본은 쓰지 않는다', () async {
    await repositoryWith(_Adapter(first: _ok)).fetchRoster('run-1');

    final repository = repositoryWith(_Adapter(first: _offline));

    expect(repository.fetchRoster('run-2'), throwsA(isA<NetworkFailure>()));
  });

  test('clear 하면 저장본이 모두 사라진다(로그아웃·세션 만료)', () async {
    await repositoryWith(_Adapter(first: _ok)).fetchRoster('run-1');

    await cache.clear();

    expect(await cache.read('run-1'), isNull);
  });
}

/// 이 시험은 명단 조회만 본다 — 대기열은 쓰지 않는다.
class _NoQueue implements OfflineQueueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixedClock implements Clock {
  const new();

  @override
  DateTime now() => DateTime(2026, 10, 10, 8, 5);
}
