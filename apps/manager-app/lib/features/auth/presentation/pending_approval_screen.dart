import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/info_rows_card.dart';
import 'package:manager_app/core/ui/manager_header.dart';
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
  const new({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  Future<SignupStatusResponse>? _statusFuture;
  SignupStatusResponse? _lastStatus;
  DateTime? _checkedAt;

  /// 승인은 관계자가 따로 하므로 이 화면이 스스로 상태를 다시 본다(M11, 시안 "30초마다").
  static const _autoRefreshInterval = Duration(seconds: 30);
  Timer? _autoRefresh;
  bool _reapplying = false;
  AcademySummary? _newAcademy;
  bool _submittingReapply = false;
  String? _reapplyError;

  @override
  void initState() {
    super.initState();
    _statusFuture = ref.read(authRepositoryProvider).signupStatus();
    _autoRefresh = Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted && !_reapplying) unawaited(_refreshStatus());
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _logout() => signOut(ref);

  /// [상태 다시 확인] — 서버에서 다시 받아 화면에 반영한다. 승인(`active`)이 났으면 계정 상태를
  /// 바꿔 라우터가 홈으로 보내게 한다(안 바꾸면 승인된 뒤에도 이 화면이 대기 중으로 남는다).
  /// `parent_app` 의 같은 화면과 같은 동작이다(R33 M3).
  Future<void> _refreshStatus() async {
    final future = ref.read(authRepositoryProvider).signupStatus();
    setState(() {
      _statusFuture = future;
    });
    try {
      final status = await future;
      if (mounted) {
        setState(() {
          _lastStatus = status;
          _checkedAt = ref.read(clockProvider).now();
        });
      }
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
      appBar: const ManagerHeader(title: '가입 승인', showSos: false),
      body: SafeArea(
        child: FutureBuilder<SignupStatusResponse>(
          future: _statusFuture,
          initialData: _lastStatus,
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
              checkedAt: _checkedAt,
              newAcademy: _newAcademy,
              submittingReapply: _submittingReapply,
              reapplyError: _reapplyError,
              onLogout: _logout,
              onRefresh: _refreshStatus,
              onAcademySelected: (academy) => setState(() {
                _newAcademy = academy;
                // 고르는 중에는 30초 자동 확인이 화면을 흔들지 않는다.
                _reapplying = true;
              }),
              onChangeAcademy: () => setState(() {
                _newAcademy = null;
                _reapplying = false;
              }),
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

class _StatusBody extends StatelessWidget {
  const new({
    required this.status,
    required this.checkedAt,
    required this.newAcademy,
    required this.submittingReapply,
    required this.reapplyError,
    required this.onLogout,
    required this.onRefresh,
    required this.onChangeAcademy,
    required this.onAcademySelected,
    required this.onSubmitReapply,
    required this.onSearch,
  });

  final SignupStatusResponse status;
  final DateTime? checkedAt;
  final AcademySummary? newAcademy;
  final bool submittingReapply;
  final String? reapplyError;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;
  final VoidCallback onChangeAcademy;
  final ValueChanged<AcademySummary> onAcademySelected;
  final VoidCallback onSubmitReapply;
  final Future<List<AcademySummary>> Function(String query) onSearch;

  bool get _isRejected => status.status == AccountStatus.rejected;

  @override
  Widget build(BuildContext context) {
    if (!_isRejected) {
      return _PendingBody(
        status: status,
        checkedAt: checkedAt,
        onRefresh: onRefresh,
        onLogout: onLogout,
      );
    }
    final colors = context.colors;
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm');
    final contact = status.academyContact;
    final academy = newAcademy;
    final rejectReason = status.rejectReason ?? '등록된 사유가 없어요. 학원에 문의해 주세요.';
    final reapplyReason = academy == null ? '다시 신청할 학원을 고르면 눌러요' : null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AlertBanner(
                  tone: AlertTone.missed,
                  title: '가입이 거절됐어요',
                  body: '사유 · $rejectReason',
                ),
                const SizedBox(height: BaraedaSpacing.space3),
                InfoRowsCard(
                  rows: [
                    InfoRow('신청 학원', value: status.academyName),
                    InfoRow(
                      '신청 일시',
                      value: dateFormat.format(status.requestedAt.toLocal()),
                    ),
                    const InfoRow(
                      '현재 상태',
                      valueWidget: Align(
                        alignment: Alignment.centerLeft,
                        child: BaraedaStatusPill(
                          status: BaraedaStatus.missed,
                          label: '거절됨',
                        ),
                      ),
                    ),
                    InfoRow(
                      '학원 문의처',
                      valueWidget: Row(
                        children: [
                          Expanded(
                            child: Text(
                              status.academyContactText,
                              style: BaraedaTypography.body.copyWith(
                                color: colors.textPrimary,
                                fontWeight: BaraedaFontWeight.medium,
                              ),
                            ),
                          ),
                          // 번호 모양이 아닌 문의처(문장)는 걸 곳이 없어
                          // 전화 단추를 만들지 않는다(`Ruling 827`).
                          if (looksLikePhoneNumber(contact))
                            _CallButton(number: contact!.trim()),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BaraedaSpacing.space4),
                Text(
                  '다른 학원으로 다시 신청',
                  style: BaraedaTypography.label.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: BaraedaSpacing.space2),
                if (academy == null)
                  AcademyPicker(
                    onSearch: onSearch,
                    selected: newAcademy,
                    onSelected: onAcademySelected,
                  )
                else
                  BaraedaCard(
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
                            borderRadius: BorderRadius.circular(
                              BaraedaRadius.control,
                            ),
                          ),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: BaraedaIcon(
                                'school',
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: BaraedaSpacing.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                academy.name,
                                style: BaraedaTypography.body.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: BaraedaFontWeight.bold,
                                ),
                              ),
                              Text(
                                '${academy.region} · 학원 코드 ${academy.code}',
                                style: BaraedaTypography.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        BaraedaButton(
                          label: '변경',
                          size: BaraedaButtonSize.sm,
                          variant: BaraedaButtonVariant.ghost,
                          onPressed: onChangeAcademy,
                        ),
                      ],
                    ),
                  ),
                if (reapplyError != null) ...[
                  const SizedBox(height: BaraedaSpacing.space2),
                  AlertBanner(tone: AlertTone.missed, body: reapplyError),
                ],
              ],
            ),
          ),
        ),
        BottomActionBar(
          children: [
            BaraedaButton(
              label: '이 학원으로 재신청',
              size: BaraedaButtonSize.xl,
              block: true,
              onPressed: academy == null || submittingReapply
                  ? null
                  : onSubmitReapply,
              disabledReason: reapplyReason,
            ),
            const SizedBox(height: BaraedaSpacing.space1),
            BaraedaButton(
              label: '로그아웃',
              variant: BaraedaButtonVariant.ghost,
              block: true,
              onPressed: onLogout,
            ),
          ],
        ),
      ],
    );
  }
}

/// `전화` 단추 — 번호로 전화 앱을 연다.
class _CallButton extends ConsumerWidget {
  const new({required this.number});

  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BaraedaButton(
    label: '전화',
    icon: 'phone',
    variant: BaraedaButtonVariant.secondary,
    onPressed: () => unawaited(
      ref.read(uriOpenerProvider)(Uri(scheme: 'tel', path: number)),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const new({required this.label, required this.value});

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
              style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 승인 대기(시안 `pending`) — 머리글 · `승인 대기` 칩 · 3단계 · 신청 학원 · 학원 문의처(번호 모양일 때만 전화).
class _PendingBody extends ConsumerWidget {
  const new({
    required this.status,
    required this.checkedAt,
    required this.onRefresh,
    required this.onLogout,
  });

  final SignupStatusResponse status;
  final DateTime? checkedAt;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final contact = status.academyContact;
    final requested = DateFormat('M월 d일 HH:mm')
        .format(status.requestedAt.toLocal());
    final checked = checkedAt == null
        ? null
        : DateFormat('HH:mm').format(checkedAt!.toLocal());
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              Text(
                '가입 승인을 기다리고 있어요',
                textAlign: TextAlign.center,
                style: BaraedaTypography.h3.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              const Center(
                child: BaraedaStatusPill(
                  status: BaraedaStatus.waiting,
                  label: '승인 대기',
                  size: BaraedaStatusPillSize.lg,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                [
                  if (checked != null) '$checked 확인',
                  '이 화면은 30초마다 저절로 확인해요',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: BaraedaTypography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              BaraedaCard(
                child: StopTimeline(
                  stops: [
                    Stop(
                      name: '신청 접수',
                      address: requested,
                      state: StopState.done,
                    ),
                    const Stop(
                      name: '학원 관계자 승인',
                      address: '보통 학원이 확인하는 대로 승인돼요',
                      state: StopState.current,
                    ),
                    const Stop(name: '이용 시작', address: '승인되면 홈으로 이동해요'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BaraedaCard(
                child: Column(
                  children: [
                    _InfoRow(label: '신청 학원', value: status.academyName),
                    Padding(
                      padding: const EdgeInsets.only(left: 88),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${status.academyRegion} · 코드 ${status.academyCode}',
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 24, color: colors.borderSubtle),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoRow(
                            label: '학원 문의처',
                            value: status.academyContactText,
                          ),
                        ),
                        // 번호 모양이 아닌 문의처(문장)는 걸 곳이 없다 — 전화 단추를 만들지 않는다(`Ruling
                        // 827`).
                        if (looksLikePhoneNumber(contact))
                          BaraedaButton(
                            label: '전화',
                            icon: 'phone',
                            variant: BaraedaButtonVariant.secondary,
                            onPressed: () => unawaited(
                              ref.read(uriOpenerProvider)(
                                Uri(scheme: 'tel', path: contact!.trim()),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bgBase,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BaraedaButton(
                  label: '상태 다시 확인',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                  onPressed: onRefresh,
                ),
                const SizedBox(height: 4),
                BaraedaButton(
                  label: '로그아웃',
                  variant: BaraedaButtonVariant.ghost,
                  block: true,
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
