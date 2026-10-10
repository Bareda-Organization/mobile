import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_photo.dart';

/// 탑승 · 대기 · 미승차 · 미등원 — 나눔명조 큰 숫자 4칸(시안 `.m-stats`).
class RosterStatsCard extends StatelessWidget {
  const new({required this.counts, this.boardedLabel = '탑승', super.key});

  final RosterCounts counts;

  /// 하원은 내리는 쪽이 일이라 `탑승 중` 으로 적는다(시안 `roster-escort--dropoff`).
  final String boardedLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cell(String value, String label, {Color? color}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: BaraedaTypography.h2.copyWith(
                color: color ?? colors.textPrimary,
              ),
            ),
            Text(
              label,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    return BaraedaCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell('${counts.boarded}', boardedLabel),
            VerticalDivider(width: 1, color: colors.borderSubtle),
            cell('${counts.waiting}', '대기'),
            VerticalDivider(width: 1, color: colors.borderSubtle),
            cell('${counts.noShow}', '미승차'),
            VerticalDivider(width: 1, color: colors.borderSubtle),
            cell('${counts.absentN}', '미등원'),
          ],
        ),
      ),
    );
  }
}

/// 명단에서 승하차지 한 곳이 놓이는 자리.
enum RosterStopPhase { arrived, current, upcoming }

/// 승하차지 한 곳 — 머리(번호 원 · 이름 · 부제 · 칩) + 펼치면 학생 행들.
///
/// 지금 곳(다음 도착)은 초록 테두리로 늘 펼쳐 있고, 그 밖의 곳은 접혀 있다가 눌러 펼친다(동승자가 직접 펼칠 수
/// 있다). [children] 은 펼쳤을 때만 그린다 — 학생이 없는 곳은 펼침 단추를 그리지 않는다.
class RosterStopCard extends StatelessWidget {
  const new({
    required this.stop,
    required this.order,
    required this.phase,
    required this.expanded,
    required this.onToggle,
    required this.children,
    super.key,
    this.waitingCount = 0,
    this.noShowCount = 0,
  });

  final RosterStop stop;

  /// 이 목록에서의 번호(1부터) — 서버 `seq` 가 아니다(`Ruling 400`).
  final int order;
  final RosterStopPhase phase;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final int waitingCount;
  final int noShowCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final skipped = stop.change == StopChange.skipped;
    final added = stop.change == StopChange.added;
    final current = phase == RosterStopPhase.current;
    final arrivedAt = stop.arrivedAt;

    final subtitle = skipped
        ? (stop.skipNotice ?? '오늘 탑승 학생 없음')
        : switch (phase) {
            RosterStopPhase.arrived =>
              '${hhmm(arrivedAt!)} 도착 · 학생 ${stop.students.length}명',
            RosterStopPhase.current => '다음 승하차지 · 대기 $waitingCount명',
            RosterStopPhase.upcoming => [
              if (added) '오늘 추가',
              '대기 $waitingCount명',
            ].join(' · '),
          };

    final chip = skipped
        ? (BaraedaStatus.missed, '미경유')
        : noShowCount > 0
        ? (BaraedaStatus.missed, '미승차 $noShowCount')
        : current
        ? (BaraedaStatus.moving, '다음')
        : added
        ? (BaraedaStatus.boarded, '추가')
        : null;

    final header = InkWell(
      onTap: stop.students.isEmpty ? null : onToggle,
      borderRadius: BorderRadius.circular(BaraedaRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Node(order: order, phase: phase, skipped: skipped, added: added),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.body.copyWith(
                      fontWeight: BaraedaFontWeight.bold,
                      color: skipped ? colors.statusMissed : colors.textPrimary,
                      height: 1.3,
                      // 타임라인 · 지도 핀과 같게 — 미경유는 이름에 취소선.
                      decoration: skipped ? TextDecoration.lineThrough : null,
                      decorationColor: colors.statusMissed,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (chip != null) ...[
              const SizedBox(width: 8),
              BaraedaStatusPill(status: chip.$1, label: chip.$2),
            ],
            if (stop.students.isNotEmpty && !current) ...[
              const SizedBox(width: 4),
              BaraedaIcon(
                expanded ? 'chevron-down' : 'chevron-right',
                color: colors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        border: current
            ? Border.all(color: colors.accentPrimary, width: 2)
            : Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (expanded && !skipped)
            for (final child in children) ...[
              Divider(height: 1, color: colors.borderSubtle),
              child,
            ],
        ],
      ),
    );
  }
}

/// 번호 원 — 지금은 앰버 면, 도착한 곳은 초록 면 + 체크, 건너뜀은 빨간 고리, 나머지는 고리.
class _Node extends StatelessWidget {
  const new({
    required this.order,
    required this.phase,
    required this.skipped,
    required this.added,
  });

