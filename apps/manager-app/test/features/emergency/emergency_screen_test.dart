import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/emergency/domain/emergency_repository.dart';
import 'package:manager_app/features/emergency/presentation/emergency_screen.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 시각을 고정해 취소 가능 창 판정을 결정적으로 만드는 가짜 시계
/// (`drive_mode_screen_test.dart` 와 같은 패턴, 이월 11 · Ruling 266).
class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 테스트 전용 대역 — §4.14(발신·취소)·§4.15(목록) 호출 여부·인자·횟수만
/// 기록한다.
class _FakeEmergencyRepository implements EmergencyRepository {
  _FakeEmergencyRepository({
    this.raiseOutcome,
    this.raiseFailure,
    this.cancelFailure,
    this.list,
    this.listFailure,
  });

  final SendOutcome<EmergencyRaiseResult>? raiseOutcome;
  final Failure? raiseFailure;
  final Failure? cancelFailure;
  final EmergencyListResponse? list;
  final Failure? listFailure;

  int raiseCallCount = 0;
  EmergencyRaiseRequest? lastRequest;
  String? lastCanceledEmergencyId;

  @override
  Future<SendOutcome<EmergencyRaiseResult>> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  }) async {
    raiseCallCount++;
    lastRequest = request;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고) — delay_screen_test.dart 와
    // 같은 패턴.
    // ignore: only_throw_errors
    if (raiseFailure != null) throw raiseFailure!;
    return raiseOutcome!;
  }

  @override
  Future<void> cancel({
    required String runId,
    required String emergencyId,
  }) async {
    lastCanceledEmergencyId = emergencyId;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다(위 raise
    // 주석과 같은 이유).
    // ignore: only_throw_errors
    if (cancelFailure != null) throw cancelFailure!;
  }

  @override
  Future<EmergencyListResponse> fetchList({required String runId}) async {
    // Failure 는 Exception/Error 를 상속하지 않는다 — 위 raise 와 같은 이유.
    // ignore: only_throw_errors
    if (listFailure != null) throw listFailure!;
    return list ?? const EmergencyListResponse(items: []);
  }
}

/// 항상 같은 좌표 스냅샷(또는 `null`)을 돌려주는 가짜 위치 소스 —
/// `drive_mode_position_transmission_test.dart` 와 같은 패턴(F1). `sampleOnce`
/// 는 스트림이 없을 때(BG2)의 1회 측정을 대역한다 — 호출 횟수를 기록하고,
/// 값을 즉시 낼지([onceSample]) 완료를 미룰지([onceCompleter], 중복 발신
/// 시험용)를 고른다.
class _FakePositionSource implements PositionSource {
  _FakePositionSource(this._sample, {this.onceSample, this.onceCompleter});

  final PositionSample? _sample;
  final PositionSample? onceSample;
  final Completer<PositionSample?>? onceCompleter;

