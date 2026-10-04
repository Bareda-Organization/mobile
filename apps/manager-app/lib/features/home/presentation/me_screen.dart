import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';

/// 내 정보 탭 — 내 이름 · 학원 · 담당 차량과 "사용 중 도움"(오프라인 대기열 · 위치 권한 · 비밀번호 변경 ·
/// 학원 전화), 맨 아래 로그아웃(`Ruling 826` — 홈 머리말에서 옮겨 왔다). 기사 · 동승자 공통이다.
///
/// 담당 차량은 지금 다루는 회차의 호차와 번호판(§4.1 `plate_no`) — 서버가 번호판을 아직 안 주면 그 칸을 뺀다.
class MeScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final role = ref.watch(currentUserRoleProvider);
    final focus = ref.watch(focusRunProvider);
    final pending = ref.watch(pendingRequestsProvider).value?.length ?? 0;
    final contact = ref.watch(academyContactProvider);
    final colors = context.colors;
    final isDriver = role == UserRole.driver;

    return Scaffold(
      appBar: const ManagerHeader(title: '내 정보'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ProfileCard(
            name: me?.name,
            academy: me?.academy?.name,
            roleLabel: isDriver ? '기사' : '동승자',
            busNo: focus?.busNo,
            plateNo: focus?.plateNo,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '사용 중 도움',
              style: BaraedaTypography.title.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          BaraedaListGroup(
            children: [
              BaraedaListRow(
                leadingIcon: 'inbox',
                title: '오프라인 대기열',
                subtitle: '인터넷이 끊겼을 때 못 보낸 처리',
                trailing: _TrailingChevron(count: pending),
                onTap: () => unawaited(context.push(AppRoutes.offlineQueue)),
              ),
              _LocationRow(isDriver: isDriver),
              BaraedaListRow(
                leadingIcon: 'lock',
                title: '비밀번호 변경',
                trailing: const _TrailingChevron(),
                onTap: () => unawaited(context.push(AppRoutes.passwordChange)),
              ),
              if (looksLikePhoneNumber(contact))
                BaraedaListRow(
                  leadingIcon: 'phone',
                  title: '학원 전화',
                  subtitle: contact!.trim(),
                  trailing: const _TrailingChevron(),
                  onTap: () => unawaited(
                    ref.read(uriOpenerProvider)(
                      Uri(scheme: 'tel', path: contact.trim()),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          BaraedaButton(
            label: '로그아웃',
            icon: 'log-out',
            variant: BaraedaButtonVariant.dangerOutline,
            block: true,
            onPressed: () => unawaited(_confirmSignOut(context, ref)),
          ),
        ],
      ),
    );
  }

  /// 로그아웃 확인(AUTH-09) — 운행 중이면 명단·위치 송신이 멈춘다는 경고를 붙이고, 못 보낸 처리가 있으면 건수를
  /// 알리며 **대기열 먼저 보기**를 맨 위에 둔다(M8 — 로그아웃하면 대기열을 비운다). 창은 바로 띄우고 건수는 읽히는
  /// 대로 채운다 — 대기열 읽기가 로그아웃 확인을 막지 않게. 확인해야만 [signOut] 을 부른다 — 그 함수는 서버 성패와
  /// 무관하게 토큰을 지우고, 라우터가 역할 소실을 보고 로그인 화면으로 보낸다.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final hasMovingRun =
        ref
            .read(todayRunsProvider)
            .value
            ?.any((run) => run.runStatus == RunStatus.moving) ??
        false;
    final pendingCount = _pendingCount(ref);
    final choice = await showBaraedaActionDialog<_SignOutChoice>(
      context: context,
      title: '로그아웃하시겠습니까?',
      content: FutureBuilder<int>(
        future: pendingCount,
        initialData: 0,
        builder: (dialogContext, snapshot) {
          final count = snapshot.data ?? 0;
          final colors = dialogContext.colors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  if (hasMovingRun)
                    '운행 중에 로그아웃하면 명단·위치 송신이 멈춥니다'
                  else
                    '다시 로그인해야 이 앱을 계속 쓸 수 있습니다',
                  // M2-01 — 큐에는 계정 열이 없어 로그아웃하면 비운다(F06-02). 있을 때만 알린다.
                  if (count > 0) '아직 보내지 못한 처리 $count건은 버려집니다',
                ].join('\n'),
                style: BaraedaTypography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                BaraedaButton(
                  label: '대기열 $count건 먼저 보기',
                  block: true,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_SignOutChoice.viewQueue),
                ),
              ],
            ],
          );
        },
      ),
      actions: const [
        BaraedaDialogAction(
          label: '로그아웃',
          value: _SignOutChoice.signOut,
          variant: BaraedaButtonVariant.danger,
        ),
        BaraedaDialogAction(
          label: '닫기',
          value: _SignOutChoice.close,
          variant: BaraedaButtonVariant.secondary,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case _SignOutChoice.viewQueue:
        unawaited(context.push(AppRoutes.offlineQueue));
      case _SignOutChoice.signOut:
        await _signOut(ref);
      case _SignOutChoice.close || null:
        break;
    }
  }

  /// 아직 서버에 보내지 못한 오프라인 대기 요청 수. 읽지 못하면 0 으로 보고 로그아웃을 막지 않는다.
  Future<int> _pendingCount(WidgetRef ref) async {
    try {
      return (await ref.read(offlineQueueRepositoryProvider).fetchPending())
          .length;
    } on Object {
      return 0;
    }
  }

  Future<void> _signOut(WidgetRef ref) async {
    try {
      await signOut(ref);
    } on Object {
      // signOut 은 서버 호출 실패도 그대로 다시 던진다(토큰은 이미 지워졌다). 보여 줄 추가 동작이 없다 —
      // 라우터가 역할 소실을 보고 로그인 화면으로 보낸다.
    }
  }
}