  final int order;
  final RosterStopPhase phase;
  final bool skipped;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = phase == RosterStopPhase.current;
    final arrived = phase == RosterStopPhase.arrived;
    final ring = skipped
        ? colors.statusMissed
        : added
        ? colors.accentPrimary
        : colors.textPrimary;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current
            ? colors.shapeMoving
            : arrived
            ? colors.accentPrimary
            : colors.surfaceCard,
        border: Border.all(
          color: current
              ? colors.textPrimary
              : arrived
              ? colors.accentPrimary
              : ring,
          width: 2,
        ),
      ),
      child: arrived
          ? BaraedaIcon('check', size: 18, color: colors.textInverse)
          : Text(
              '$order',
              style: BaraedaTypography.caption.copyWith(
                fontWeight: BaraedaFontWeight.bold,
                color: current ? colors.onNow : ring,
              ),
            ),
    );
  }
}

/// 학생 한 명 — 사진(없으면 이름 끝 두 글자) · 이름 · 학급 · 연락처 · 상태 칩, 아래 줄에 단추들.
///
/// 상태 칩은 오른쪽에 늘 보이고 단추는 [actions] 가 이름 아래 한 줄로 놓인다 — 시안은 단추를 칩 자리에서 치우지
/// 않는다. 하원에서 혼자 귀가할 수 없는 학생은 빨간 주의 줄을 붙인다(`can_go_alone == false`).
class RosterStudentTile extends StatelessWidget {
  const new({
    required this.student,
    required this.ride,
    super.key,
    this.photoHeaders,
    this.metaExtra,
    this.actions,
    this.badge,
    this.busy = false,
    this.warnCannotGoAlone = true,
  });

  final RosterStudent student;
  final RideStatus ride;

  /// `can_go_alone == false` 주의 줄을 낼지 — 혼자 귀가 여부는 하원에서만 뜻이 있어 등원 회차에서는 끈다.
  final bool warnCannotGoAlone;
  final Map<String, String>? photoHeaders;

  /// 학급 · 연락처 줄 뒤에 붙일 것(미승차 만료 시각 등).
  final String? metaExtra;
  final Widget? actions;

  /// 칩 대신 보일 배지(금일 삭제 · 전송 대기).
  final Widget? badge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photo = resolveRosterPhoto(
      student.photoUrl,
      baseUrl: ApiConstants.baseUrl,
      authHeaders: photoHeaders,
    );
    final meta = [
      if (student.change == RiderChange.added) '신규',
      student.className,
      student.guardianPhone,
      metaExtra,
    ].whereType<String>().join(' · ');
    final note = student.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    final initials = student.name.length >= 2
        ? student.name.substring(student.name.length - 2)
        : student.name;

    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.statusIdleSoft,
                    borderRadius: BorderRadius.circular(BaraedaRadius.control),
                  ),
                  child: ExcludeSemantics(
                    child: photo == null
                        ? Text(
                            initials,
                            style: BaraedaTypography.title.copyWith(
                              color: colors.textBrand,
                            ),
                          )
                        : Image.network(
                            photo.url,
                            headers: photo.headers,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            // 로딩 중이거나 실패해도 이니셜 자리를 그대로 둔다 — 깨진 이미지를 보이지 않는다.
                            errorBuilder: (_, _, _) => Text(
                              initials,
                              style: BaraedaTypography.title.copyWith(
                                color: colors.textBrand,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 사람 이름은 자르지 않고 줄을 바꾼다(시안 ⑤-4).
                      Text(
                        student.name,
                        style: BaraedaTypography.body.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          color: colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      // 특이사항(RST-02 · M-03) — 학원이 적어 둔 현장 참고 사항.
                      if (hasNote)
                        Text(
                          '특이사항 · $note',
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      if (warnCannotGoAlone && !student.canGoAlone)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              BaraedaIcon(
                                'triangle-alert',
                                size: 16,
                                color: colors.statusMissed,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '혼자 귀가 불가 · 보호자 확인',
                                  style: BaraedaTypography.caption.copyWith(
                                    color: colors.statusMissed,
                                    fontWeight: BaraedaFontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                badge ?? _chip(ride),
              ],
            ),
            if (actions != null) ...[
              const SizedBox(height: 12),
              // 응답을 기다리는 동안 흐려지기만 하면 눌렸는지 알 수 없다 — 단추 옆에 진행 표시를 돌린다(R46).
              if (busy)
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: actions!),
                  ],
                )
              else
                actions!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(RideStatus ride) => switch (ride) {
    RideStatus.waiting => const BaraedaStatusPill(
      status: BaraedaStatus.waiting,
      label: '대기',
    ),
    RideStatus.boarded => const BaraedaStatusPill(
      status: BaraedaStatus.boarded,
      label: '탑승',
    ),
    RideStatus.alighted => const BaraedaStatusPill(
      status: BaraedaStatus.idle,
      label: '하차',
    ),
    RideStatus.missed => const BaraedaStatusPill(
      status: BaraedaStatus.missed,
      label: '미승차',
    ),
    RideStatus.absent => const BaraedaStatusPill(
      status: BaraedaStatus.idle,
      label: '미등원',
    ),
  };
}

/// 전화 단추 — 이름 아래 줄 맨 왼쪽 48 정사각(시안 `.m-btn--icon`).
class RosterCallButton extends StatelessWidget {
  const new({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '보호자에게 전화',
      enabled: onPressed != null,
      excludeSemantics: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: colors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BaraedaRadius.control),
            side: BorderSide(color: colors.borderControl),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BaraedaRadius.control),
            ),
            child: Center(
              child: BaraedaIcon('phone', color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
