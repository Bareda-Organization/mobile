import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/ui/minute_ticker.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';
import 'package:parent_app/features/child_link/presentation/widgets/link_done_view.dart';
import 'package:parent_app/features/child_link/presentation/widgets/parent_link_view.dart';
import 'package:parent_app/features/child_link/presentation/widgets/student_code_view.dart';

/// 자녀 연결 (FEATURE_SPEC §5.1 색인 기준 P-02) · 학생 코드 생성(S-05) 화면.
///
/// 학부모·학생이 같은 화면을 쓰되 [roleCapabilitiesProvider] 로 흐름을
/// 가른다(§1.1 "역할 분기는 role_policy 한 곳" — 이 파일에 역할 문자열을
/// 직접 쓰지 않는다).
///
/// **Ruling 324** — 가입 승인과 자녀 연결을 분리하며 요청(§3.2) 단계를
/// 없앴다. 학생이 선행 조건 없이 언제든 코드를 만들고(§3.3), 학부모는 그
/// 코드를 입력하기만 한다(§3.4) — 2단계로 줄었다.
///
/// R48 시안 `child-link*` · `link-code*` — 주 행동은 화면 맨 아래 고정 줄에 두고(엄지가 닿는 곳), 학부모는
/// 연결이
/// 끝나면 전용 완료 화면으로 바뀐다. 보이는 부분은 `widgets/` 에 있고 이 파일은 상태와 서버 호출만 맡는다.
class ChildLinkScreen extends ConsumerStatefulWidget {
  /// `/child-link`.
  const new({super.key});

  @override
  ConsumerState<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

/// 코드 자릿수 — 학부모 입력 칸과 학생이 만든 코드가 같다(`§3.3 · §3.4`).
const _codeLength = 6;

class _ChildLinkScreenState extends ConsumerState<ChildLinkScreen> {
  /// 학부모가 입력 중인 코드.
  String _code = '';

  /// 학생이 만든 코드 — 아직 안 만들었으면 `null`.
  LinkCodeResult? _generated;

  /// 학부모의 연결이 끝난 자녀 — 있으면 완료 화면이다.
  LinkConfirmResult? _connected;

  bool _submitting = false;
  String? _formError;

  /// 지금 `_formError` 가 `LINK_CODE_INVALID` 로 실패한 것인가.
  /// 서버는 코드 오류·시도 상한 초과·중복 코드를 전부 이 코드 하나로
  /// 합쳐 돌려준다(코드 실재 노출 방지, `§3.4`) — 응답을 갈라 안내하지
  /// 못하므로 이 코드일 때는 항상 시도 상한 고정 안내를 함께 보여준다.
  bool _formErrorIsCodeInvalid = false;

