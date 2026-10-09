import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';

/// Ruling 267(P2 게이트 조건 ②) — `pending` 계정 화면에 심은 단말 등록
/// 패널이 실제로 나타나는지(도달성)와 토글이 실제 등록 호출까지 이어지는지
/// (동작)를 함께 확인한다. 도달성만 보면 "빈 패널이 떠 있을 뿐" 인
/// 사고를 못 잡고, 동작만 보면 "이 화면에서는 애초에 안 보인다" 는
/// 사고를 못 잡는다 — 그래서 두 가지를 각각 별도 테스트로 확인한다.
class _StubAuthRepository implements AuthRepository {
  DeviceRegistrationRequest? registeredWith;
  String? unregisteredToken;
  int logoutCallCount = 0;

  /// `signupStatus` 호출 횟수 — [다시 확인] 이 실제로 서버를 다시 부르는지 본다.
  int signupStatusCalls = 0;

  /// 두 번째 조회부터 이 상태로 응답한다(관리자가 그 사이에 승인·거절한 상황).
  AccountStatus? statusFromSecondCall;

  /// 두 번째 조회부터 네트워크 오류로 실패한다(터널·지하처럼 끊긴 상황).
  bool failFromSecondCall = false;

  /// 학원이 대표 연락처를 등록하지 않은 응답
  /// (`academy_contact: null` — API_SPEC §2.3, Ruling 781).
  bool academyContactMissing = false;

  /// 첫 조회가 돌려줄 상태 — 거절 화면 시험이 쓴다. 두 번째 조회부터는 [statusFromSecondCall] 이다
  /// (재신청하면 서버도 다시 대기로 돌려놓는다).
  AccountStatus firstStatus = AccountStatus.pending;
  String? rejectReason;
  List<AcademySummary> academies = const [];
  String? reappliedWith;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => academies;

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      throw UnimplementedError();

  @override
  Future<SignupStatusResponse> signupStatus() async {
    signupStatusCalls++;
    if (academyContactMissing) {
      // 서버가 보내는 JSON 그대로 읽는다 — 파싱이 null 을 못 받으면 여기서 던진다.
      return SignupStatusResponse.fromJson({
        'status': 'pending',
        'academy': {'name': '바래다학원', 'region': '서울', 'code': 'A-001'},
        'requested_at': '2026-09-01T00:00:00Z',
        'academy_contact': null,
      });
    }
    if (failFromSecondCall && signupStatusCalls > 1) {
      return await Future.error(const Failure.network());
    }
    return SignupStatusResponse(
      status: signupStatusCalls > 1
          ? statusFromSecondCall ?? AccountStatus.pending
          : firstStatus,
      rejectReason: signupStatusCalls > 1 ? null : rejectReason,
      academyName: '바래다학원',
      academyRegion: '서울',
      academyCode: 'A-001',
      requestedAt: DateTime(2026, 9),
      academyContact: '02-000-0000',
    );
  }

  @override
  Future<ReapplyResponse> reapply({required String academyId}) async {
    reappliedWith = academyId;
    return ReapplyResponse(
      status: AccountStatus.pending,
      requestedAt: DateTime(2026, 9),
    );
  }

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

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
  ) async {
    registeredWith = request;
    return DeviceRegistrationResponse(
      deviceId: request.deviceId,
      registeredAt: DateTime(2026, 9, 12),
    );
  }

  @override
  Future<void> unregisterDevice(String token) async {
    unregisteredToken = token;
  }
}

/// `DeviceRegistrationStorage` 는 내부에 `FlutterSecureStorage` 를 들고
/// 있어 시험 환경의 플랫폼 채널을 못 탄다(`fake_token_storage.dart` 와
/// 같은 사정) — 메모리로만 도는 대역으로 바꾼다.
class _FakeDeviceRegistrationStorage extends DeviceRegistrationStorage {
  String? _deviceId;
  String? _token;

  @override
  Future<String> readOrCreateDeviceId() async => _deviceId ??= 'device-1';

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}

/// 문의처를 메모리에 남기는 대역 — 차단 화면이 읽을 값이 실제로 저장되는지 본다(`Ruling 825`).
class _RecordingContactStorage extends AcademyContactStorage {
  String? saved;

  @override
  Future<void> save(String contact) async => saved = contact;
}

