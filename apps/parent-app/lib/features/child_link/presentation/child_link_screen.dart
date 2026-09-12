import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';

/// 자녀 연결 (FEATURE_SPEC §5.1 색인 기준 P-02, BRIEF 표기 "P-01" 은
/// 정본과 어긋남 — 보고서 §2 참고) · 학생 코드 생성(S-05) 화면.
///
/// 학부모·학생이 같은 화면을 쓰되 [roleCapabilitiesProvider] 로 흐름을
/// 가른다(§1.1 "역할 분기는 role_policy 한 곳" — 이 파일에 역할 문자열을
/// 직접 쓰지 않는다).
///
/// - 학부모: `student_login_id` 입력(§3.2) → 코드 입력(§3.4) 2단계.
/// - 학생: 코드 생성 버튼 하나(§3.3) — 대기 중인 연결 요청이 있어야 성공한다.
class ChildLinkScreen extends ConsumerStatefulWidget {
  const ChildLinkScreen({super.key});

  @override
  ConsumerState<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

class _ChildLinkScreenState extends ConsumerState<ChildLinkScreen> {
  final _studentLoginIdController = TextEditingController();
  String _code = '';

  bool _submitting = false;
  String? _formError;
  String? _successMessage;

  // §3.2 성공 후에만 코드 입력 단계로 넘어간다 — null 이면 1단계.
  bool _codeStepUnlocked = false;

  @override
  void dispose() {
    _studentLoginIdController.dispose();
    super.dispose();
  }

  Future<void> _submitRequestLink() async {
    final loginId = _studentLoginIdController.text.trim();
    if (loginId.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _successMessage = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      await repository.requestLink(loginId);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _codeStepUnlocked = true;
        _successMessage = '연결 요청을 보냈습니다. 자녀 화면에서 받은 코드를 입력해 주세요.';
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
      });
    }
  }

  Future<void> _submitConfirmLink() async {
    if (_code.length != 6 || _submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _successMessage = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.confirmLink(_code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _successMessage = '${result.name} 자녀 연결이 완료됐습니다.';
      });
      // 홈 화면의 자녀 목록이 낡지 않도록 무효화한다(C-10 계열 — 다시
      // 조회해 서버 상태를 그대로 반영).
      ref.invalidate(myStudentsProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
      });
    }
  }

  Future<void> _submitGenerateCode() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _successMessage = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.generateLinkCode();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _code = result.code;
        _successMessage = '학부모 앱에 이 코드를 알려 주세요 (만료: ${result.expiresAt}).';
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
      });
    }
  }

  String _messageFor(Failure failure) => switch (failure) {
    ApiFailure(code: 'STUDENT_NOT_FOUND') => '해당 아이디의 학생을 찾을 수 없습니다',
    ApiFailure(code: 'ALREADY_LINKED') => '이미 연결된 자녀입니다',
    ApiFailure(code: 'LINK_CODE_INVALID') => '코드가 올바르지 않거나 만료됐습니다',
    ApiFailure(code: 'LINK_REQUEST_NOT_FOUND') =>
      '대기 중인 연결 요청이 없습니다. 학부모에게 먼저 요청을 보내달라고 해주세요',
    ApiFailure(:final message) => message,
    NetworkFailure() => '네트워크 상태를 확인해 주세요',
    _ => '요청을 처리하지 못했습니다',
  };

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    // 학생만 코드 생성 진입점을 갖는다(role_policy.dart) — 그 외(학부모 ·
    // 아직 role 미확정)는 연결 요청 흐름을 보여준다.
    final isStudent = capabilities?.canGenerateLinkCode ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '자녀 연결'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isStudent ? _buildStudentFlow() : _buildParentFlow(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParentFlow() {
    return [
      const Text('자녀 아이디로 연결 요청', style: BaraedaTypography.h3),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaInput(
        label: '자녀 아이디',
        required: true,
        enabled: !_codeStepUnlocked,
        controller: _studentLoginIdController,
      ),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaButton(
        label: '연결 요청 보내기',
        size: BaraedaButtonSize.lg,
        onPressed: (_submitting || _codeStepUnlocked)
            ? null
            : _submitRequestLink,
      ),
      if (_codeStepUnlocked) ...[
        const SizedBox(height: BaraedaSpacing.space8),
        const Text('자녀가 발급받은 코드 입력', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaCodeInput(
          value: _code,
          onChanged: (value) => setState(() => _code = value),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaButton(
          label: '연결 완료하기',
          size: BaraedaButtonSize.lg,
          onPressed: (_submitting || _code.length != 6)
              ? null
              : _submitConfirmLink,
        ),
      ],
      ..._buildMessages(),
    ];
  }

  List<Widget> _buildStudentFlow() {
    return [
      const Text('학부모 연결 코드 생성', style: BaraedaTypography.h3),
      const SizedBox(height: BaraedaSpacing.space4),
      const Text('학부모가 먼저 보낸 연결 요청이 있어야 코드를 만들 수 있습니다.'),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaButton(
        label: '코드 생성하기',
        size: BaraedaButtonSize.lg,
        onPressed: _submitting ? null : _submitGenerateCode,
      ),
      if (_code.isNotEmpty) ...[
        const SizedBox(height: BaraedaSpacing.space6),
        Center(
          child: Text(
            _code,
            style: BaraedaTypography.h1.copyWith(letterSpacing: 8),
          ),
        ),
      ],
      ..._buildMessages(),
    ];
  }

  List<Widget> _buildMessages() {
    return [
      if (_formError != null) ...[
        const SizedBox(height: BaraedaSpacing.space4),
        AlertBanner(tone: AlertTone.missed, body: _formError),
      ],
      if (_successMessage != null) ...[
        const SizedBox(height: BaraedaSpacing.space4),
        AlertBanner(tone: AlertTone.boarded, body: _successMessage),
      ],
    ];
  }
}
