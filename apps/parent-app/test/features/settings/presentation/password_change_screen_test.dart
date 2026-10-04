import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/settings/presentation/password_change_screen.dart';

/// P2 게이트 조건 ① — `password_change_screen.dart:33`(정확한 줄은 그
/// 사이 다른 편집으로 이동했으나 대상은 `_submit()` 첫머리의
/// `isEmpty` 빈 입력 가드) 를 없애면 빈 문자열로도
/// `AuthRepository.changePassword` 가 호출된다. 이 테스트는 입력을 전혀
/// 하지 않고 제출 버튼만 눌러 그 호출이 실제로 막히는지 본다.
class _CountingAuthRepository implements AuthRepository {
  int changePasswordCallCount = 0;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [];

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      throw UnimplementedError();

  @override
  Future<SignupStatusResponse> signupStatus() => throw UnimplementedError();

  @override
  Future<ReapplyResponse> reapply({required String academyId}) =>
      throw UnimplementedError();

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCallCount++;
  }

  @override
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) => throw UnimplementedError();

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

/// FE-R2 목표 10 — 제출 중 표시. `changePassword` 가 끝나는 시점을 이
/// `Completer` 로 직접 쥐고 있어야 "제출 중" 인 프레임을 관측할 수 있다
/// (`pumpAndSettle` 로는 그 순간을 지나쳐 버린다).
class _StallingAuthRepository implements AuthRepository {
  final changePasswordCalled = Completer<void>();
  final _changePasswordResult = Completer<void>();

  // 실패로 끝낸다 — 성공 경로는 `_submitting` 을 다시 내리지 않고 router
  // 리다이렉트로 화면을 통째로 치워 버리므로(클래스 문서 참고), 이 화면
  // 하나만 올린 시험에서는 "표시기가 사라진다" 를 관측할 방법이 없다.
  void failChangePassword() =>
      _changePasswordResult.completeError(const Failure.network());

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [];

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      throw UnimplementedError();

  @override
  Future<SignupStatusResponse> signupStatus() => throw UnimplementedError();

  @override
  Future<ReapplyResponse> reapply({required String academyId}) =>
      throw UnimplementedError();

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  // 화면은 changePassword 성공 뒤 곧바로 logout() 을 부른다(클래스 문서
  // 참고, 실패해도 무시한다) — 여기서 던지면 이 시험의 관심사(로딩 표시)와
  // 무관한 예외로 실패하므로 성공으로 둔다.
  @override
  Future<void> logout() async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalled.complete();
    await _changePasswordResult.future;
  }

  @override
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) => throw UnimplementedError();

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

