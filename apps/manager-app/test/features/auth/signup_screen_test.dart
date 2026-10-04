import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/signup_screen.dart';

const _academy = AcademySummary(
  id: 'a1',
  name: '하늘수학학원 부천중동점',
  region: '경기 부천시 원미구',
  code: 'HN-0012',
);

/// 학원 검색만 대답하는 가짜 저장소 — 가입 요청은 이 시험의 관심사가 아니다.
class _FakeAuthRepository implements AuthRepository {
  SignupRequest? signupRequest;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [
    _academy,
  ];

  @override
  Future<SignupResponse> signup(SignupRequest request) async {
    signupRequest = request;
    throw UnimplementedError('이 시험은 가입 요청을 보내지 않는다');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<_FakeAuthRepository> pumpScreen(WidgetTester tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: SignupScreen()),
      ),
    );
    return repository;
  }

  BaraedaButton submit(WidgetTester tester) => tester.widget<BaraedaButton>(
    find.widgetWithText(BaraedaButton, '가입 신청하기'),
  );

  Future<void> type(WidgetTester tester, int field, String text) async {
    await tester.enterText(find.byType(TextField).at(field), text);
    await tester.pump();
  }

  Future<void> pickAcademy(WidgetTester tester) async {
    await type(tester, 4, '하늘');
    await tester.ensureVisible(find.text('검색하기'));
    await tester.tap(find.text('검색하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_academy.displayLabel).last);
    await tester.pumpAndSettle();
  }

  testWidgets('역할 칸 아래에 두 역할이 하는 일을 한 줄로 알린다', (tester) async {
    await pumpScreen(tester);

    expect(
      find.text('버스기사 — 운행 시작 · 승하차지 도착 처리. 동승자 — 학생 승차 · 하차 처리.'),
      findsOneWidget,
    );
  });

  testWidgets('아이디와 비밀번호 칸에 한도 안내가 있다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('50자 이하'), findsOneWidget);
    expect(find.text('영문 72자 · 한글 24자까지'), findsOneWidget);
  });

  // M16 — 꺼진 단추는 무엇이 비었는지 단추 아래에 적는다.
  testWidgets('아직 비운 항목을 단추 아래에 순서대로 알리고 단추는 꺼져 있다(M16)', (tester) async {
    await pumpScreen(tester);

    expect(submit(tester).onPressed, isNull);
    expect(
      find.text('아직 채우지 않은 항목 · 아이디 · 비밀번호 · 이름 · 연락처 · 학원'),
      findsOneWidget,
    );
  });

  testWidgets('칸을 채울수록 안내에서 그 항목이 빠진다', (tester) async {
    await pumpScreen(tester);

    await type(tester, 0, 'driverA2');
    await type(tester, 1, 'password');

    expect(find.text('아직 채우지 않은 항목 · 이름 · 연락처 · 학원'), findsOneWidget);
  });

  testWidgets('공백만 넣은 이름은 채운 것으로 치지 않는다', (tester) async {
    await pumpScreen(tester);

    await type(tester, 2, '   ');

    expect(
      find.textContaining('아직 채우지 않은 항목 · 아이디 · 비밀번호 · 이름'),
      findsOneWidget,
    );
  });

  testWidgets('다 채우면 단추가 켜지고 승인 안내로 바뀌며 요청에 값이 실린다', (tester) async {
    final repository = await pumpScreen(tester);

    await type(tester, 0, 'driverA2');
    await type(tester, 1, 'password');
    await type(tester, 2, '박정훈');
    await type(tester, 3, '010-4821-7730');
    await pickAcademy(tester);

    expect(submit(tester).onPressed, isNotNull);
    expect(find.text('신청하면 학원 관계자가 확인한 뒤 승인해요.'), findsOneWidget);
    expect(find.textContaining('아직 채우지 않은 항목'), findsNothing);
    // 고른 학원은 이름 · 지역 · 코드로 카드에 보인다.
    expect(find.text('하늘수학학원 부천중동점'), findsOneWidget);
    expect(find.text('경기 부천시 원미구 · 학원 코드 HN-0012'), findsOneWidget);
    expect(repository.signupRequest, isNull, reason: '누르기 전에는 요청이 없다');
  });

  testWidgets('비밀번호가 72바이트를 넘으면 이유를 보이고 가입 단추가 꺼진다', (tester) async {
    await pumpScreen(tester);

    await type(tester, 0, 'driverA2');
    await type(tester, 1, '가' * 25);
    await type(tester, 2, '박정훈');
    await type(tester, 3, '010-4821-7730');
    await pickAcademy(tester);

    expect(find.text('비밀번호는 72바이트(한글 24자) 이하여야 해요'), findsOneWidget);
    expect(submit(tester).onPressed, isNull);
  });
}