  Future<void> _submitConfirmLink() async {
    if (_code.length != _codeLength || _submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _formErrorIsCodeInvalid = false;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.confirmLink(_code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _connected = result;
      });
      // 홈 화면의 자녀 목록이 낡지 않도록 무효화한다(C-10 계열 — 다시
      // 조회해 서버 상태를 그대로 반영).
      ref.invalidate(myStudentsProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
        _formErrorIsCodeInvalid =
            failure is ApiFailure && failure.code == 'LINK_CODE_INVALID';
      });
    }
  }

  Future<void> _submitGenerateCode() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.generateLinkCode();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _generated = result;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
      });
    }
  }

  /// 완료 화면에서 다른 자녀를 이어 연결한다 — 입력 칸을 비운다.
  void _connectAnother() => setState(() {
    _connected = null;
    _code = '';
    _formError = null;
    _formErrorIsCodeInvalid = false;
  });

  /// 클립보드에 복사하고 결과를 알린다 — 복사 성공은 되돌릴 수 없는 동작이 아니라 한 줄 안내로 충분하다.
  Future<void> _copy(String text, String doneMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: WordWrapText(doneMessage)));
  }

  /// 학부모에게 메신저로 붙여 넣을 문장 — 코드만 보내면 어디에 입력하는지 모른다.
  String _shareMessage(String code, DateTime expiresAt) =>
      '바래다 자녀 연결 코드 $code · 학부모 앱의 [설정] › [자녀 추가] 에서 입력해 주세요 · '
      '${DateFormat('H:mm').format(expiresAt.toLocal())} 까지 쓸 수 있습니다';

  String _messageFor(Failure failure) => switch (failure) {
    ApiFailure(code: 'ALREADY_LINKED') => '이미 연결된 자녀입니다',
    ApiFailure(code: 'LINK_CODE_INVALID') => linkCodeInvalidTitle,
    ApiFailure(:final message) => message,
    NetworkFailure() => '네트워크 상태를 확인해 주세요',
    _ => '요청을 처리하지 못했습니다',
  };

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    // 학생만 코드 생성 진입점을 갖는다(role_policy.dart) — 그 외(학부모 ·
    // 아직 role 미확정)는 코드 입력 흐름을 보여준다.
    final isStudent = capabilities?.canGenerateLinkCode ?? false;

    // 학생 화면은 만료 시각이 지나는 순간 모양이 바뀌므로 분 단위 시계를 물고 그린다.
    return MinuteTicker(
      builder: (context, now) =>
          isStudent ? _buildStudent(context, now) : _buildParent(context),
    );
  }

  Widget _buildParent(BuildContext context) {
    final connected = _connected;
    if (connected != null) return _buildDone(context, connected);

    final complete = _code.length == _codeLength;
    return _Page(
      title: '자녀 연결',
      body: ParentLinkView(
        code: _code,
        onCodeChanged: (value) => setState(() => _code = value),
        invalid: _formErrorIsCodeInvalid,
        error: _formError,
      ),
      bar: BaraedaButton(
        label: '연결 완료하기',
        size: BaraedaButtonSize.xl,
        block: true,
        // 꺼진 단추에는 이유가 붙는다 — 무엇을 하면 눌리는지.
        disabledReason: complete || _submitting
            ? null
            : '연결 코드 $_codeLength자리를 모두 입력하면 눌러요',
        onPressed: _submitting || !complete ? null : _submitConfirmLink,
      ),
    );
  }

  Widget _buildDone(BuildContext context, LinkConfirmResult connected) {
    // 목록을 받는 동안·실패했을 때는 방금 연결한 자녀 하나만 보인다 — 연결은 이미 끝난 일이다.
    final students = ref.watch(myStudentsProvider).value ?? const [];
    return _Page(
      title: '자녀 연결',
      body: LinkDoneView(
        justLinkedId: connected.studentId,
        justLinkedName: connected.name,
        students: students,
      ),
      bar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BaraedaButton(
            label: '홈으로 가기',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () => context.go(AppRoutes.home),
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          BaraedaButton(
            label: '다른 자녀도 연결하기',
            variant: BaraedaButtonVariant.secondary,
            block: true,
            onPressed: _connectAnother,
          ),
        ],
      ),
    );
  }

  Widget _buildStudent(BuildContext context, DateTime now) {
    final generated = _generated;
    final expiresAt = generated?.expiresAt;
    final expired =
        expiresAt != null && StudentCodeView.isExpired(expiresAt, now);

    final Widget bar;
    if (generated == null) {
      bar = BaraedaButton(
        label: '코드 만들기',
        size: BaraedaButtonSize.xl,
        block: true,
        onPressed: _submitting ? null : _submitGenerateCode,
      );
    } else if (expired) {
      // 만료되면 새 코드가 주 행동이다.
      bar = BaraedaButton(
        label: '새 코드 만들기',
        size: BaraedaButtonSize.xl,
        block: true,
        onPressed: _submitting ? null : _submitGenerateCode,
      );
    } else {
      // 안내 문구가 코드만 보내는 것보다 실제로 유용하다 — 어디에 입력하는지가 함께 간다.
      bar = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BaraedaButton(
            label: '안내 문구 복사',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () => _copy(
              _shareMessage(generated.code, generated.expiresAt),
              '안내 문구를 복사했어요',
            ),
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          BaraedaButton(
            label: '새 코드 만들기',
            variant: BaraedaButtonVariant.ghost,
            block: true,
            onPressed: _submitting ? null : _submitGenerateCode,
          ),
        ],
      );
    }

    return _Page(
      title: '부모님과 연결하기',
      body: StudentCodeView(
        code: generated?.code,
        expiresAt: expiresAt,
        now: now,
        shareMessage: generated == null
            ? null
            : _shareMessage(generated.code, generated.expiresAt),
        onCopyCode: () => _copy(generated?.code ?? '', '코드를 복사했어요'),
        error: _formError,
      ),
      bar: bar,
    );
  }
}

/// 화면 틀 — 머리줄 + 스크롤 본문 + 맨 아래 고정 줄.
class _Page extends StatelessWidget {
  const new({required this.title, required this.body, required this.bar});

  final String title;
  final Widget body;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: title),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
                child: body,
              ),
            ),
            StickyActionBar(child: bar),
          ],
        ),
      ),
    );
  }
}
