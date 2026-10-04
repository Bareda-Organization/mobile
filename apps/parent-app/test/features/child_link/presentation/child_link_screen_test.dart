import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
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

  /// `confirmLink` 로 받은 코드 — 6자리를 다 채웠을 때만 서버로 가는지 본다.
  final confirmed = <String>[];

  @override
  Future<LinkConfirmResult> confirmLink(String code) async {
    confirmed.add(code);
    final failure = confirmLinkFailure;
    if (failure != null) return await Future.error(failure);
    return const LinkConfirmResult(studentId: 's-1', name: '홍길동');
  }

  @override
  Future<LinkCodeResult> generateLinkCode() async {
    final failure = generateLinkCodeFailure;
    if (failure != null) return await Future.error(failure);
    // 아직 살아 있는 코드여야 "살아 있는 모양" 을 본다.
    // 만료 모양은 `child_link_code_actions_test` 가 본다.
    return LinkCodeResult(code: '123456', expiresAt: DateTime(2100));
  }
}

final _linkedAt = DateTime(2026);

/// 연결이 끝난 뒤 화면이 서버에서 다시 받는 자녀 목록 — 방금 연결한 `홍길동` 이 맨 끝에 있다.
List<Student> _students() => [
  Student(studentId: 's-0', name: '김하준', linkedAt: _linkedAt),
  Student(studentId: 's-1', name: '홍길동', linkedAt: _linkedAt),
];

Future<void> _pumpAsParent(WidgetTester tester, LinkRepository repository) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
        myStudentsProvider.overrideWith((ref) async => _students()),
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

/// 학부모 코드 입력 칸의 숨은 입력창 — 글자를 넣는다.
Finder _codeField() => find.descendant(
  of: find.byType(BaraedaCodeInput),
  matching: find.byType(TextField),
);

BaraedaButton _button(WidgetTester tester, String label) =>
    tester.widget<BaraedaButton>(find.widgetWithText(BaraedaButton, label));

const _invalidNotice = '여러 번 틀리면 10분 동안 입력이 막혀요. 계속 안 되면 자녀 앱에서 코드를 다시 만들어요.';