Future<void> _pumpPendingApproval(
  WidgetTester tester,
  AuthRepository authRepository, {
  AcademyContactStorage? contactStorage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        if (contactStorage != null)
          academyContactStorageProvider.overrideWithValue(contactStorage),
        deviceRegistrationStorageProvider.overrideWithValue(
          _FakeDeviceRegistrationStorage(),
        ),
      ],
      child: const MaterialApp(home: PendingApprovalScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 화면 밖에 밀린 단추도 스크롤해서 누른다 — 실제 폰의 손가락과 같다.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  // BR-301(Ruling 781) — 학원이 연락처를 등록하지 않아 academy_contact 가 null 이어도 화면이 뜬다.
  testWidgets('학원 문의처가 null 이면 대체 문구를 보여준다', (tester) async {
    final authRepository = _StubAuthRepository()..academyContactMissing = true;
    await _pumpPendingApproval(tester, authRepository);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.text('등록된 문의처 없음'), findsOneWidget);
  });

  testWidgets('학원 문의처가 있으면 그 값을 보여주고 대체 문구는 없다', (tester) async {
    await _pumpPendingApproval(tester, _StubAuthRepository());

    expect(find.text('02-000-0000'), findsOneWidget);
    expect(find.text('등록된 문의처 없음'), findsNothing);
  });

  // R48 Ruling 825 · 827 — 문의처를 기기에 남기고(차단 화면이 쓴다), 번호 모양이 있을 때만 전화 단추를 둔다.
  testWidgets('문의처에 번호가 있으면 학원에 전화 단추가 있고 그 문의처를 기기에 남긴다', (tester) async {
    final storage = _RecordingContactStorage();
    await _pumpPendingApproval(
      tester,
      _StubAuthRepository(),
      contactStorage: storage,
    );

    expect(find.text('전화'), findsOneWidget);
    expect(storage.saved, '02-000-0000');
  });

  testWidgets('문의처가 null 이면 전화 단추가 없고 아무것도 남기지 않는다', (tester) async {
    final storage = _RecordingContactStorage();
    await _pumpPendingApproval(
      tester,
      _StubAuthRepository()..academyContactMissing = true,
      contactStorage: storage,
    );

    expect(find.text('전화'), findsNothing);
    expect(storage.saved, isNull);
  });

  // R32 P9 — 상태를 처음 한 번만 조회해, 관리자가 승인·거절해도 앱을 껐다 켜야 알 수 있었다.
  testWidgets('P9 [상태 다시 확인] 을 누르면 승인 상태를 다시 조회해 화면에 반영한다', (tester) async {
    final authRepository = _StubAuthRepository()
      ..statusFromSecondCall = AccountStatus.rejected;
    await _pumpPendingApproval(tester, authRepository);
    expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);

    await _scrollAndTap(tester, find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(authRepository.signupStatusCalls, 2);
    expect(find.text('가입이 거절되었어요'), findsOneWidget);
  });

  // 승인이 났는데 대기 화면에 남아 있으면 안 된다 — 계정 상태를 갱신해 라우터가 홈으로 보내게 한다.
  testWidgets('P9 다시 확인했더니 승인됐으면 계정 상태를 active 로 바꾼다', (tester) async {
    final authRepository = _StubAuthRepository()
      ..statusFromSecondCall = AccountStatus.active;
    await _pumpPendingApproval(tester, authRepository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PendingApprovalScreen)),
    );
    expect(container.read(currentAccountStatusProvider), isNull);

    await _scrollAndTap(tester, find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(container.read(currentAccountStatusProvider), AccountStatus.active);
  });

  // R46 B2 #20 — 푸시 SDK 가 없어 대기 화면이 한 번만 조회하면 승인이 나도 [상태 다시 확인] 을 눌러야 했다.
  group('R46 주기 재확인', () {
    // 사양(UF-X-02)이 정한 값 — 아래 시험은 이 상수로 시간을 흘리므로 값 자체는 여기서 고정한다.
    test('재조회 간격은 30초다', () {
      expect(pendingStatusPollInterval, const Duration(seconds: 30));
    });

    testWidgets(
      '$pendingStatusPollInterval 마다 조용히 다시 조회하고 승인되면 계정 상태를 active 로 바꾼다',
      (
        tester,
      ) async {
        final authRepository = _StubAuthRepository()
          ..statusFromSecondCall = AccountStatus.active;
        await _pumpPendingApproval(tester, authRepository);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PendingApprovalScreen)),
        );
        expect(authRepository.signupStatusCalls, 1);

        await tester.pump(
          pendingStatusPollInterval - const Duration(seconds: 1),
        );
        expect(
          authRepository.signupStatusCalls,
          1,
          reason: '간격이 지나기 전에는 조회하지 않는다',
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(authRepository.signupStatusCalls, 2);
        expect(
          container.read(currentAccountStatusProvider),
          AccountStatus.active,
        );
      },
    );

    testWidgets('앱이 백그라운드에서 돌아오면 간격을 기다리지 않고 바로 조회한다', (tester) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(authRepository.signupStatusCalls, 2);
    });

    testWidgets('조용한 재확인이 네트워크로 실패해도 보이던 대기 화면을 오류 화면으로 바꾸지 않는다', (
      tester,
    ) async {
      final authRepository = _StubAuthRepository()..failFromSecondCall = true;
      await _pumpPendingApproval(tester, authRepository);

      await tester.pump(pendingStatusPollInterval);
      await tester.pumpAndSettle();

      expect(authRepository.signupStatusCalls, 2);
      expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);
      expect(find.text('상태를 불러오지 못했습니다'), findsNothing);
    });
  });

  testWidgets('가입 승인 대기 화면에 단말 등록 패널이 도달 가능하다', (tester) async {
    await _pumpPendingApproval(tester, _StubAuthRepository());

    expect(find.byType(DeviceRegistrationPanel), findsOneWidget);
  });

  testWidgets('대기 화면의 단말 등록 패널에서 토글하면 registerDevice 가 실제로 호출된다', (
    tester,
  ) async {
    final authRepository = _StubAuthRepository();
    await _pumpPendingApproval(tester, authRepository);

    expect(authRepository.registeredWith, isNull);

    await _scrollAndTap(tester, find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(authRepository.registeredWith, isNotNull);
    expect(authRepository.registeredWith!.platform, isNotEmpty);
  });

  // F2 — `settings_screen.dart` 의 확인 대화를 그대로 재사용하는지 검사한다.
  // 지금 코드는 확인 대화 없이 바로 logout() 을 부른다 — 버튼 라벨
  // 대화의 확정 버튼 라벨('로그아웃하기')은 `find.descendant` 로
  // `BaraedaDialog` 안쪽만 짚는다.
  group('F2 — 로그아웃 확인 대화(P 의 확인 대화 재사용)', () {
    // 로그아웃 버튼은 스크롤 목록 맨 아래라 기본 시험 화면(800x600) 밖에
    // 있다 — `ensureVisible` 로 먼저 스크롤한다.
    Future<void> tapLogoutButton(WidgetTester tester) async {
      final button = find.text('로그아웃');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
    }

    testWidgets('로그아웃하기 버튼을 누르면 확인 대화가 뜨고, 아직 요청을 보내지 않는다', (
      tester,
    ) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();

      expect(find.byType(BaraedaDialog), findsOneWidget);
      expect(authRepository.logoutCallCount, 0);
    });

    testWidgets('확인 대화에서 취소하면 요청을 보내지 않는다', (tester) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(BaraedaDialog), findsNothing);
      expect(authRepository.logoutCallCount, 0);
    });

    testWidgets('확인 대화에서 확정하면 요청이 실행된다', (tester) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BaraedaDialog),
          matching: find.text('로그아웃하기'),
        ),
      );
      await tester.pumpAndSettle();

      expect(authRepository.logoutCallCount, 1);
    });
  });

  // R48 시안 `pending*` — 상태를 칩 + 큰 제목 + 3단계 진행 막대로 먼저 보여 준다.
  group('R48 승인 대기 · 거절 구성', () {
    testWidgets('승인 대기 — 대기 칩 · 확인 중 제목 · 단계 셋 · 30초 자동 확인 안내', (tester) async {
      await _pumpPendingApproval(tester, _StubAuthRepository());

      expect(find.text('승인 대기'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{2}:\d{2} 확인')), findsOneWidget);
      expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);
      expect(find.textContaining('30초마다 저절로 확인해요'), findsOneWidget);
      expect(find.text('신청 접수'), findsOneWidget);
      expect(find.text('학원 확인'), findsOneWidget);
      expect(find.text('진행 중'), findsOneWidget);
      expect(find.text('사용 시작'), findsOneWidget);
      // 상태는 칩 하나로 말한다 — 옛 "현재 상태" 줄은 없다.
      expect(find.text('현재 상태'), findsNothing);
      expect(find.text('가입이 거절되었어요'), findsNothing);
      expect(find.text('학원 다시 골라 재신청'), findsNothing);
    });

    testWidgets('거절 — 사유 띠 · 마지막 단계가 "거절" · 주 행동은 아래 고정 단추', (tester) async {
      final repository = _StubAuthRepository()
        ..firstStatus = AccountStatus.rejected
        ..rejectReason = '재원생 명단에서 자녀 이름을 찾을 수 없습니다.';
      await _pumpPendingApproval(tester, repository);

      expect(find.text('거절됨'), findsOneWidget);
      expect(find.text('가입이 거절되었어요'), findsOneWidget);
      expect(find.text('학원이 남긴 사유'), findsOneWidget);
      expect(find.text('재원생 명단에서 자녀 이름을 찾을 수 없습니다.'), findsOneWidget);
      expect(find.text('거절'), findsOneWidget);
      // 거절 카드에는 "12:14 확인" 이 없다 — 대기 카드에만 마지막 확인 시각이 붙는다.
      expect(find.textContaining(RegExp(r'\d{2}:\d{2} 확인')), findsNothing);
      expect(find.text('사용 시작'), findsNothing);
      expect(find.text('가입 승인을 기다리고 있어요'), findsNothing);
      expect(
        find.ancestor(
          of: find.text('학원 다시 골라 재신청'),
          matching: find.byType(StickyActionBar),
        ),
        findsOneWidget,
      );
    });

    group('재신청 — 학원을 고른 뒤 확인 대화상자 한 단계(UF-X-02)', () {
      const academy = AcademySummary(
        id: 'a-2',
        name: '하늘수학 상동분원',
        region: '부천시 원미구',
        code: 'A1204',
      );

      Future<_StubAuthRepository> pumpToPickedAcademy(
        WidgetTester tester,
      ) async {
        final repository = _StubAuthRepository()
          ..firstStatus = AccountStatus.rejected
          ..rejectReason = '사유'
          ..academies = [academy];
        await _pumpPendingApproval(tester, repository);
        await tester.tap(find.text('학원 다시 골라 재신청'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '하늘');
        await tester.tap(find.text('검색'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('하늘수학 상동분원'));
        await tester.pumpAndSettle();
        return repository;
      }

      testWidgets('학원을 고르기 전에는 [재신청하기] 가 꺼져 있다', (tester) async {
        final repository = _StubAuthRepository()
          ..firstStatus = AccountStatus.rejected
          ..rejectReason = '사유';
        await _pumpPendingApproval(tester, repository);
        await tester.tap(find.text('학원 다시 골라 재신청'));
        await tester.pumpAndSettle();

        expect(find.text('다니는 학원을 다시 골라 주세요'), findsOneWidget);
        expect(
          tester
              .widget<BaraedaButton>(
                find.widgetWithText(BaraedaButton, '재신청하기'),
              )
              .onPressed,
          isNull,
        );
      });

      testWidgets('[재신청하기] 는 곧바로 보내지 않고 확인 대화상자를 먼저 연다', (tester) async {
        final repository = await pumpToPickedAcademy(tester);

        await tester.tap(find.widgetWithText(BaraedaButton, '재신청하기'));
        await tester.pumpAndSettle();

        expect(find.byType(BaraedaDialog), findsOneWidget);
        expect(find.text('하늘수학 상동분원으로 다시 신청할까요?'), findsOneWidget);
        expect(repository.reappliedWith, isNull, reason: '확인 전에는 서버에 보내지 않는다');
      });

      testWidgets('대화상자에서 [학원 다시 고르기] 를 누르면 보내지 않고 닫힌다', (tester) async {
        final repository = await pumpToPickedAcademy(tester);
        await tester.tap(find.widgetWithText(BaraedaButton, '재신청하기'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('학원 다시 고르기'));
        await tester.pumpAndSettle();

        expect(find.byType(BaraedaDialog), findsNothing);
        expect(repository.reappliedWith, isNull);
      });

      testWidgets('대화상자에서 [재신청하기] 를 누르면 그 학원으로 보낸다', (tester) async {
        final repository = await pumpToPickedAcademy(tester);
        await tester.tap(find.widgetWithText(BaraedaButton, '재신청하기'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byType(BaraedaDialog),
            matching: find.text('재신청하기'),
          ),
        );
        await tester.pumpAndSettle();

        expect(repository.reappliedWith, 'a-2');
      });
    });
  });
}
