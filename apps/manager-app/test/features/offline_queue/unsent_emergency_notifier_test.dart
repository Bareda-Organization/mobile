import 'dart:async';

import 'package:baraeda_core/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';

import '../../support/fake_academy_contact_store.dart';

/// 첫 쓰기는 예외를 던지고 이후는 저장하는 저장소.
/// 읽기는 [readGate] 가 풀어 줄 때까지 끝나지 않는다(없으면 곧바로 [saved]).
/// [failReads] 번까지는 읽기가 예외를 던진다.
class _FlakyStore implements UnsentEmergencyStore {
  new({
    this.readGate,
    this.failFirstWrite = false,
    this.failReads = 0,
    this.saved,
  });

  UnsentEmergency? saved;
  final Completer<UnsentEmergency?>? readGate;
  bool failFirstWrite;
  int failReads;

  @override
  Future<UnsentEmergency?> read() {
    if (failReads > 0) {
      failReads--;
      return Future.error(StateError('저장소 읽기 실패'));
    }
    return readGate?.future ?? Future.value(saved);
  }

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
        clockProvider.overrideWithValue(FixedClock(lastAt)),
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

  group('경합', () {
    // a — 읽기가 실패한 채 새 건을 쓰면 기기에 있던 앞 건수가 새 건 하나로 덮였다.
    test('a: 저장소 읽기가 한 번 실패해도 앞 건수 위에 새 건을 더해 쓴다', () async {
      final store = _FlakyStore(
        saved: UnsentEmergency(count: 2, lastAt: DateTime(2026, 10, 10)),
        failReads: 1,
      );
      final container = open(store);
      await pumpEventQueue();

      unawaited(
        container
            .read(unsentEmergencyProvider.notifier)
            .add(count: 1, contact: null),
      );
      await pumpEventQueue();

      expect(store.saved?.count, 3);
      expect(container.read(unsentEmergencyProvider)?.count, 3);
    });

    test('a: 읽기가 계속 실패하면 앞 저장분을 덮어쓰지 않는다(메모리 안내는 뜬다)', () async {
      final prior = UnsentEmergency(count: 2, lastAt: DateTime(2026, 10, 10));
      final store = _FlakyStore(saved: prior, failReads: 99);
      final container = open(store);
      await pumpEventQueue();

      unawaited(
        container
            .read(unsentEmergencyProvider.notifier)
            .add(count: 1, contact: null),
      );
      await pumpEventQueue();

      expect(store.saved, prior);
      expect(container.read(unsentEmergencyProvider)?.count, 1);
    });

    // b — 읽기가 3초 상한을 넘겨 쓰기가 먼저 나간 뒤, 읽기가 그 쓰기를 담은 값을 돌려주면 같은 건이 두 번 셌다.
    testWidgets('b: 읽기가 3초 상한을 넘겨 늦게 끝나도 같은 건을 두 번 세지 않는다', (tester) async {
      final gate = Completer<UnsentEmergency?>();
      final store = _FlakyStore(
        readGate: gate,
        saved: UnsentEmergency(count: 2, lastAt: DateTime(2026, 10, 10)),
      );
      final container = open(store);

      unawaited(
        container
            .read(unsentEmergencyProvider.notifier)
            .add(count: 1, contact: null),
      );
      await tester.pump(const Duration(seconds: 4));
      // 늦은 읽기가 끝나는 순간 저장소에 있는 값을 돌려준다(쓰기가 나갔다면 그 값을 담는다).
      gate.complete(store.saved);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      // 앞 건수 2 + 새 건 1 — 새 건이 두 번 세어지지도(4) 앞 건수가 덮이지도(1) 않는다.
      expect(container.read(unsentEmergencyProvider)?.count, 3);
      expect(store.saved?.count, 3);
    });

    // 시작 때 읽기가 실패한 채 [확인] 하면 다음 저장 재시도가 기기 저장분을 다시 띄운다는 우려.
    // 확인한 건이 되살아나는지(결함)와 한 번도 보이지 않은 기기 저장분이 보이는지(옳은 동작)를 가른다.
    test('⑦: 시작 때 읽기가 실패한 채 확인해도 확인한 건은 돌아오지 않고 기기에 있던 앞 건수만 알린다', () async {
      final store = _FlakyStore(
        saved: UnsentEmergency(count: 2, lastAt: DateTime(2026, 10, 10)),
        // 시작 읽기 + add 의 저장 재시도 읽기가 실패하고, 확인 뒤 저장 재시도에서 읽힌다.
        failReads: 2,
      );
      final container = open(store);
      final notifier = container.read(unsentEmergencyProvider.notifier);
      await pumpEventQueue();

      unawaited(notifier.add(count: 1, contact: null));
      await pumpEventQueue();
      expect(container.read(unsentEmergencyProvider)?.count, 1);
      notifier.dismiss(1);
      await pumpEventQueue();

      // 확인한 1건은 돌아오지 않는다 — 남는 2건은 이 실행에서 한 번도 보이지 않은 기기 저장분이다.
      expect(container.read(unsentEmergencyProvider)?.count, 2);
      expect(store.saved?.count, 2);

      // 그 2건도 확인하면 기기 저장분까지 비어 다시 뜨지 않는다.
      notifier.dismiss(2);
      await pumpEventQueue();
      expect(container.read(unsentEmergencyProvider), isNull);
      expect(store.saved, isNull);
    });

    // c — 확인을 누른 안내(건수 2)를 지우는 사이 새 건이 들어오면 새 건까지 지워졌다.
    test('c: 확인은 사용자가 본 건수만 지우고 그 사이 들어온 새 건은 남긴다', () async {
      final store = _FlakyStore();
      final container = open(store);
      final notifier = container.read(unsentEmergencyProvider.notifier);

      unawaited(notifier.add(count: 2, contact: null));
      await pumpEventQueue();
      final seen = container.read(unsentEmergencyProvider)!;
      unawaited(notifier.add(count: 1, contact: null));
      notifier.dismiss(seen.count);
      await pumpEventQueue();

      expect(container.read(unsentEmergencyProvider)?.count, 3 - seen.count);
      expect(store.saved?.count, 3 - seen.count);
    });
  });
}