void main() {
  testWidgets('두 입력란이 비어 있으면 제출을 눌러도 changePassword 를 호출하지 않는다', (
    tester,
  ) async {
    final repository = _CountingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(
      repository.changePasswordCallCount,
      0,
      reason: '빈 입력값으로는 API 호출 자체가 나가면 안 된다',
    );
  });

  // F05-11 — API_SPEC §2.8 새 비밀번호는 UTF-8 72바이트 이하(한글 24자).
  // 넘으면 서버 422 를 기다리지 않는다.
  testWidgets('F05-11 새 비밀번호가 72바이트를 넘으면 이유를 보이고 요청을 보내지 않는다', (tester) async {
    final repository = _CountingAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'current-pw');
    await tester.enterText(find.byType(TextField).at(1), '가' * 25); // 75바이트
    await tester.pump();
    expect(find.textContaining('72바이트'), findsOneWidget);

    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(repository.changePasswordCallCount, 0);
  });

  testWidgets('F05-11 한글 24자(72바이트)는 통과한다', (tester) async {
    final repository = _CountingAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'current-pw');
    await tester.enterText(find.byType(TextField).at(1), '가' * 24);
    await tester.pump();

    expect(find.textContaining('72바이트'), findsNothing);
  });

  // FE-R2 목표 10 — 버튼 비활성화뿐 아니라 로딩 표시기도 함께 뜨는지 본다.
  // `changePassword` 응답이 오기 전 프레임을 `pump()` 로 붙잡아 확인한다.
  testWidgets('제출 중에는 진행 표시기가 뜨고, 끝나면 사라진다', (tester) async {
    final repository = _StallingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'current-pw');
    await tester.enterText(find.byType(TextField).at(1), 'new-pw');
    // 두 칸을 다 채우면 다음 프레임에 단추가 켜진다 — 그 프레임을 그린 뒤 누른다.
    await tester.pump();
    await tester.tap(find.text('변경하기'));
    // API 호출이 나갔지만 아직 응답이 오지 않은 시점까지만 프레임을 민다.
    await tester.pump();
    await repository.changePasswordCalled.future;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.failChangePassword();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // R48 시안 `password*` — 꺼진 단추에는 왜 꺼졌는지가 단추 바로 아래에 있다(막다른 길을 만들지 않는다).
  group('R48 꺼진 [변경하기] 의 이유', () {
    test('이유는 무엇이 비었는지에 따라 달라진다 — 다 채웠으면 이유가 없다', () {
      expect(
        passwordChangeBlockedReason(current: '', next: ''),
        '현재 비밀번호와 새 비밀번호를 입력하면 눌러요',
      );
      expect(
        passwordChangeBlockedReason(current: 'old-pw', next: ''),
        '새 비밀번호를 입력하면 눌러요',
      );
      expect(
        passwordChangeBlockedReason(current: '', next: 'new-pw'),
        '현재 비밀번호를 입력하면 눌러요',
      );
      expect(
        passwordChangeBlockedReason(current: 'old-pw', next: '가' * 25),
        '새 비밀번호를 한도 안으로 줄이면 눌러요',
      );
      expect(
        passwordChangeBlockedReason(current: 'old-pw', next: 'new-pw'),
        isNull,
      );
    });

    Future<void> pump(WidgetTester tester, {bool forced = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_CountingAuthRepository()),
            if (forced) mustChangePasswordProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(home: PasswordChangeScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    BaraedaButton changeButton(WidgetTester tester) => tester
        .widget<BaraedaButton>(find.widgetWithText(BaraedaButton, '변경하기'));

    testWidgets('처음에는 꺼져 있고 이유가 단추 아래에 보인다', (tester) async {
      await pump(tester);

      expect(changeButton(tester).onPressed, isNull);
      expect(find.text('현재 비밀번호와 새 비밀번호를 입력하면 눌러요'), findsOneWidget);
    });

    testWidgets('채우는 만큼 이유가 바뀌고, 다 채우면 켜지며 이유가 사라진다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField).at(0), 'old-pw');
      await tester.pump();
      expect(find.text('새 비밀번호를 입력하면 눌러요'), findsOneWidget);
      expect(changeButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(1), 'new-pw');
      await tester.pump();
      expect(changeButton(tester).onPressed, isNotNull);
      expect(find.textContaining('입력하면 눌러요'), findsNothing);
    });

    testWidgets('새 비밀번호가 한도를 넘으면 꺼지고 줄이라는 이유가 붙는다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField).at(0), 'old-pw');
      await tester.enterText(find.byType(TextField).at(1), '가' * 25);
      await tester.pump();

      expect(changeButton(tester).onPressed, isNull);
      expect(find.text('새 비밀번호를 한도 안으로 줄이면 눌러요'), findsOneWidget);
    });
  });

  group('R48 비밀번호 변경 구성', () {
    Future<void> pump(WidgetTester tester, {bool forced = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_CountingAuthRepository()),
            if (forced) mustChangePasswordProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(home: PasswordChangeScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('입력 전에 "모든 기기에서 로그아웃" 경고와 길이 한도 안내를 보여 준다', (tester) async {
      await pump(tester);

      expect(find.text('바꾸면 모든 기기에서 로그아웃돼요.'), findsOneWidget);
      expect(find.textContaining('새 비밀번호로 다시 로그인해 주세요'), findsOneWidget);
      expect(find.text('영문 72자 · 한글 24자까지'), findsOneWidget);
      expect(find.text('로그아웃'), findsNothing, reason: '강제 변경이 아니면 로그아웃 줄이 없다');
    });

    testWidgets('두 입력란 모두 낭독기가 "필수" 를 읽는다(Ruling 833)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('현재 비밀번호 필수'), findsOneWidget);
      expect(find.bySemanticsLabel('새 비밀번호 필수'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('강제 변경 — 뒤로 가기가 없고 임시 비밀번호 안내와 로그아웃만 있다', (tester) async {
      await pump(tester, forced: true);

      expect(find.text('임시 비밀번호로 로그인했어요'), findsOneWidget);
      expect(find.text('바꾸면 모든 기기에서 로그아웃돼요.'), findsNothing);
      expect(find.byTooltip('뒤로'), findsNothing);
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('두 입력란 모두 비밀번호 보기 단추가 있고 칸마다 따로 바뀐다', (tester) async {
      await pump(tester);
      bool obscured(int index) => tester
          .widget<TextField>(find.byType(TextField).at(index))
          .obscureText;

      expect(obscured(0), isTrue);
      expect(obscured(1), isTrue);

      // 현재 비밀번호 칸의 단추만 눌러도 새 비밀번호 칸은 그대로 가려져 있다.
      await tester.tap(find.bySemanticsLabel('비밀번호 보기').first);
      await tester.pump();
      expect(obscured(0), isFalse);
      expect(obscured(1), isTrue);
    });
  });
}
