import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';

/// 건수와 마지막 시각을 기기에 남기고 사용자가 [dismiss] 할 때만 지우는 안내의 공통 뼈대(Ruling 886 · 892).
/// 안내(`state`)는 곧바로 바꾸고 저장소 읽기 · 쓰기만 한 줄로 이어 붙인다 — 저장소가 실패하거나 응답하지 않아도
/// 이번 실행의 안내와 뒤따르는 작업이 막히지 않는다.
///
/// 경합 규칙 —
/// ①시작 때 저장분을 읽지 못했으면 한 번 더 읽고, 그래도 못 읽으면 앞 건수를 덮을 수 있어 쓰지 않는다
/// ②읽기가 끝나기 전에는 쓰지 않는다(상한을 넘긴 늦은 읽기가 우리 쓰기를 담아 와 같은 건이 두 번 세지는
/// 일을 막는다. 읽기가 끝나면 합친 값을 쓴다)
/// ③[dismiss] 는 사용자가 본 건수만 지운다 — 그 사이 들어온 새 건과 읽기가 끝나기 전의 저장분은 남는다.
abstract class PersistedTallyNotifier extends Notifier<UnsentEmergency?> {
  /// 쓰기 줄이 시작 때 저장분 읽기를 기다리는 최대 시간 — 넘으면 이번 쓰기는 건너뛰고(읽기가 끝나는 대로 쓴다) 줄을 푼다.
  static const _loadLimit = Duration(seconds: 3);

  var _tail = Future<void>.value();

  /// 시작 때 저장분 읽기 — 끝나면 `null`.
  Future<void>? _loading;

  /// 저장분을 한 번이라도 읽어 합쳤는가.
  var _loaded = false;

  /// 읽기가 끝나기 전이라 쓰기를 건너뛴 적이 있는가.
  var _writeSkipped = false;

  /// 이 안내를 남기는 기기 저장소.
  UnsentEmergencyStore get store;

  /// 저장하려는 안내에 번호가 없을 때 채울 번호 — 기본은 없다.
  Future<String?> fallbackContact() async => null;

  @override
  UnsentEmergency? build() {
    _loading = _load().whenComplete(() => _loading = null);
    return null;
  }

  /// 시작 때 저장분을 합친다 — 읽기가 끝나기 전에 쓰기를 건너뛰었으면 합친 값을 지금 쓴다.
  Future<void> _load() async {
    if (!await _mergeSaved() || !ref.mounted) return;
    if (_writeSkipped && state != null) unawaited(_enqueue(_persist));
  }

  /// 저장분을 읽어 지금 안내([state])와 합친다 — 그 사이 [add] 한 건수가
  /// 줄거나 두 번 더해지지 않게 더한다. 읽지 못하면 `false`.
  Future<bool> _mergeSaved() async {
    final UnsentEmergency? saved;
    try {
      saved = await store.read();
    } on Object catch (error) {
      debugPrint('기기에 남긴 안내를 읽지 못했어요: $error');
      return false;
    }
    if (!ref.mounted) return false;
    _loaded = true;
    if (saved == null) return true;
    final current = state;
    state = current == null
        ? saved
        : UnsentEmergency(
            count: saved.count + current.count,
            lastAt: current.lastAt,
            contact: current.contact ?? saved.contact,
          );
    return true;
  }

  /// [count] 건을 더한다 — 건수를 더하고 시각을 지금으로, 번호는 [contact] 를 우선한다(없으면 앞서 남긴 번호 ·
  /// [fallbackContact]). 돌려주는 Future 는 기기 저장이 끝나면 완료된다 —
  /// 대기열을 지우기 전에 기다려야 하는 호출부가 쓴다.
  Future<void> add({required int count, required String? contact}) {
    final previous = state;
    state = UnsentEmergency(
      count: (previous?.count ?? 0) + count,
      lastAt: ref.read(clockProvider).now(),
      contact: contact ?? previous?.contact,
    );
    return _enqueue(_persist);
  }

  /// 사용자가 [seen] 건짜리 안내를 확인했다 — 그 건수만 지우고 기기의 저장분도 그만큼 줄인다.
  void dismiss(int seen) {
    final current = state;
    if (current == null) return;
    final remaining = current.count - seen;
    state = remaining > 0
        ? UnsentEmergency(
            count: remaining,
            lastAt: current.lastAt,
            contact: current.contact,
          )
        : null;
    unawaited(_enqueue(_persist));
  }

  /// 지금 안내를 기기에 쓴다(실행 시점의 값 — 앞선 쓰기가 밀려도 마지막 값이 남는다). 안내가 없으면 저장분을 지운다.
  Future<void> _persist() async {
    await _loading?.timeout(_loadLimit, onTimeout: () {});
    if (!ref.mounted) return;
    if (_loading != null) {
      _writeSkipped = true;
      return;
    }
    if (!_loaded && !await _mergeSaved()) return;
    if (!ref.mounted) return;
    var current = state;
    if (current == null) {
      await store.clear();
      return;
    }
    if (current.contact == null) {
      final contact = await fallbackContact();
      if (!ref.mounted) return;
      current = state;
      if (current == null) return;
      if (current.contact == null && contact != null) {
        current = UnsentEmergency(
          count: current.count,
          lastAt: current.lastAt,
          contact: contact,
        );
        state = current;
      }
    }
    await store.write(current);
  }

  /// 작업 하나가 실패해도 줄이 끊기지 않는다 — 오류는 기록만 남기고 다음 작업으로 넘어간다.
  Future<void> _enqueue(Future<void> Function() job) {
    return _tail = _tail.then((_) => job()).catchError((Object error) {
      debugPrint('기기에 남기는 안내 저장 작업이 실패했어요: $error');
    });
  }
}

/// 서버가 거절해 지워진 비상 신고의 기기 저장 안내 — 사용자가 [확인] 할 때까지 앱을 끄거나 로그아웃해도 남는다
/// (Ruling 886).
final NotifierProvider<UnsentEmergencyNotifier, UnsentEmergency?>
unsentEmergencyProvider =
    NotifierProvider<UnsentEmergencyNotifier, UnsentEmergency?>(
      UnsentEmergencyNotifier.new,
    );

class UnsentEmergencyNotifier extends PersistedTallyNotifier {
  @override
  UnsentEmergencyStore get store => ref.read(unsentEmergencyStoreProvider);

  /// 번호가 없으면 기기에 저장된 학원 번호로 채운다.
  @override
  Future<String?> fallbackContact() async {
    try {
      return await ref.read(academyContactStoreProvider).read();
    } on Object {
      return null;
    }
  }
}

/// 서버가 거절해 지워진 승하차·도착 처리의 기기 저장 안내 — **건수와 마지막 시각만** 남긴다(학생 이름은 남기지 않는다 ·
/// Ruling 892). 사용자가 [확인] 할 때까지 앱을 껐다 켜도 남는다.
final NotifierProvider<DroppedTallyNotifier, UnsentEmergency?>
droppedTallyProvider = NotifierProvider<DroppedTallyNotifier, UnsentEmergency?>(
  DroppedTallyNotifier.new,
);

class DroppedTallyNotifier extends PersistedTallyNotifier {
  @override
  UnsentEmergencyStore get store => ref.read(droppedTallyStoreProvider);
}
