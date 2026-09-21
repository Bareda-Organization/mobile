// 라우터에 등록한 화면에 **갈 길이 있는가**.
//
// ⚠ 2026-09-21 실측 — `liveMap`·`routeDetail`·`settings` 세 화면이 만들어져 있고 검사도
// 있는데 **앱 어디에서도 그리로 이동하지 않았다.** 사양은 진입점을 명시한다 —
// `UF-P-07` "홈 · 실시간 운행 정보 → [지도 진입] → … → [노선 자세히 보기]" ·
// `UF-P-08` "홈 → [알림] → … → [알림 설정]".
//
// 정본이 이미 같은 형태를 판정해 뒀다 — *"도달 못 하는 화면은 없는 것과 같다"*
// (`docs/frontend/IMPLEMENTATION_PLAN.md`, `§2.11` 단말 등록 건).
//
// 이 검사는 **소스에서 센다.** 화면을 띄워 누르는 검사는 각 화면이 따로 갖고 있고,
// 여기서 잡으려는 것은 "연결이 아예 없다" 는 배선 구멍이라 정적 대조가 맞는 수단이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final router = File('lib/app/router.dart').readAsStringSync();

  /// `lib/` 전체에서 실제로 이동을 부르는 곳을 모은다.
  Set<String> navigatedTargets() {
    final targets = <String>{};
    final re = RegExp(r'context\.(?:go|push)\(\s*AppRoutes\.(\w+)');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('router.dart')) continue; // 등록처는 세지 않는다
      for (final m in re.allMatches(f.readAsStringSync())) {
        targets.add(m.group(1)!);
      }
    }
    return targets;
  }

  test('등록한 화면에는 전부 갈 길이 있다', () {
    final registered = RegExp(r'path:\s*AppRoutes\.(\w+)')
        .allMatches(router)
        .map((m) => m.group(1)!)
        .toSet();
    final reached = navigatedTargets()
      // 첫 화면과 계정 상태 리다이렉트는 `router.dart` 의 redirect 가 보낸다 —
      // `context.push` 로 가지 않으므로 여기서 면제한다.
      ..addAll({'home', 'pendingApproval', 'blockedAccount'});

    expect(
      registered.difference(reached),
      isEmpty,
      reason: '만들어 두고 아무도 안 가는 화면이 있다 — 도달 못 하는 화면은 없는 것과 같다',
    );
  });
}
