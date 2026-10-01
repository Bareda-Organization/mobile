import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

import '../../support/fake_token_storage.dart';

/// R46 B2 #22 배선 — ① 모든 REST 요청이 연결 감시를 지난다 ② 끊기면 앱 맨 위에 한 줄이 뜬다
/// ③ 끊긴 동안 홈은 카드 위에 "이전 정보입니다" 띠를 또 나열하지 않는다(맨 위 한 줄이 그 말을 한다).
class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
  );

  @override
  void close({bool force = false}) {}
}

final _child = Student(
  studentId: 's-1',
  name: '첫째',
  linkedAt: DateTime(2026, 9),
);

void main() {
  test('앱의 API 클라이언트로 나간 요청이 연결 실패하면 끊김 상태가 된다', () async {
    final container = ProviderContainer(
      overrides: [tokenStorageProvider.overrideWithValue(FakeTokenStorage())],
    );
    addTearDown(container.dispose);
    final dio = container.read(apiClientProvider).dio
      ..httpClientAdapter = _Adapter();

    await expectLater(
      dio.get<dynamic>('http://localhost/x'),
      throwsA(isA<DioException>()),
    );

    expect(container.read(networkStatusProvider).isOffline, isTrue);
  });

  testWidgets('끊기면 앱 어느 화면이든 맨 위에 한 줄이 뜬다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          networkStatusProvider.overrideWith(
            (ref) => NetworkStatusNotifier(
              initial: const NetworkStatus(isOffline: true),
            ),
          ),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('네트워크 연결이 끊겼습니다'), findsOneWidget);
  });

  // 실기기(iOS 시뮬레이터)에서 표시줄 위 상태 표시줄 영역이 검게 비고 글자에 노란 밑줄이 떴다 —
  // 앱 틀은 `Scaffold` 밖이라 `Material` 도 배경도 없었다. 위젯 시험이 `Scaffold` 안에서만 그려 못 잡았다.
  testWidgets('끊김 표시줄은 Material 위에 그려지고 상태 표시줄 영역까지 같은 색이다', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(top: 141); // 논리 47(노치 높이)
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          networkStatusProvider.overrideWith(
            (ref) => NetworkStatusNotifier(
              initial: const NetworkStatus(isOffline: true),
            ),
          ),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.text('네트워크 연결이 끊겼습니다');
    final material = find.ancestor(
      of: label,
      matching: find.byType(Material),
    );
    expect(material, findsWidgets, reason: 'Material 이 없으면 글자에 노란 밑줄이 뜬다');
    // 가장 가까운 Material 이 화면 맨 위(상태 표시줄 영역)부터 글자 아래까지 칠한다.
    final bar = tester.getRect(material.first);
    expect(bar.top, 0);
    expect(tester.getTopLeft(label).dy, greaterThanOrEqualTo(47));
    expect(bar.bottom, greaterThan(tester.getBottomLeft(label).dy));
  });

  group('홈', () {
    Future<void> pumpHome(
      WidgetTester tester, {
      required bool isOffline,
    }) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            networkStatusProvider.overrideWith(
              (ref) => NetworkStatusNotifier(
                initial: NetworkStatus(isOffline: isOffline),
              ),
            ),
            roleCapabilitiesProvider.overrideWithValue(
              RoleCapabilities.of(UserRole.parent),
            ),
            myStudentsProvider.overrideWith((ref) async => [_child]),
            // 첫 조회는 성공(마지막 데이터가 생김), 다시 받을 때 실패한다.
            runsForStudentProvider.overrideWith((ref, id) async {
              calls++;
              if (calls > 1) throw Exception('x');
              return const <StudentRun>[];
            }),
            changeRequestsProvider.overrideWith(
              (ref, id) async =>
                  const ChangeRequestPage(items: [], pendingCount: 0),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // 당겨서 새로고침 — 두 번째 조회가 실패한다.
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
    }

    testWidgets('연결 중에 갱신이 실패하면 이전 정보 띠가 뜬다', (tester) async {
      await pumpHome(tester, isOffline: false);
      expect(find.textContaining('이전 정보입니다'), findsOneWidget);
    });

    testWidgets('끊긴 동안 갱신이 실패해도 카드 위 띠를 또 만들지 않는다', (tester) async {
      await pumpHome(tester, isOffline: true);
      expect(find.textContaining('이전 정보입니다'), findsNothing);
    });
  });
}
