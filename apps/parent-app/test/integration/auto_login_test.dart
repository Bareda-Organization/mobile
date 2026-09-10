import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

import '../support/fake_token_storage.dart';

/// `localhost:8080` 을 실제로 때리는 계약 시험 — F2 목표 표 5항(재실행 시
/// 자동 로그인). `flutter test` 가 도는 동안 로컬 백엔드가 떠 있어야 하고,
/// 없으면 `setUpAll` 헬스체크가 이 그룹 전체를 환경 문제로 건너뛴다
/// (`real_backend_auth_test.dart` 와 같은 구조).
///
/// "재실행" 자체는 `flutter test` 로 흉내 낼 수 없다(진짜 프로세스 재시작이
/// 필요) — 대신 `authBootstrapProvider` 가 실제로 검증하는 조건, 즉 "이미
/// 저장돼 있던 refresh 토큰으로 `/me` 를 불러 role·status 를 되살리고 로그인
/// 화면을 건너뛴다"를 `FakeTokenStorage.seedRefreshToken` 으로 재현한다.
/// 진짜 프로세스 재시작 확인은 iOS 시뮬레이터 실행으로 별도 수행한다(보고서
/// § 실측 참고).
void main() {
  const baseUrl = 'http://localhost:8080/api/v1';
  late bool backendReachable;

  setUpAll(() async {
    // `flutter test` 는 `TestWidgetsFlutterBinding` 초기화 시점에
    // `HttpOverrides.global` 을 "항상 400 을 응답하고 소켓은 아예 열지
    // 않는" 대역으로 바꿔 둔다(§ 실제 네트워크 실수 방지 안전장치, 위젯
    // 시험이 실수로 진짜 서버를 때리지 않게). 그래서 이 시험처럼 **의도적으로**
    // 실제 백엔드를 때리려면 그 대역을 이 파일이 도는 동안만 꺼야 한다 —
    // 꺼 두지 않으면 서버가 떠 있어도 항상 400/빈 본문이 와서 "서버 다운"과
    // 구별되지 않는다(manager-app 과 같은 원인, 원인 규명 과정은 보고서 §
    // 실측 참고).
    HttpOverrides.global = null;
    final probe = Dio(BaseOptions(baseUrl: baseUrl));
    try {
      await probe.get<dynamic>(
        '/academies/search',
        queryParameters: {'q': '바래다'},
      );
      backendReachable = true;
    } on DioException catch (e) {
      backendReachable = e.response != null;
    } finally {
      probe.close();
    }
  });

  testWidgets(
    '목표 5 — 저장된 refresh 토큰이 있으면 재실행 시 로그인 화면을 건너뛰고 '
    '홈 화면으로 간다 (실제 로그인 1회로 진짜 토큰을 발급받아 시드)',
    (tester) async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8080 백엔드 미기동');
        return;
      }

      // `testWidgets` 본문은 기본적으로 가짜 시계(zone) 안에서 돈다 —
      // `Dio` 가 쓰는 실제 소켓 I/O 는 그 가짜 시계로는 완료 신호를 못 받아
      // 무기한 멎는다(manager-app 1차 시도에서 8분 넘게 멈춰 실측).
      // `tester.runAsync` 로 실제 시간이 흐르는 영역으로 나가야 진짜 백엔드
      // 호출이 끝난다.
      await tester.runAsync(() async {
        // 진짜 refresh 토큰을 얻는 것 자체는 이번 시험의 관심사가 아니라
        // 준비 단계라, 임시 대역(FakeTokenStorage)에 실제 로그인 결과를 받아
        // 그 문자열만 꺼내 쓴다 — 플랫폼 채널을 타는 실제 `TokenStorage` 를
        // 여기서 또 만들 필요가 없다(`FakeTokenStorage` 도 `TokenStorage` 라
        // `AuthApi` 생성자에 그대로 넣을 수 있다).
        //
        // ⚠ 맨 `Dio()` 가 아니라 `ApiClient` 를 거쳐야 한다 — 서버 응답은
        // `{success, data, message}` 봉투에 싸여 오고 그 봉투를 벗기는 것은
        // `ApiClient` 가 붙이는 `_EnvelopeInterceptor` 뿐이다. 벗기지 않은
        // 채로 `LoginResponse.fromJson` 에 넘기면 `json['access_token']` 이
        // 항상 `null`이라 타입 캐스트에서 죽는다(manager-app 에서 실제로
        // 처음 이 실수를 했다).
        final throwawayStorage = FakeTokenStorage();
        final bootstrapClient = ApiClient(
          tokenStorage: throwawayStorage,
          baseUrl: baseUrl,
        );
        final bootstrapAuth = AuthApi(
          dio: bootstrapClient.dio,
          tokenStorage: throwawayStorage,
        );
        final login = await bootstrapAuth.login(
          loginId: 'studentA4',
          password: 'password',
        );
        final realRefreshToken = login.refreshToken;
        expect(
          realRefreshToken,
          isNotNull,
          reason: 'app 클라이언트 로그인은 refresh 토큰을 항상 발급해야 한다',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(
                FakeTokenStorage(seedRefreshToken: realRefreshToken),
              ),
            ],
            child: const BaraedaParentApp(),
          ),
        );

        // `pumpAndSettle` 은 못 쓴다 — 로딩 중 화면(`app.dart`)이 그리는
        // `CircularProgressIndicator` 자체가 끝나지 않는 애니메이션이라
        // "더 그릴 프레임이 없다" 는 조건이 영원히 안 온다. 대신 진짜
        // `/me` 호출이 끝나 로그인/홈 화면 둘 중 하나가 나타날 때까지
        // 일정 간격으로 `pump` 만 반복한다.
        //
        // ⚠ `tester.pump(Duration)` 은 **가짜 시계만 흘려보낸다** — 이
        // 콜백은 `runAsync` 가 만든 진짜 시간대에서 도는데, `pump` 내부의
        // `_currentFakeAsync!.elapse(duration)` 은 가짜 큐만 비우고 진짜
        // 소켓 I/O 가 쓰는 진짜 이벤트 루프에는 실제로 아무 시간도 주지
        // 않는다(앱 내부의 `authBootstrapProvider` 가 여는 두 번째 실제
        // HTTP 왕복 — 무토큰 `/me` 401 → `/auth/refresh` → 재시도 — 이
        // 여기 해당한다). 그래서 진짜 `Future.delayed` 로 진짜 시간을
        // 흘려보낸 *뒤에* `pump()` 로 그 결과를 화면에 반영해야 한다
        // (manager-app 에서 실제로 이걸 빼먹었을 때는 50회를 돌아도
        // 로딩 화면에서 한 발짝도 못 나갔다).
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          final settled =
              find.byType(HomeScreen).evaluate().isNotEmpty ||
              find.byType(LoginScreen).evaluate().isNotEmpty;
          if (settled) break;
        }
      });

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );
}
