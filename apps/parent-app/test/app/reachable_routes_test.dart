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

  /// `lib/` 전체에서 화면을 가리키는 곳을 모은다 — 경로 정의 파일 두 개는 뺀다.
  ///
  /// ⚠ **`context.push(...)` 호출만 세지 않는다.** 이동 대상을 변수에 담는 자리가 있어
  /// (`destination = canOperateRun ? driveMode : roster`) 호출 형태로 세면 멀쩡한 배선을
  /// 도달 불가로 잘못 보고한다. 그래서 **언급 자체**를 센다 — 느슨한 대신 **오탐이 없다**.
  /// 이 검사가 잡으려는 것은 "연결이 아예 없다" 는 구멍이지 잘못된 연결이 아니다.
  Set<String> referencedTargets() {
    final targets = <String>{};
    final re = RegExp(r'AppRoutes\.(\w+)');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('router.dart') ||
          f.path.endsWith('app_routes.dart')) {
        continue; // 등록처·정의처는 세지 않는다
      }
      for (final m in re.allMatches(f.readAsStringSync())) {
        // 주소를 만들어 주는 도우미(`routeDetailFor`)는 그 경로를 가리킨 것으로 센다.
        targets.add(m.group(1)!.replaceFirst(RegExp(r'For$'), ''));
      }
    }
    return targets;
  }

  test('등록한 화면에는 전부 갈 길이 있다', () {
    final registered = RegExp(
      r'path:\s*AppRoutes\.(\w+)',
    ).allMatches(router).map((m) => m.group(1)!).toSet();
    final reached = referencedTargets()
      // 첫 화면과 계정 상태 리다이렉트는 `router.dart` 의 redirect 가 보낸다 —
      // `context.push` 로 가지 않으므로 여기서 면제한다.
      // 아래 탭(홈 · 일정 · 알림 · 설정)은 `AppShell` 의 탭 막대가 인덱스로 간다 — 경로 문자열을 언급하지
      // 않으므로 여기서 면제하고, 칸이 실제로 있는지는 `app_shell_test.dart` 가 본다.
      ..addAll({
        'home',
        'schedule',
        'notifications',
        'settings',
        'pendingApproval',
        'blockedAccount',
      });

    expect(
      registered.difference(reached),
      isEmpty,
      reason: '만들어 두고 아무도 안 가는 화면이 있다 — 도달 못 하는 화면은 없는 것과 같다',
    );
  });
}
