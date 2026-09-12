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

/// 이월 2-2 — API_SPEC §3.2·§3.3·§3.4 에러 코드 4종
/// (`STUDENT_NOT_FOUND`·`ALREADY_LINKED`·`LINK_CODE_INVALID`·
/// `LINK_REQUEST_NOT_FOUND`)이 이 화면에서 실제로 다른 문구로 갈리는지
/// 확인한다.
class _StubLinkRepository implements LinkRepository {
  _StubLinkRepository({
    Failure? requestLinkFailure,
    Failure? confirmLinkFailure,
    Failure? generateLinkCodeFailure,
  }) : _requestLinkFailure = requestLinkFailure,
       _confirmLinkFailure = confirmLinkFailure,
       _generateLinkCodeFailure = generateLinkCodeFailure;

  final Failure? _requestLinkFailure;
  final Failure? _confirmLinkFailure;
  final Failure? _generateLinkCodeFailure;

  @override
  Future<LinkRequestResult> requestLink(String studentLoginId) async {
    final failure = _requestLinkFailure;
    if (failure != null) throw failure;
    return LinkRequestResult(
      linkRequestId: 'link-1',
      expiresAt: DateTime(2026, 9, 12),
    );
  }

  @override
  Future<LinkConfirmResult> confirmLink(String code) async {
    final failure = _confirmLinkFailure;
    if (failure != null) throw failure;
    return const LinkConfirmResult(studentId: 's-1', name: '홍길동');
  }

  @override
  Future<LinkCodeResult> generateLinkCode() async {
    final failure = _generateLinkCodeFailure;
    if (failure != null) throw failure;
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

void main() {
  testWidgets('연결 요청이 STUDENT_NOT_FOUND 로 실패하면 안내 문구를 보여준다', (tester) async {
    await _pumpAsParent(
      tester,
      _StubLinkRepository(
        requestLinkFailure: const Failure.api(
          statusCode: 404,
          code: 'STUDENT_NOT_FOUND',
          message: '학생을 찾을 수 없습니다',
        ),
      ),
    );

    await tester.enterText(find.byType(BaraedaInput), 's-login-1');
    await tester.tap(find.text('연결 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('해당 아이디의 학생을 찾을 수 없습니다'), findsOneWidget);
  });

  testWidgets('연결 요청이 ALREADY_LINKED 로 실패하면 안내 문구를 보여준다', (tester) async {
    await _pumpAsParent(
      tester,
      _StubLinkRepository(
        requestLinkFailure: const Failure.api(
          statusCode: 409,
          code: 'ALREADY_LINKED',
          message: '이미 연결됨',
        ),
      ),
    );

    await tester.enterText(find.byType(BaraedaInput), 's-login-1');
    await tester.tap(find.text('연결 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('이미 연결된 자녀입니다'), findsOneWidget);
  });

  testWidgets('코드 확인이 LINK_CODE_INVALID 로 실패하면 안내 문구를 보여준다', (tester) async {
    await _pumpAsParent(
      tester,
      _StubLinkRepository(
        confirmLinkFailure: const Failure.api(
          statusCode: 400,
          code: 'LINK_CODE_INVALID',
          message: '코드가 올바르지 않음',
        ),
      ),
    );

    // 1단계: 연결 요청 성공 → 코드 입력 단계로 진입.
    await tester.enterText(find.byType(BaraedaInput), 's-login-1');
    await tester.tap(find.text('연결 요청 보내기'));
    await tester.pumpAndSettle();

    // 2단계: 코드 입력 → 실패. `BaraedaCodeInput` 자체는 `EditableText` 가
    // 아니라 내부에 숨겨 둔 `TextField` 하나가 실제 입력을 받는다
    // (code_input.dart 참고).
    await tester.enterText(
      find.descendant(
        of: find.byType(BaraedaCodeInput),
        matching: find.byType(TextField),
      ),
      '000000',
    );
    // `enterText` 가 트리거하는 `onChanged`→`setState` 는 다음 프레임에야
    // 반영된다 — 여기서 pump 하지 않으면 "연결 완료하기" 버튼이 여전히 옛
    // `_code`(빈 문자열) 기준으로 빌드돼 비활성 상태라 탭이 무시된다.
    await tester.pump();
    await tester.tap(find.text('연결 완료하기'));
    await tester.pumpAndSettle();

    expect(find.text('코드가 올바르지 않거나 만료됐습니다'), findsOneWidget);
  });

  testWidgets('코드 생성이 LINK_REQUEST_NOT_FOUND 로 실패하면 안내 문구를 보여준다', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkRepositoryProvider.overrideWithValue(
            _StubLinkRepository(
              generateLinkCodeFailure: const Failure.api(
                statusCode: 404,
                code: 'LINK_REQUEST_NOT_FOUND',
                message: '대기 중인 요청 없음',
              ),
            ),
          ),
          currentUserRoleProvider.overrideWith((ref) => UserRole.student),
        ],
        child: const MaterialApp(home: ChildLinkScreen()),
      ),
    );

    await tester.tap(find.text('코드 생성하기'));
    await tester.pumpAndSettle();

    expect(
      find.text('대기 중인 연결 요청이 없습니다. 학부모에게 먼저 요청을 보내달라고 해주세요'),
      findsOneWidget,
    );
  });
}