void main() {
  group('학생 — 부모님과 연결할 코드', () {
    testWidgets('처음에는 코드 없이 안내만 있다 — 코드는 [코드 만들기] 를 눌러야 만들어진다', (tester) async {
      await _pumpAsStudent(tester, _StubLinkRepository());

      expect(find.text('부모님과 연결할 코드를 만들어요'), findsOneWidget);
      expect(find.text('코드는 한 번만 쓸 수 있어요'), findsOneWidget);
      expect(find.text('만든 뒤 일정 시간이 지나면 만료돼요'), findsOneWidget);
      // N-10(BR-215) — 다시 만들면 이전 코드는 그 자리에서 만료된다. 이미 알려 준 코드를 다시 쓰지 않게 안내한다.
      expect(find.text('새로 만들면 이전 코드는 쓸 수 없어요'), findsOneWidget);
      expect(find.byType(BaraedaCodeDisplay), findsNothing);
      // 들어오자마자 자동으로 만들지 않는다 — 부모에게 이미 준 코드가 무효가 된다.
      expect(find.text('코드 만들기'), findsOneWidget);
    });

    testWidgets('[코드 만들기] 를 누르면 코드가 화면에 뜬다', (tester) async {
      await _pumpAsStudent(tester, _StubLinkRepository());

      await tester.tap(find.text('코드 만들기'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('연결 코드 1 2 3 4 5 6'), findsOneWidget);
      expect(find.text('부모님께 알려 줄 코드예요'), findsOneWidget);
      expect(find.text('코드만 복사'), findsOneWidget);
      expect(find.text('안내 문구 복사'), findsOneWidget);
      expect(find.text('새 코드 만들기'), findsOneWidget);
      // 부모님께 보낼 문구가 미리 보인다 — 코드가 어디에 입력하는 것인지 함께 간다.
      expect(find.textContaining('바래다 자녀 연결 코드 123456'), findsOneWidget);
    });

    // R32 P8 — 만료 시각이 `2026-09-12 00:00:00.000` 그대로 화면에 나왔다.
    testWidgets('만료 시각을 읽기 쉬운 시각으로 보여준다', (tester) async {
      await _pumpAsStudent(tester, _StubLinkRepository());

      await tester.tap(find.text('코드 만들기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('만료 시각 00:00'), findsOneWidget);
      expect(find.textContaining('2026-09-12'), findsNothing);
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

      await tester.tap(find.text('코드 만들기'));
      await tester.pumpAndSettle();

      expect(find.text('잠시 후 다시 시도해 주세요'), findsOneWidget);
    });
  });

  group('학부모 — 자녀가 만든 코드를 입력', () {
    testWidgets('연결 순서 3단계를 먼저 보이고, 6칸이 비었으면 [연결 완료하기] 가 꺼져 있다', (
      tester,
    ) async {
      await _pumpAsParent(tester, _StubLinkRepository());

      expect(find.text('자녀가 만든 코드를 입력해요'), findsOneWidget);
      expect(find.text('자녀 앱을 열어요'), findsOneWidget);
      expect(find.text('만들어진 코드 6자리를 받아요'), findsOneWidget);
      expect(find.text('아래에 입력해요'), findsOneWidget);
      final input = tester.widget<BaraedaCodeInput>(
        find.byType(BaraedaCodeInput),
      );
      expect(input.length, 6);
      expect(_button(tester, '연결 완료하기').onPressed, isNull);
      // 꺼진 단추에는 이유가 붙는다.
      expect(find.text('연결 코드 6자리를 모두 입력하면 눌러요'), findsOneWidget);
    });

    testWidgets('5자리까지는 꺼져 있고 6자리를 채우면 켜진다 — 그때 이유가 사라진다', (tester) async {
      final repository = _StubLinkRepository();
      await _pumpAsParent(tester, repository);

      await tester.enterText(_codeField(), '12345');
      await tester.pump();
      expect(_button(tester, '연결 완료하기').onPressed, isNull);
      await tester.tap(find.text('연결 완료하기'));
      await tester.pump();
      expect(repository.confirmed, isEmpty, reason: '5자리로는 서버에 가지 않는다');

      await tester.enterText(_codeField(), '123456');
      await tester.pump();
      expect(_button(tester, '연결 완료하기').onPressed, isNotNull);
      expect(find.text('연결 코드 6자리를 모두 입력하면 눌러요'), findsNothing);
    });

    testWidgets('연결이 끝나면 완료 화면이 뜨고 방금 연결한 자녀가 목록에 표시된다', (tester) async {
      final repository = _StubLinkRepository();
      await _pumpAsParent(tester, repository);

      await tester.enterText(_codeField(), '123456');
      await tester.pump();
      await tester.tap(find.text('연결 완료하기'));
      await tester.pumpAndSettle();

      expect(repository.confirmed, ['123456']);
      expect(find.text('홍길동 연결이 끝났어요'), findsOneWidget);
      expect(find.text('이제 홍길동의 버스 위치와 알림을 볼 수 있어요.'), findsOneWidget);
      // 이미 연결돼 있던 자녀는 "연결됨", 방금 연결한 자녀만 "방금 연결".
      expect(find.text('김하준'), findsOneWidget);
      expect(find.text('연결됨'), findsOneWidget);
      expect(find.text('방금 연결'), findsOneWidget);
      expect(find.text('홈으로 가기'), findsOneWidget);
      // 입력 화면의 것은 없다.
      expect(find.byType(BaraedaCodeInput), findsNothing);
    });

    testWidgets('[다른 자녀도 연결하기] 는 빈 입력 화면으로 돌아간다', (tester) async {
      await _pumpAsParent(tester, _StubLinkRepository());
      await tester.enterText(_codeField(), '123456');
      await tester.pump();
      await tester.tap(find.text('연결 완료하기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('다른 자녀도 연결하기'));
      await tester.pumpAndSettle();

      expect(find.byType(BaraedaCodeInput), findsOneWidget);
      expect(find.text('홍길동 연결이 끝났어요'), findsNothing);
      expect(_button(tester, '연결 완료하기').onPressed, isNull);
    });

    testWidgets(
      '코드 확인이 LINK_CODE_INVALID 로 실패하면 이유를 가르지 않는 안내와 시도 상한 안내를 보여준다',
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

        await tester.enterText(_codeField(), '000000');
        await tester.pump();
        await tester.tap(find.text('연결 완료하기'));
        await tester.pumpAndSettle();

        expect(find.text('코드가 올바르지 않거나 만료됐어요'), findsOneWidget);
        // P2 — 서버는 오류 · 상한 초과 · 중복을 이 코드 하나로 합친다(실재 노출 방지). 그래서 매번 고정 안내를 함께 보여
        // 상한에 걸린 학부모가 무한정 재시도하지 않게 한다.
        expect(find.text(_invalidNotice), findsOneWidget);
        expect(
          tester
              .widget<BaraedaCodeInput>(find.byType(BaraedaCodeInput))
              .invalid,
          isTrue,
          reason: '칸이 빨간 테두리가 된다',
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

      await tester.enterText(_codeField(), '123456');
      await tester.pump();
      await tester.tap(find.text('연결 완료하기'));
      await tester.pumpAndSettle();

      expect(find.text('이미 연결된 자녀입니다'), findsOneWidget);
      // P2 안내는 LINK_CODE_INVALID 전용 — 다른 에러 코드까지 번지면 무관한 상황(이미 연결된 자녀)에도 시도 상한
      // 얘기가 뜬다.
      expect(find.text(_invalidNotice), findsNothing);
      expect(
        tester.widget<BaraedaCodeInput>(find.byType(BaraedaCodeInput)).invalid,
        isFalse,
      );
    });
  });
}
