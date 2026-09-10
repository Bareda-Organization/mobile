import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/features/auth/presentation/widgets/academy_picker.dart';

/// UF-X-02 — 승인 대기 · 거절 안내.
///
/// `pending` · `rejected` 계정은 `router.dart` 의 `redirect` 가 이 화면
/// 밖으로 못 나가게 고정한다(허용 목록 밖 호출은 서버가 어차피
/// `403 AUTH_PENDING`/`AUTH_REJECTED` 로 막지만, 화면단에서도 미리
/// 막아 불필요한 실패 요청을 줄인다). `parent_app` 의 같은 화면과 내용이
/// 같다(§1.1).
class PendingApprovalScreen extends ConsumerStatefulWidget {
  /// `/pending-approval`.
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState
    extends ConsumerState<PendingApprovalScreen> {
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

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    if (!mounted) return;
    applyRoleAndStatus(
      ref.read(unsupportedRoleProvider.notifier),
      ref.read(currentUserRoleProvider.notifier),
      ref.read(currentAccountStatusProvider.notifier),
      role: null,
      status: null,
    );
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
              return _ErrorBody(onRetry: () {
                setState(() {
                  _statusFuture = ref
                      .read(authRepositoryProvider)
                      .signupStatus();
                });
              });
            }
            final status = snapshot.data!;
            return _StatusBody(
              status: status,
              reapplying: _reapplying,
              newAcademy: _newAcademy,
              submittingReapply: _submittingReapply,
              reapplyError: _reapplyError,
              onLogout: _logout,
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