enum _SignOutChoice { viewQueue, signOut, close }

/// 이름 · 학원 · 역할 칩 + 담당 차량 · 번호판.
class _ProfileCard extends StatelessWidget {
  const new({
    required this.name,
    required this.academy,
    required this.roleLabel,
    required this.busNo,
    required this.plateNo,
  });

  final String? name;
  final String? academy;
  final String roleLabel;
  final String? busNo;
  final String? plateNo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial = (name == null || name!.isEmpty)
        ? ''
        : name!.characters.first;
    return BaraedaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.accentPrimary,
                child: Text(
                  initial,
                  style: BaraedaTypography.title.copyWith(
                    color: colors.textInverse,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BaraedaTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (academy != null)
                      Text(
                        academy!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: BaraedaTypography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accentPrimary,
                  borderRadius: BorderRadius.circular(BaraedaRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    roleLabel,
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textInverse,
                      fontWeight: BaraedaFontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (busNo != null || plateNo != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                children: [
                  if (busNo != null)
                    Expanded(
                      child: _Fact(value: busNo!, label: '담당 차량'),
                    ),
                  if (busNo != null && plateNo != null)
                    VerticalDivider(width: 1, color: colors.borderSubtle),
                  if (plateNo != null)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: busNo == null ? 0 : 16),
                        child: _Fact(value: plateNo!, label: '번호판'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const new({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: BaraedaTypography.body.copyWith(
            fontWeight: BaraedaFontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        Text(
          label,
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 위치 권한 한 줄 — 허용되면 초록 칩, 아니면 누르면 기기 설정으로 간다.
class _LocationRow extends ConsumerWidget {
  const new({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(_locationAvailabilityProvider).value;
    final allowed = availability == PositionAvailability.available;
    return BaraedaListRow(
      leadingIcon: 'map-pin',
      title: '위치 권한',
      subtitle: isDriver
          ? '운행 중 2초마다 버스 위치를 서버로 보내요'
          : '비상 알림을 보낼 때 현재 위치를 함께 보내요',
      trailing: availability == null
          ? null
          : BaraedaStatusPill(
              status: allowed ? BaraedaStatus.boarded : BaraedaStatus.missed,
              label: allowed ? '허용됨' : '꺼져 있음',
            ),
      onTap: allowed || availability == null
          ? null
          : () => unawaited(
              ref.read(settingsOpenerProvider)(
                availability == PositionAvailability.permissionDenied
                    ? DeviceSettingsPage.app
                    : DeviceSettingsPage.location,
              ),
            ),
    );
  }
}

/// 화면이 열릴 때 권한 · 위치 서비스를 한 번 다시 확인한다 — 좌표는 받지 않는다.
final FutureProvider<PositionAvailability> _locationAvailabilityProvider =
    FutureProvider.autoDispose<PositionAvailability>((ref) async {
      final source = ref.watch(positionSourceProvider);
      await source.recheck();
      return source.availability;
    });

/// 오른쪽 끝 — 건수 배지(있을 때) + ›.
class _TrailingChevron extends StatelessWidget {
  const new({this.count = 0});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.dangerSolid,
              borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.onDangerSolid,
                  fontWeight: BaraedaFontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        BaraedaIcon('chevron-right', color: colors.textSecondary),
      ],
    );
  }
}
