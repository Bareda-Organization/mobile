import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/core/refresh/visible_poller.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/korean_particle.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/auth/presentation/widgets/academy_picker.dart';
import 'package:parent_app/features/auth/presentation/widgets/approval_progress.dart';
import 'package:url_launcher/url_launcher.dart';

/// 승인 대기 화면이 상태를 다시 조회하는 간격 — 푸시 SDK 가 없어 이 조회가
/// 승인·거절을 아는 유일한 길이다(R46 B2 #20). 홈의 `pollInterval`(90초)보다 짧게 둔다:
/// 승인을 기다리는 사람은 이 화면 하나만 보고 있고, 계정 상태 조회 한 건은 가볍다.
const Duration pendingStatusPollInterval = Duration(seconds: 30);

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
  const new({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  Future<SignupStatusResponse>? _statusFuture;

  /// 가입 상태를 받고, 학원 문의처를 기기에 남긴다 — 차단 화면이 소속 학원을 모를 때 쓴다(`Ruling 825`).
  Future<SignupStatusResponse> _loadStatus() async {
    final status = await ref.read(authRepositoryProvider).signupStatus();
    final contact = status.academyContact;
    if (contact != null) {
      unawaited(ref.read(academyContactStorageProvider).save(contact));
    }
    if (mounted) _checkedAt = ref.read(clockProvider).now();
    return status;
  }

  /// 마지막으로 조회한 시각 — 카드 오른쪽 `12:14 확인`. 서버 값이 아니라 앱이 조회한 순간(`REPORT-MP §1.3`).
  DateTime? _checkedAt;
  bool _reapplying = false;
  AcademySummary? _newAcademy;
  bool _submittingReapply = false;
  String? _reapplyError;

  /// 앱이 보이는 동안만 [pendingStatusPollInterval] 마다, 백그라운드에서 돌아오면 바로 다시 조회한다.
  late final VisiblePoller _poller = VisiblePoller(
    interval: pendingStatusPollInterval,
    onTick: () => unawaited(_pollQuietly()),
  );

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  /// 화면을 로딩·오류로 바꾸지 않고 조회한다 — 실패하면 보이던 상태를 그대로 두고 다음 간격에 다시 시도한다.
  /// 승인(`active`)이면 계정 상태를 바꿔 라우터가 홈으로 보내게 한다.
  Future<void> _pollQuietly() async {
    try {
      final status = await _loadStatus();
      if (!mounted) return;
      setState(() {
        _statusFuture = Future.value(status);
      });
      if (status.status == AccountStatus.active) {
        ref.read(currentAccountStatusProvider.notifier).state =
            AccountStatus.active;
      }
    } on Object {
      // 연결이 끊긴 동안의 실패는 오류 화면이 아니라 다음 조회로 넘긴다.
    }
  }

  // F2(2026-09-26) — `settings_screen.dart` 가 만든 확인 대화를 재사용한다
  // (`core/auth/account_session.dart` 의 [confirmLogout]). 이 화면은 이제껏
  // 확인 없이 곧장 [signOut] 을 불렀다 — 두 로그아웃 진입점의 동작이
  // 갈리는 비일관성이었다(FIX-P.md §2).
  Future<void> _logout() => confirmLogout(context, ref);

  /// [상태 다시 확인] — 서버에서 다시 받아 화면에 반영한다. 승인(`active`)이 났으면 계정 상태를
  /// 바꿔 라우터가 홈으로 보내게 한다(안 바꾸면 승인된 뒤에도 이 화면이 대기 중으로 남는다, R32 P9).
  Future<void> _refreshStatus() async {
    final future = _loadStatus();
    setState(() {
      _statusFuture = future;
    });
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

  /// 학원을 고른 뒤 확인 대화상자 한 단계를 거친다(UF-X-02) — 신청한 뒤에는 되돌릴 수 없다.
  Future<void> _confirmReapply() async {
    final academy = _newAcademy;
    if (academy == null || _submittingReapply) return;
    final confirmed = await showBaraedaActionDialog<bool>(
      context: context,
      title: '${academy.name}${euroOf(academy.name)} 다시 신청할까요?',
      body: '신청한 뒤에는 되돌릴 수 없어요. 학원이 확인하면 알림으로 알려 드려요.',
      actions: const [
        BaraedaDialogAction(label: '재신청하기', value: true),
        BaraedaDialogAction(
          label: '학원 다시 고르기',
          value: false,
          variant: BaraedaButtonVariant.secondary,
        ),
      ],
    );
    if (confirmed ?? false) await _reapply();
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
        _statusFuture = _loadStatus();
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
      appBar: const AppHeader(title: '가입 승인'),
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
            final rejected = status.status == AccountStatus.rejected;
            return Column(
              children: [
                Expanded(
                  child: _StatusBody(
                    status: status,
                    checkedAt: _checkedAt,
                    reapplying: _reapplying,
                    newAcademy: _newAcademy,
                    reapplyError: _reapplyError,
                    onLogout: _logout,
                    onRefresh: _refreshStatus,
                    onAcademySelected: (academy) =>
                        setState(() => _newAcademy = academy),
                    onSearch: ref.read(authRepositoryProvider).searchAcademies,
                  ),
                ),
                // 거절이면 주 행동을 엄지가 닿는 맨 아래에 고정한다.
                if (rejected)
                  StickyActionBar(
                    child: _reapplying
                        ? BaraedaButton(
                            label: '재신청하기',
                            size: BaraedaButtonSize.xl,
                            block: true,
                            onPressed: _newAcademy == null || _submittingReapply
                                ? null
                                : _confirmReapply,
                          )
                        : BaraedaButton(
                            label: '학원 다시 골라 재신청',
                            size: BaraedaButtonSize.xl,
                            block: true,
                            onPressed: () => setState(() => _reapplying = true),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const new({required this.onRetry});

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

/// 본문 — 상태 카드 → 진행 막대 → 신청 정보 → 다시 확인 → 기기 알림 → 로그아웃.
/// 학원을 다시 고르는 중이면 앞 두 칸 대신 거절 띠와 학원 검색이 온다(시안 `pending--reapply`).
class _StatusBody extends StatelessWidget {
  const new({
    required this.status,
    required this.checkedAt,
    required this.reapplying,
    required this.newAcademy,
    required this.reapplyError,
    required this.onLogout,
    required this.onRefresh,
    required this.onAcademySelected,
    required this.onSearch,
  });

  final SignupStatusResponse status;
  final DateTime? checkedAt;
  final bool reapplying;
  final AcademySummary? newAcademy;
  final String? reapplyError;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;
  final ValueChanged<AcademySummary> onAcademySelected;
  final Future<List<AcademySummary>> Function(String query) onSearch;

  bool get _isRejected => status.status == AccountStatus.rejected;

  /// 거절 사유 — 학원이 적지 않았으면 그 사실을 그대로 쓴다.
  String get _reason => status.rejectReason ?? '거절 사유가 등록되지 않았습니다';

  @override
  Widget build(BuildContext context) {
    if (_isRejected && reapplying) return _buildReapply(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(
            rejected: _isRejected,
            checkedAt: checkedAt,
            reason: _isRejected ? _reason : null,
          ),
          const SizedBox(height: BaraedaSpacing.space5),
          ApprovalProgress(
            steps: approvalSteps(status.status, status.requestedAt),
          ),
          const SizedBox(height: BaraedaSpacing.space5),
          _InfoCard(status: status),
          const SizedBox(height: BaraedaSpacing.space3),
          // R32 P9 — 상태를 처음 한 번만 조회해, 승인·거절이 나도 앱을 껐다 켜야 알 수 있었다.
          BaraedaButton(
            label: '상태 다시 확인',
            icon: 'refresh',
            variant: BaraedaButtonVariant.secondary,
            block: true,
            onPressed: onRefresh,
          ),
          const SizedBox(height: BaraedaSpacing.space3),
          const _DeviceCard(),
          const SizedBox(height: BaraedaSpacing.space4),
          BaraedaButton(
            label: '로그아웃',
            variant: BaraedaButtonVariant.ghost,
            block: true,
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }

  /// 학원을 다시 고르는 중 — 거절 띠 + 안내 + 학원 검색.
  Widget _buildReapply(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBanner(
            tone: AlertTone.missed,
            title: '가입이 거절되었어요',
            body: _reason,
          ),
          const SizedBox(height: BaraedaSpacing.space5),
          const Text('다니는 학원을 다시 골라 주세요', style: BaraedaTypography.h3),
          const SizedBox(height: BaraedaSpacing.space3),
          AcademyPicker(
            onSearch: onSearch,
            selected: newAcademy,
            onSelected: onAcademySelected,
          ),
          if (reapplyError != null) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            AlertBanner(tone: AlertTone.missed, body: reapplyError),
          ],
          const SizedBox(height: BaraedaSpacing.space6),
          BaraedaButton(
            label: '로그아웃',
            variant: BaraedaButtonVariant.ghost,
            block: true,
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

/// 맨 위 카드 — 상태 칩 + 마지막 확인 시각 → 큰 제목 → 안내(거절이면 사유 띠).
class _StatusCard extends StatelessWidget {
  const new({
    required this.rejected,
    required this.checkedAt,
    required this.reason,
  });

  final bool rejected;
  final DateTime? checkedAt;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final checked = checkedAt;

    return BaraedaCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BaraedaStatusPill(
                status: rejected ? BaraedaStatus.missed : BaraedaStatus.waiting,
                label: rejected ? '거절됨' : '승인 대기',
                size: BaraedaStatusPillSize.lg,
              ),
              const Spacer(),
              if (checked != null)
                Text(
                  '${formatClock(checked)} 확인',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space3),
          Text(
            rejected ? '가입이 거절되었어요' : '학원이 확인하고 있어요',
            style: BaraedaTypography.h3,
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          if (rejected)
            AlertBanner(
              tone: AlertTone.missed,
              title: '학원이 남긴 사유',
              body: reason,
            )
          else
            WordWrapText(
              '승인되면 알림으로 알려 드려요. 이 화면은 30초마다 저절로 확인해요.',
              style: BaraedaTypography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 신청 정보 표 — 줄마다 이름 + 값. 문의처 줄 오른쪽에 번호 모양이 있을 때만 전화 단추를 둔다(`Ruling 827`).
class _InfoCard extends StatelessWidget {
  const new({required this.status});

  final SignupStatusResponse status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm');
    final phone = phoneNumberOf(status.academyContact);
    final rows = <Widget>[
      _InfoRow(label: '신청 학원', value: status.academyName),
      _InfoRow(label: '학원 지역', value: status.academyRegion),
      _InfoRow(label: '학원 코드', value: status.academyCode),
      _InfoRow(
        label: '신청 일시',
        value: dateFormat.format(status.requestedAt.toLocal()),
      ),
      _InfoRow(
        label: '학원 문의처',
        value: status.academyContactText,
        trailing: phone == null
            ? null
            : Semantics(
                label: '학원에 전화 $phone',
                button: true,
                excludeSemantics: true,
                onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                child: BaraedaButton(
                  label: '전화',
                  icon: 'phone',
                  size: BaraedaButtonSize.sm,
                  variant: BaraedaButtonVariant.secondary,
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                ),
              ),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.borderSubtle),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const new({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaraedaSpacing.space4,
          vertical: BaraedaSpacing.space2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: WordWrapText(
                value,
                style: BaraedaTypography.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: BaraedaSpacing.space2),
              ?trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// 이 기기의 알림 받기 — 승인 · 거절 결과를 바로 받으려면 켜 둔다(`Ruling 267`).
class _DeviceCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: BaraedaSpacing.space4),
        child: DeviceRegistrationPanel(
          sublabel: '승인 · 거절 결과를 바로 알려 드려요',
        ),
      ),
    );
  }
}
