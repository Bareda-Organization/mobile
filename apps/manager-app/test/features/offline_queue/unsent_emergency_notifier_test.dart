import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';

import '../../support/fake_academy_contact_store.dart';

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 첫 쓰기는 예외를 던지고 이후는 저장하는 저장소.
/// 읽기는 [readGate] 가 풀어 줄 때까지 끝나지 않는다(없으면 곧바로 [saved]).
class _FlakyStore implements UnsentEmergencyStore {
  new({this.readGate, this.failFirstWrite = false});

  UnsentEmergency? saved;
  final Completer<UnsentEmergency?>? readGate;
  bool failFirstWrite;

  @override
  Future<UnsentEmergency?> read() => readGate?.future ?? Future.value(saved);

  @override
  Future<void> write(UnsentEmergency value) async {
    if (failFirstWrite) {
      failFirstWrite = false;
      throw StateError('저장소 쓰기 실패');
    }
    saved = value;
  }

  @override
  Future<void> clear() async => saved = null;
}

/// 비상 신고 기기 저장 안내의 작업 줄(Ruling 886) — 저장소가 실패하거나 응답하지 않아도 메모리 안내와 이후 작업이 산다.
void main() {
  final lastAt = DateTime(2026, 10, 11, 9, 30);

  ProviderContainer open(_FlakyStore store) {
    final container = ProviderContainer(
      overrides: [
        unsentEmergencyStoreProvider.overrideWithValue(store),
        academyContactStoreProvider.overrideWithValue(
          FakeAcademyContactStore('032-000-1100'),
        ),
        clockProvider.overrideWithValue(_FixedClock(lastAt)),
      ],
    );
    addTearDown(container.dispose);
    // 구독해 두어 provider 가 살아 있게 한다.
    container.listen(unsentEmergencyProvider, (_, _) {});
    return container;
  }

  test('저장소 쓰기가 예외를 던져도 다음 add 가 반영된다', () async {
    final store = _FlakyStore(failFirstWrite: true);
    final container = open(store);

    unawaited(
      container
          .read(unsentEmergencyProvider.notifier)
          .add(count: 1, contact: null),
    );
    await pumpEventQueue();
    unawaited(
      container
          .read(unsentEmergencyProvider.notifier)
          .add(count: 1, contact: null),
    );
    await pumpEventQueue();

    expect(container.read(unsentEmergencyProvider)?.count, 2);
    expect(store.saved?.count, 2);
  });

  test('저장소 읽기가 끝나지 않아도 add 뒤 안내가 바로 뜬다', () async {
    final store = _FlakyStore(readGate: Completer<UnsentEmergency?>());
    final container = open(store);

    unawaited(
      container
          .read(unsentEmergencyProvider.notifier)
          .add(count: 1, contact: null),
    );

    expect(container.read(unsentEmergencyProvider)?.count, 1);
  });

  test('읽기가 늦게 끝나도 건수는 저장분에 그 사이 add 를 더한 값이다', () async {
    final gate = Completer<UnsentEmergency?>();
    final store = _FlakyStore(readGate: gate);
    final container = open(store);

    unawaited(
      container
          .read(unsentEmergencyProvider.notifier)
          .add(count: 1, contact: null),
    );
    await pumpEventQueue();
    gate.complete(
      UnsentEmergency(count: 2, lastAt: DateTime(2026, 10, 10), contact: '010'),
    );
    await pumpEventQueue();

    final merged = container.read(unsentEmergencyProvider);
    expect(merged?.count, 3);
    expect(merged?.lastAt, lastAt);
    expect(store.saved?.count, 3);
  });
}
