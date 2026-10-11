import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/features/emergency/data/emergency_api.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_unsent_emergency_store.dart';

/// 모든 요청에 [status] 와 [body] 로 답한다.
class _FixedAdapter implements HttpClientAdapter {
  new(this.status, this.body);

  final int status;
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// 887③ — 비상 신고를 직접 보내는 순간 세션이 끝나(재발급 401 · 대기·거절 게이트 403) 못 보낸 신고는 대기열에도
/// 없이 로그인 화면으로 바뀐다. 그 한 건을 886 의 기기 저장 안내에 더한다. 그 밖의 실패는 지금대로다.
void main() {
  late OfflineQueueDatabase database;
  late FakeUnsentEmergencyStore unsent;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    unsent = FakeUnsentEmergencyStore();
  });
  tearDown(() => database.close());

  ProviderContainer open(int status, String body) {
    final container = ProviderContainer(
      overrides: [
        offlineQueueDatabaseProvider.overrideWithValue(database),
        unsentEmergencyStoreProvider.overrideWithValue(unsent),
        academyContactStoreProvider.overrideWithValue(
          FakeAcademyContactStore('032-000-1100'),
        ),
        emergencyApiProvider.overrideWithValue(
          EmergencyApi(
            dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = _FixedAdapter(status, body),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(unsentEmergencyProvider, (_, _) {});
    container.read(academyContactProvider.notifier).state = '032-111-2222';
    return container;
  }

  Future<Object?> raise(ProviderContainer container) async {
    try {
      await container
          .read(emergencyRepositoryProvider)
          .raise(
            runId: 'run-A',
            request: const EmergencyRaiseRequest(
              type: EmergencyType.accident,
              clientKey: 'E',
            ),
          );
      return null;
    } on Failure catch (failure) {
      return failure;
    }
  }

  String envelope(String code) => '{"error":{"code":"$code","message":"m"}}';

  final cases = <(String, int, String, int)>[
    ('재발급이 거절된 401', 401, envelope('TOKEN_EXPIRED'), 1),
    ('승인 대기 게이트 403', 403, envelope('AUTH_PENDING'), 1),
    ('가입 거절 게이트 403', 403, envelope('AUTH_REJECTED'), 1),
    ('그 밖의 403(권한)', 403, envelope('FORBIDDEN'), 0),
    ('422 검증 실패', 422, envelope('VALIDATION_FAILED'), 0),
  ];
  for (final (name, status, body, count) in cases) {
    test(
      '직접 전송이 $name 이면 기기 저장 안내 ${count == 1 ? '에 더한다' : '를 만들지 않는다'}',
      () async {
        final container = open(status, body);

        final failure = await raise(container);
        await pumpEventQueue();

        expect(failure, isA<Failure>(), reason: '호출부는 지금처럼 실패를 그대로 받는다');
        expect(
          container.read(unsentEmergencyProvider)?.count,
          count == 0 ? null : count,
        );
        expect(unsent.saved?.count, count == 0 ? null : count);
        if (count == 1) {
          expect(unsent.saved?.contact, '032-111-2222');
        }
      },
    );
  }

  test('직접 전송이 5xx 면 대기열에 쌓이고 기기 저장 안내는 만들지 않는다', () async {
    final container = open(503, envelope('SERVICE_UNAVAILABLE'));

    final failure = await raise(container);
    await pumpEventQueue();

    expect(failure, isNull);
    expect(container.read(unsentEmergencyProvider), isNull);
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      hasLength(1),
    );
  });
}
