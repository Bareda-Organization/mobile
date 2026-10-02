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
  new({this.confirmLinkFailure, this.generateLinkCodeFailure});

  final Failure? confirmLinkFailure;
  final Failure? generateLinkCodeFailure;

  @override
  Future<LinkConfirmResult> confirmLink(String code) async {
    final failure = confirmLinkFailure;
    if (failure != null) return await Future.error(failure);
    return const LinkConfirmResult(studentId: 's-1', name: '홍길동');
  }

  @override
  Future<LinkCodeResult> generateLinkCode() async {
    final failure = generateLinkCodeFailure;
    if (failure != null) return await Future.error(failure);
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

  // N-10(BR-215) — 다시 만들면 이전 코드는 그 자리에서 만료된다. 이미 알려 준 코드를 다시 쓰지 않게 안내한다.
  testWidgets('학생 갈래는 코드를 다시 만들면 이전 코드를 쓸 수 없다고 안내한다', (tester) async {
    await _pumpAsStudent(tester, _StubLinkRepository());

    expect(find.textContaining('이전 코드는 더 이상 쓸 수 없'), findsOneWidget);
  });

  // R32 P8 — 만료 시각이 `2026-09-12 00:00:00.000` 그대로 화면에 나왔다.
  testWidgets('만료 시각을 읽기 쉬운 한국어 날짜로 보여준다', (tester) async {
    await _pumpAsStudent(tester, _StubLinkRepository());

    await tester.tap(find.text('코드 생성하기'));
    await tester.pumpAndSettle();

    expect(find.text('만료 시각: 9월 12일 00:00'), findsOneWidget);
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

  // P2 — FEATURE_SPEC 정책 상수(보호자당 10분에 5회)에 걸려도 응답은
  // LINK_CODE_INVALID 하나뿐이라(코드 실재 노출 방지) 화면이 매번 이
  // 고정 안내를 함께 보여줘 상한에 걸린 학부모가 무한정 재시도하지 않게
  // 한다.
  testWidgets(
    '코드 확인이 LINK_CODE_INVALID 로 실패하면 시도 상한 고정 안내도 함께 보여준다',
    (tester) async {
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

      expect(
        find.text('여러 번 틀리면 10분 동안 입력이 막힙니다 · 계속 안 되면 자녀 앱에서 코드를 다시 발급'),
        findsOneWidget,
      );
    },
  );

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
    // P2 안내는 LINK_CODE_INVALID 전용 — 다른 에러 코드까지 번지면 무관한
    // 상황(이미 연결된 자녀)에도 시도 상한 얘기가 뜬다.
    expect(
      find.text('여러 번 틀리면 10분 동안 입력이 막힙니다 · 계속 안 되면 자녀 앱에서 코드를 다시 발급'),
      findsNothing,
    );
  });
}
