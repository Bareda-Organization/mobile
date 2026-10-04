import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 1초마다 뛰는 신호 — 남은 시간 글자를 다시 그리는 데 쓴다(비상 알림 취소 가능 시간 등).
///
/// 화면이 이 신호를 `watch` 하는 동안에만 타이머가 돈다. 시험은 이 provider 를 빈 스트림이나 손으로 밀어 주는
/// 스트림으로 덮어, 시계가 흐르지 않는 상태에서 `pumpAndSettle` 이 끝나게 한다.
final StreamProvider<int> countdownTickProvider =
    StreamProvider.autoDispose<int>(
      (ref) =>
          Stream<int>.periodic(const Duration(seconds: 1), (count) => count),
    );