  int sampleOnceCallCount = 0;

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    sampleOnceCallCount++;
    if (onceCompleter != null) return onceCompleter!.future;
    return onceSample;
  }

  @override
  PositionSample? sample() => _sample;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  const runId = 'run-1';
  final raisedAt = DateTime(2026, 9, 12, 9);
  final cancelableUntil = raisedAt.add(const Duration(minutes: 1));

  List<Override> overridesFor({
    required _FakeEmergencyRepository fakeRepo,
    DateTime? now,
    // `_submit` 이 sample() null 이면 sampleOnce() 로 넘어간다(BG2) — 이
    // 값을 안 주는 시험은 기본 provider(di.dart 의 실제
    // GeolocatorPositionSource) 로 떨어져 플랫폼 채널을 두드리다 예외를
    // 낸다. 좌표를 직접 다루지 않는 시험은 이 기본값(둘 다 null)으로
    // 충분하다.
    PositionSource? positionSource,
  }) {
    return [
      selectedRunIdProvider.overrideWith((ref) => runId),
      emergencyRepositoryProvider.overrideWithValue(fakeRepo),
      clockProvider.overrideWithValue(_FixedClock(now ?? raisedAt)),
      positionSourceProvider.overrideWithValue(
        positionSource ?? _FakePositionSource(null),
      ),
    ];
  }

  testWidgets('선택된 운행이 없으면 안내만 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), [
        selectedRunIdProvider.overrideWith((ref) => null),
      ]),
    );

    expect(find.text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'), findsOneWidget);
  });

  testWidgets('유형이 기타인데 메모가 비어 있으면 서버 호출 없이 막는다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('기타'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('기타 유형은 상황 메모가 필요합니다'), findsOneWidget);
    expect(fakeRepo.raiseCallCount, 0);
  });

  testWidgets('발신이 즉시 성공하면(Sent) 알림 대상 수와 취소 가능 시각을 보여준다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: cancelableUntil,
          notified: 3,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3명에게 전달'), findsOneWidget);
    expect(find.text('처리되지 않았습니다 · 대기 중'), findsNothing);
    // raise 는 client_key 를 반드시 채워 보낸다(§1.7 멱등 대상 ②).
    expect(fakeRepo.lastRequest?.clientKey, isNotEmpty);
  });

  testWidgets(
    '발신 요청에 occurred_at 이 clockProvider 가 준 시각 그대로 실린다',
    (tester) async {
      // §4.14 는 occurred_at 을 "오프라인 발신분의 실제 시각"으로 규정하고
      // 비상 발신은 §1.7 오프라인 큐 대상이다 — 통신이 끊겼다 복구됐을 때
      // 서버가 실제 발생 시각을 알 수 있어야 한다. `clockProvider` 를
      // `raisedAt` 으로 고정해 그 값이 그대로(가짜 시계 값과 다른 값이
      // 아니라) 나가는지 본다.
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );

      await tester.pumpWidget(
        _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.occurredAt, raisedAt);
    },
  );

  testWidgets(
    '위치 소스가 좌표를 주면 발신 요청에 lat·lng 가 실린다 (F1)',
    (tester) async {
      // 비상은 기사·동승자 둘 다 발신한다(ARCHITECTURE §3.3·EXC-04) —
      // 이 시험은 역할을 override 하지 않는다(역할 무관 동작을 확인).
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );
      final sample = PositionSample(
        lat: 37.5,
        lng: 127,
        recordedAt: DateTime(2026, 9, 12, 8, 59),
      );

      await tester.pumpWidget(
        _wrap(
          const EmergencyScreen(),
          overridesFor(
            fakeRepo: fakeRepo,
            positionSource: _FakePositionSource(sample),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.lat, 37.5);
      expect(fakeRepo.lastRequest?.lng, 127);
    },
  );

  testWidgets(
    '위치 소스가 null 이면 발신 요청에서 lat·lng 를 생략한다(서버가 최신 수신 좌표로 대체) (F1)',
    (tester) async {
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );

      await tester.pumpWidget(
        _wrap(
          const EmergencyScreen(),
          overridesFor(
            fakeRepo: fakeRepo,
            positionSource: _FakePositionSource(null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.lat, isNull);
      expect(fakeRepo.lastRequest?.lng, isNull);
    },
  );

  // BRIEF-BG2 — Ruling 360 이후 위치 스트림이 기사 운행 화면에서만 열려
  // (`positionSourceProvider.sample()`), 스트림이 없을 때(동승자 단말·송신
  // 두절 기사 단말)는 발신 시점에 1회만 좌표를 측정해 보완한다.
  testWidgets(
    '스트림 좌표가 없으면(sample() null) 1회 측정 좌표를 요청에 싣는다 (BG2)',
    (tester) async {
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );
      final onceSample = PositionSample(
        lat: 37.6,
        lng: 127.1,
        recordedAt: DateTime(2026, 9, 12, 8, 59, 55),
      );
      final fakeSource = _FakePositionSource(null, onceSample: onceSample);

      await tester.pumpWidget(
        _wrap(
          const EmergencyScreen(),
          overridesFor(fakeRepo: fakeRepo, positionSource: fakeSource),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.lat, 37.6);
      expect(fakeRepo.lastRequest?.lng, 127.1);
      expect(fakeSource.sampleOnceCallCount, 1);
    },
  );

  testWidgets(
    '1회 측정이 실패(null)해도 좌표 없이 발신은 그대로 진행한다 (BG2)',
    (tester) async {
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );
      // onceSample 을 안 주면 sampleOnce() 는 null 을 낸다 — 제한 시간 초과·
      // 권한 거부와 같은 결과(호출부 관점에서는 구별할 필요가 없다).
      final fakeSource = _FakePositionSource(null);

      await tester.pumpWidget(
        _wrap(
          const EmergencyScreen(),
          overridesFor(fakeRepo: fakeRepo, positionSource: fakeSource),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.lat, isNull);
      expect(fakeRepo.lastRequest?.lng, isNull);
      expect(fakeRepo.raiseCallCount, 1);
      expect(find.textContaining('보냈습니다'), findsOneWidget);
    },
  );

  testWidgets(
    '스트림 좌표가 있으면(sample() 값 있음) 1회 측정을 부르지 않는다 (BG2)',
    (tester) async {
      final fakeRepo = _FakeEmergencyRepository(
        raiseOutcome: Sent(
          EmergencyRaiseResult(
            emergencyId: 'e1',
            raisedAt: raisedAt,
            cancelableUntil: cancelableUntil,
            notified: 1,
          ),
        ),
        list: const EmergencyListResponse(items: []),
      );
      final streamSample = PositionSample(
        lat: 37.5,
        lng: 127,
        recordedAt: DateTime(2026, 9, 12, 8, 59),
      );
      final fakeSource = _FakePositionSource(
        streamSample,
        onceSample: PositionSample(
          lat: 0,
          lng: 0,
          recordedAt: DateTime(2026, 9, 12, 8, 59),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const EmergencyScreen(),
          overridesFor(fakeRepo: fakeRepo, positionSource: fakeSource),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상 알림 보내기'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastRequest?.lat, 37.5);
      expect(fakeRepo.lastRequest?.lng, 127);
      expect(fakeSource.sampleOnceCallCount, 0);
    },
  );

  testWidgets('측정을 기다리는 동안 두 번째 탭은 새 발신을 만들지 않는다 (BG2)', (
    tester,
  ) async {
    // 1회 측정이 끝나기 전까지는 버튼이 다시 그려지기 전이라(pump 없이
    // 연속 탭) onPressed 가 아직 살아 있는 옛 위젯을 그대로 다시 호출할 수
    // 있다 — `_submit` 자체의 재진입 가드가 없으면 두 번째 호출도 끝까지
    // 진행해 중복 발신이 나간다.
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: cancelableUntil,
          notified: 1,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );
    final completer = Completer<PositionSample?>();
    final fakeSource = _FakePositionSource(null, onceCompleter: completer);

    await tester.pumpWidget(
      _wrap(
        const EmergencyScreen(),
        overridesFor(fakeRepo: fakeRepo, positionSource: fakeSource),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.tap(find.text('비상 알림 보내기'));

    completer.complete(null);
    await tester.pumpAndSettle();

    expect(fakeRepo.raiseCallCount, 1);
  });

  testWidgets('발신이 통신 두절로 큐에 쌓이면 대기 안내를 보여준다', (tester) async {
    // §1.7 M-06 — sendOrQueue 가 Queued 를 돌려주는 경우(UF-E-07).
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: const Queued<EmergencyRaiseResult>(),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('처리되지 않았습니다 · 대기 중'), findsOneWidget);
  });

  testWidgets('비상이 큐에 쌓이면 학원에 전화하라고 알리고 [학원에 전화]가 학원 번호를 tel: 로 연다 (R46)', (
    tester,
  ) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: const Queued<EmergencyRaiseResult>(),
      list: const EmergencyListResponse(items: []),
    );
    final opened = <Uri>[];

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), [
        ...overridesFor(fakeRepo: fakeRepo),
        academyContactProvider.overrideWith((ref) => '02-555-0101'),
        uriOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('전송 안 됨 — 학원에 전화하세요'), findsOneWidget);
    await tester.tap(find.text('학원에 전화'));
    await tester.pump();

    expect(opened, [Uri(scheme: 'tel', path: '02-555-0101')]);
  });

  testWidgets('학원 번호를 모르면 전화 안내 문구만 보이고 전화 버튼은 없다 (R46)', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: const Queued<EmergencyRaiseResult>(),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('전송 안 됨 — 학원에 전화하세요'), findsOneWidget);
    expect(find.text('학원에 전화'), findsNothing);
  });

  testWidgets('학원 번호가 공백뿐이어도 전화 버튼은 없다 — 걸리지 않는 버튼을 그리지 않는다 (R46)', (
    tester,
  ) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: const Queued<EmergencyRaiseResult>(),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), [
        ...overridesFor(fakeRepo: fakeRepo),
        academyContactProvider.overrideWith((ref) => '  '),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('전송 안 됨 — 학원에 전화하세요'), findsOneWidget);
    expect(find.text('학원에 전화'), findsNothing);
  });

  testWidgets('발신이 서버 거절(403 FORBIDDEN)로 실패하면 단일 사유를 보여준다', (tester) async {
    // §4.15 의 403 은 배치되지 않은 회차·타 학원 회차·존재하지 않는 회차를
    // 한 코드로 묶는다(Ruling 259(b)) — 404 로 분리하지 않는다.
    final fakeRepo = _FakeEmergencyRepository(
      raiseFailure: const ApiFailure(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: '권한 없음',
      ),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('이 회차를 이용할 권한이 없습니다'), findsOneWidget);
    // 존재하지 않는 회차만을 위한 별도 문구는 없다 — 하나로 묶여 있다.
    expect(find.textContaining('찾을 수 없습니다'), findsNothing);
  });

  testWidgets('중복 발신을 막지 않는다 — 연속으로 두 번 보내도 둘 다 성공한다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: cancelableUntil,
          notified: 2,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(fakeRepo.raiseCallCount, 2);
    expect(find.textContaining('보냈습니다'), findsOneWidget);
  });

  testWidgets('취소 가능 창은 서버가 준 cancelable_until 만으로 판단한다', (tester) async {
    // 서버가 짧은 창(발신 후 30초)을 내려줬는데도 클라이언트가 "발신
    // 시각 + 1분" 을 스스로 계산해 취소 버튼을 더 오래 보여주면 안 된다 —
    // 그래서 시계를 45초 뒤로 고정해(30초 창은 지났지만 클라이언트가
    // 임의로 계산한 1분 창 안에는 있는 시각) 버튼이 사라지는지 본다.
    final shortWindow = raisedAt.add(const Duration(seconds: 30));
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: shortWindow,
          notified: 1,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsOneWidget);

    // 시계를 45초 뒤로 되감아 다시 그린다 — Provider override 는 위젯
    // 재생성이 필요하니 pumpWidget 을 다시 호출한다.
    await tester.pumpWidget(
      _wrap(
        const EmergencyScreen(),
        overridesFor(
          fakeRepo: fakeRepo,
          now: raisedAt.add(const Duration(seconds: 45)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsNothing);
  });

  testWidgets('발신 이력이 없으면 빈 상태를 보여준다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      list: const EmergencyListResponse(items: []),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('발신한 비상 알림이 없습니다'), findsOneWidget);
  });

  testWidgets('목록 항목은 각자의 cancelable_until 기준으로 취소 버튼을 보여준다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      list: EmergencyListResponse(
        items: [
          // 취소 창이 아직 열려 있고 미확인 — 취소 버튼이 보여야 한다.
          EmergencyItem(
            emergencyId: 'e1',
            type: EmergencyType.accident,
            raisedAt: raisedAt,
            cancelableUntil: raisedAt.add(const Duration(minutes: 1)),
            acked: false,
          ),
          // 창이 지났음 — 취소 버튼이 없어야 한다.
          EmergencyItem(
            emergencyId: 'e2',
            type: EmergencyType.vehicleFault,
            raisedAt: raisedAt.subtract(const Duration(minutes: 5)),
            cancelableUntil: raisedAt.subtract(const Duration(minutes: 4)),
            acked: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsOneWidget);
    expect(find.text('확인 대기 중'), findsNWidgets(2));
  });

  testWidgets('확인자 이름이 빈 문자열이면 이름 없는 문구 대신 확인됨을 보여준다', (tester) async {
    // acked_by_name 이 빈 문자열('')로 오면 null 과 똑같이 "확인됨" 으로
    // 보여야 한다 — `byName == null` 만 검사하면 이 갈래를 통과해
    // " 님이 확인함"(앞에 빈 칸, 이름 없음)이라는 깨진 문구가 그대로
    // 노출된다. `_statusLabelOf` 는 `byName == null || byName.isEmpty`
    // 로 두 경우를 함께 처리한다.
    final fakeRepo = _FakeEmergencyRepository(
      list: EmergencyListResponse(
        items: [
          EmergencyItem(
            emergencyId: 'e1',
            type: EmergencyType.accident,
            raisedAt: raisedAt,
            cancelableUntil: raisedAt.add(const Duration(minutes: 1)),
            acked: true,
            ackedByName: '',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('확인됨'), findsOneWidget);
    expect(find.text(' 님이 확인함'), findsNothing);
  });

  testWidgets('취소가 창 종료(409)로 실패하면 실패 사유를 보여준다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      cancelFailure: const ApiFailure(
        statusCode: 409,
        code: 'EMERGENCY_CANCEL_WINDOW_CLOSED',
        message: '창 종료',
      ),
      list: EmergencyListResponse(
        items: [
          EmergencyItem(
            emergencyId: 'e1',
            type: EmergencyType.accident,
            raisedAt: raisedAt,
            cancelableUntil: raisedAt.add(const Duration(minutes: 1)),
            acked: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    // 목록이 폼 아래에 있어 화면 밖으로 밀릴 수 있다 — 스크롤해 노출한다.
    await tester.ensureVisible(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('비상 알림 취소 가능 시간(발신 후 1분)이 지났습니다'), findsOneWidget);
    expect(fakeRepo.lastCanceledEmergencyId, 'e1');
  });

  // N-08 — 비상 신고 memo 는 200자까지다(API_SPEC 자유 입력 메모 상한, 넘으면 422).
  // R46-LAST `Ruling 583` — 이 칸은 퇴원 파기 대상 밖이라 입력 단계에서 개인정보를 줄인다.
  testWidgets('상황 메모 칸 아래에 학생 이름·연락처를 적지 말라고 안내한다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: cancelableUntil,
          notified: 1,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );
    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('학생 이름·연락처는 적지 마세요'), findsOneWidget);
  });

  testWidgets('상황 메모 입력칸은 200자에서 멈춘다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      raiseOutcome: Sent(
        EmergencyRaiseResult(
          emergencyId: 'e1',
          raisedAt: raisedAt,
          cancelableUntil: cancelableUntil,
          notified: 1,
        ),
      ),
      list: const EmergencyListResponse(items: []),
    );
    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '가' * 250);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      200,
    );
  });

  // F06-06 — 이력 조회 오류가 `Failure.network(message: …)` 같은 개발용 표기 그대로 화면에 나오면
  // 긴박한 상황에서 뜻을 알 수 없다. 다른 화면과 같이 일반 문구로 바꾼다.
  testWidgets('이력 조회가 실패하면 개발용 표기 대신 알아볼 수 있는 문구를 보여준다', (tester) async {
    final fakeRepo = _FakeEmergencyRepository(
      listFailure: const Failure.network(message: 'SocketException: 연결 거부'),
    );
    await tester.pumpWidget(
      _wrap(const EmergencyScreen(), overridesFor(fakeRepo: fakeRepo)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('이력을 불러오지 못했습니다: 네트워크 상태를 확인해 주세요'),
      findsOneWidget,
    );
    expect(find.textContaining('SocketException'), findsNothing);
  });
}
