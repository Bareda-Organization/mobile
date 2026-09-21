import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_auto_sync.dart';

import 'support/fake_token_storage.dart';

/// 앱이 로그인 화면으로 뜨는지만 확인하는 자리표시 스모크 시험 —
/// 실제 화면 검증은 이번 범위가 아니다.
///
/// `tokenStorageProvider` 를 [FakeTokenStorage] 로 덮어써야 한다 — 실제
/// `TokenStorage`(`flutter_secure_storage`)는 `flutter_test` 에 플랫폼
/// 채널이 없어 `authBootstrapProvider` 의 `readRefreshToken()` 호출이
/// 응답을 못 받고, `app.dart` 가 그 로딩 동안 그리는 indeterminate
/// `CircularProgressIndicator` 때문에 `pumpAndSettle` 이 시간 초과한다
/// (`parent_app` 과 같은 이유).
void main() {
  testWidgets('로그인 전에는 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    // M-06 자동 동기화가 **실제 앱 트리에 걸려 있는지** — 위젯을 만들어 두고
    // 아무 데도 끼우지 않으면 큐는 영영 자동으로 나가지 않는다
    // (`test/app/reachable_routes_test.dart` 와 같은 형태의 구멍).
    expect(find.byType(OfflineQueueAutoSync), findsOneWidget);
  });
}
