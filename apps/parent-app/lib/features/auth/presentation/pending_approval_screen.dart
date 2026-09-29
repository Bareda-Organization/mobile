import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/features/auth/presentation/widgets/academy_picker.dart';

/// UF-X-02 — 승인 대기 · 거절 안내.
///
/// `pending` · `rejected` 계정은 `router.dart` 의 `redirect` 가 이 화면
/// 밖으로 못 나가게 고정한다(허용 목록 밖 호출은 서버가 어차피
/// `403 AUTH_PENDING`/`AUTH_REJECTED` 로 막지만, 화면단에서도 미리
/// 막아 불필요한 실패 요청을 줄인다).
///
/// Ruling 267(P2 게이트 조건 ②) — §2.11 단말 등록은 `pending` 계정도
/// 호출 가능한데(`API_SPEC §1.4` "pending: … `POST`·`DELETE /me/devices`"),
/// 이 화면 말고는 `pending`·`rejected` 계정이 갈 수 있는 화면이 없다.
/// `router.dart` 를 고쳐 예외를 추가하는 대신(Option A 채택, B·C·D 는
/// 기각) 이 화면이 `DeviceRegistrationPanel`(`core/devices`, 승격됨)을
/// 직접 품는다 — router 의 "허용 목록 밖은 전부 대기 화면으로" 라는
/// 불변식을 그대로 둔 채로 접근성만 채운다.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  /// `/pending-approval`.
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  Future<SignupStatusResponse>? _statusFuture;
  bool _reapplying = false;
  AcademySummary? _newAcademy;
  bool _submittingReapply = false;
  String? _reapplyError;

  @override
  void initState() {
    super.initState();
    _statusFuture = ref.read(authRepositoryProvider).signupStatus();
  }

  // F2(2026-09-26) — `settings_screen.dart` 가 만든 확인 대화를 재사용한다
  // (`core/auth/account_session.dart` 의 [confirmLogout]). 이 화면은 이제껏
  // 확인 없이 곧장 [signOut] 을 불렀다 — 두 로그아웃 진입점의 동작이
  // 갈리는 비일관성이었다(FIX-P.md §2).
  Future<void> _logout() => confirmLogout(context, ref);

  /// [상태 다시 확인] — 서버에서 다시 받아 화면에 반영한다. 승인(`active`)이 났으면 계정 상태를
  /// 바꿔 라우터가 홈으로 보내게 한다(안 바꾸면 승인된 뒤에도 이 화면이 대기 중으로 남는다, R32 P9).
  Future<void> _refreshStatus() async {
    final future = ref.read(authRepositoryProvider).signupStatus();
    setState(() => _statusFuture = future);
    try {
      final status = await future;
      if (mounted && status.status == AccountStatus.active) {
        ref.read(currentAccountStatusProvider.notifier).state =
            AccountStatus.active;
      }
    } on Object {
      // 실패는 FutureBuilder 가 [다시 시도하기] 화면으로 보여준다.
    }
  }

  Future<void> _reapply() async {
    final academy = _newAcademy;
    if (academy == null || _submittingReapply) return;

    setState(() {
      _submittingReapply = true;
      _reapplyError = null;
    });
    try {
      await ref.read(authRepositoryProvider).reapply(academyId: academy.id);
      if (!mounted) return;
      setState(() {
        _submittingReapply = false;
        _reapplying = false;
        _statusFuture = ref.read(authRepositoryProvider).signupStatus();
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submittingReapply = false;
        _reapplyError = switch (failure) {
          ApiFailure(:final message) => message,
          NetworkFailure() => '네트워크 상태를 확인해 주세요',
          _ => '재신청에 실패했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('가입 승인'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: FutureBuilder<SignupStatusResponse>(
          future: _statusFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorBody(
                onRetry: () {
                  setState(() {
                    _statusFuture = ref
                        .read(authRepositoryProvider)
                        .signupStatus();
                  });
                },
              );
            }
            final status = snapshot.data!;
            return _StatusBody(
              status: status,
              reapplying: _reapplying,
              newAcademy: _newAcademy,
              submittingReapply: _submittingReapply,
              reapplyError: _reapplyError,
              onLogout: _logout,
              onRefresh: _refreshStatus,
              onStartReapply: () => setState(() => _reapplying = true),
              onAcademySelected: (academy) =>
                  setState(() => _newAcademy = academy),
              onSubmitReapply: _reapply,
              onSearch: ref.read(authRepositoryProvider).searchAcademies,
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
        child: EmptyState(
          icon: 'triangle-alert',
          title: '상태를 불러오지 못했습니다',
          body: '잠시 후 다시 시도해 주세요',
          action: BaraedaButton(label: '다시 시도하기', onPressed: onRetry),
        ),
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.status,
    required this.reapplying,
    required this.newAcademy,
    required this.submittingReapply,
    required this.reapplyError,
    required this.onLogout,
    required this.onRefresh,
    required this.onStartReapply,
    required this.onAcademySelected,
    required this.onSubmitReapply,
    required this.onSearch,
  });

  final SignupStatusResponse status;
  final bool reapplying;
  final AcademySummary? newAcademy;
  final bool submittingReapply;
  final String? reapplyError;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;
  final VoidCallback onStartReapply;
  final ValueChanged<AcademySummary> onAcademySelected;
  final VoidCallback onSubmitReapply;
  final Future<List<AcademySummary>> Function(String query) onSearch;

  bool get _isRejected => status.status == AccountStatus.rejected;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBanner(
            tone: _isRejected ? AlertTone.missed : AlertTone.info,
            title: _isRejected ? '가입이 거절되었습니다' : '가입 승인을 기다리고 있습니다',
            body: _isRejected
                ? status.rejectReason ?? '거절 사유가 등록되지 않았습니다'
                : null,
          ),
          const SizedBox(height: BaraedaSpacing.space6),
          _InfoRow(label: '신청 학원', value: status.academyName),
          _InfoRow(label: '학원 지역', value: status.academyRegion),
          _InfoRow(label: '학원 코드', value: status.academyCode),
          _InfoRow(
            label: '신청 일시',
            value: dateFormat.format(status.requestedAt.toLocal()),
          ),
          _InfoRow(label: '현재 상태', value: _isRejected ? '거절됨' : '승인 대기'),
          _InfoRow(label: '학원 문의처', value: status.academyContact),
          const SizedBox(height: BaraedaSpacing.space4),
          // R32 P9 — 상태를 처음 한 번만 조회해, 승인·거절이 나도 앱을 껐다 켜야 알 수 있었다.
          BaraedaButton(
            label: '상태 다시 확인',
            variant: BaraedaButtonVariant.secondary,
            block: true,
            onPressed: onRefresh,
          ),
          const SizedBox(height: BaraedaSpacing.space6),
          const Text('단말', style: BaraedaTypography.h3),
          const SizedBox(height: BaraedaSpacing.space2),
          const DeviceRegistrationPanel(),
          const SizedBox(height: BaraedaSpacing.space6),
          if (_isRejected && !reapplying)
            BaraedaButton(
              label: '학원 재선택하고 재신청하기',
              variant: BaraedaButtonVariant.secondary,
              block: true,
              onPressed: onStartReapply,
            ),
          if (_isRejected && reapplying) ...[
            AcademyPicker(
              onSearch: onSearch,
              selected: newAcademy,
              onSelected: onAcademySelected,
            ),
            if (reapplyError != null) ...[
              const SizedBox(height: BaraedaSpacing.space2),
              AlertBanner(tone: AlertTone.missed, body: reapplyError),
            ],
            const SizedBox(height: BaraedaSpacing.space4),
            BaraedaButton(
              label: '재신청하기',
              block: true,
              onPressed: newAcademy == null || submittingReapply
                  ? null
                  : onSubmitReapply,
            ),
          ],
          const SizedBox(height: BaraedaSpacing.space8),
          BaraedaButton(
            label: '로그아웃하기',
            variant: BaraedaButtonVariant.ghost,
            block: true,
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BaraedaSpacing.space2),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: BaraedaTypography.body.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
