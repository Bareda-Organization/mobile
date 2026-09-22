import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';
import 'package:parent_app/features/child_link/domain/link_repository.dart';
import 'package:parent_app/features/child_link/presentation/child_link_screen.dart';

/// Ruling 324 — 연결 요청(§3.2) 단계 폐지 후 2단계(코드 생성 §3.3 · 코드 입력
/// §3.4)만 남은 화면을 검사한다. 에러 코드는 §3.4 의 2종
/// (`LINK_CODE_INVALID`·`ALREADY_LINKED`)이 이 화면에서 실제로 다른 문구로
/// 갈리는지 확인한다.
class _StubLinkRepository implements LinkRepository {
  _StubLinkRepository({this.confirmLinkFailure, this.generateLinkCodeFailure});

  final Failure? confirmLinkFailure;
  final Failure? generateLinkCodeFailure;

  @override
  Future<LinkConfirmResult> confirmLink(String code) async {
    final failure = confirmLinkFailure;
    if (failure != null) return Future.error(failure);
    return const LinkConfirmResult(studentId: 's-1', name: '홍길동');
  }

  @override
  Future<LinkCodeResult> generateLinkCode() async {
    final failure = generateLinkCodeFailure;
    if (failure != null) return Future.error(failure);
    return LinkCodeResult(code: '123456', expiresAt: DateTime(2026, 9, 12));
  }
}

Future<void> _pumpAsParent(WidgetTester tester, LinkRepository repository) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
      ],
      child: const MaterialApp(home: ChildLinkScreen()),
    ),
  );
}

Future<void> _pumpAsStudent(WidgetTester tester, LinkRepository repository) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) => UserRole.student),
      ],
      child: const MaterialApp(home: ChildLinkScreen()),
    ),
  );
}

void main() {
  testWidgets('학생 갈래는 코드 생성 버튼 하나로 코드가 화면에 뜬다', (tester) async {
    await _pumpAsStudent(tester, _StubLinkRepository());

    await tester.tap(find.text('코드 생성하기'));
    await tester.pumpAndSettle();

    expect(find.text('123456'), findsOneWidget);
  });

  testWidgets('학부모 갈래는 코드 입력만으로 연결이 완료된다', (tester) async {
    await _pumpAsParent(tester, _StubLinkRepository());

    await tester.enterText(
      find.descendant(
        of: find.byType(BaraedaCodeInput),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.text('연결 완료하기'));
    await tester.pumpAndSettle();

    expect(find.text('홍길동 자녀 연결이 완료됐습니다.'), findsOneWidget);
  });

  testWidgets('코드 확인이 LINK_CODE_INVALID 로 실패하면 안내 문구를 보여준다', (tester) async {
    await _pumpAsParent(
      tester,
      _StubLinkRepository(
        confirmLinkFailure: const Failure.api(
          statusCode: 403,
          code: 'LINK_CODE_INVALID',
          message: '코드가 올바르지 않음',
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(BaraedaCodeInput),
        matching: find.byType(TextField),
      ),
      '000000',
    );
    await tester.pump();
    await tester.tap(find.text('연결 완료하기'));
    await tester.pumpAndSettle();

    expect(find.text('코드가 올바르지 않거나 만료됐습니다'), findsOneWidget);
  });

  testWidgets('코드 생성이 실패하면 서버 메시지를 그대로 보여준다', (tester) async {
    await _pumpAsStudent(
      tester,
      _StubLinkRepository(
        generateLinkCodeFailure: const Failure.api(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: '잠시 후 다시 시도해 주세요',
        ),
      ),
    );

    await tester.tap(find.text('코드 생성하기'));
    await tester.pumpAndSettle();

    expect(find.text('잠시 후 다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('코드 확인이 ALREADY_LINKED 로 실패하면 안내 문구를 보여준다', (tester) async {
    await _pumpAsParent(
      tester,
      _StubLinkRepository(
        confirmLinkFailure: const Failure.api(
          statusCode: 409,
          code: 'ALREADY_LINKED',
          message: '이미 연결됨',
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(BaraedaCodeInput),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.text('연결 완료하기'));
    await tester.pumpAndSettle();

    expect(find.text('이미 연결된 자녀입니다'), findsOneWidget);
  });
}
