import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/roster/domain/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';

/// 미승차 연락 화면의 본문 — 연락 대기 요약 · 진행 타임라인 · 연락 기록과 아래 고정 단추 줄.
class NoShowBody extends ConsumerWidget {
  const new({
    required this.stop,
    required this.student,
    required this.busy,
    required this.error,
    required this.queued,
    required this.onCall,
    required this.onRecord,
    required this.onRevert,
    super.key,
  });

  final RosterStop stop;
  final RosterStudent student;
  final bool busy;
  final String? error;

  /// 방금 남긴 연락 기록이 통신 두절로 기기에 쌓였는가.
  final bool queued;
  final VoidCallback onCall;

  /// 연락 기록 시트를 연다 — 인자는 연락 대기가 끝나는 시각.
  final void Function(DateTime waitEndsAt) onRecord;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noShow = student.noShowCase!;
    final now = ref.watch(clockProvider).now();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // 실패 이유는 맨 위에 둔다 — 아래 이력 · 단추 줄 때문에 화면 밖에 있으면 못 본다.
              if (error != null) ...[
                AlertBanner(tone: AlertTone.missed, body: error),
                const SizedBox(height: 12),
              ],
              if (queued) ...[
                const AlertBanner(
                  tone: AlertTone.info,
                  title: '연락 기록을 기기에 저장했어요',
                  body: '통신이 끊겨 아직 서버에 보내지 못했어요 · 연결되면 자동으로 보내요',
                ),
                const SizedBox(height: 12),
              ],
              _NoShowSummaryCard(
                student: student,
                stop: stop,
                noShow: noShow,
                now: now,
              ),
              const SizedBox(height: 12),
              _NoShowTimeline(noShow: noShow),
              const SizedBox(height: 24),
              _NoShowContactLog(contacts: noShow.contacts),
              const SizedBox(height: 8),
              Center(
                child: BaraedaButton(
                  label: '미승차 되돌리기',
                  icon: 'undo',
                  variant: BaraedaButtonVariant.ghost,
                  onPressed: busy ? null : onRevert,
                ),
              ),
            ],
          ),
        ),
        _NoShowActionBar(
          busy: busy,
          hasGuardian: student.guardianPhone != null,
          onCall: onCall,
          onRecord: () => onRecord(noShow.expiresAt),
        ),
      ],
    );
  }
}

/// 학생 · 승하차지 · 남은 연락 대기 시간 · 진행 막대를 묶은 맨 위 카드.
class _NoShowSummaryCard extends StatelessWidget {
  const new({
    required this.student,
    required this.stop,
    required this.noShow,
    required this.now,
  });

  final RosterStudent student;
  final RosterStop stop;
  final NoShowCase noShow;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = noShow.expiresAt.difference(noShow.startedAt);
    final left = noShow.expiresAt.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;
    final progress = total.inSeconds <= 0
        ? 1.0
        : (1 - remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    String two(int n) => n.toString().padLeft(2, '0');
    final clockText =
        '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}';

    return BaraedaCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Initial(name: student.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: BaraedaTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      [
                        student.className,
                        stop.name,
                      ].whereType<String>().join(' · '),
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const BaraedaStatusPill(
                status: BaraedaStatus.missed,
                label: '미승차',
                size: BaraedaStatusPillSize.lg,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                clockText,
                style: BaraedaTypography.display.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  remaining == Duration.zero ? '연락 대기가 끝났어요' : '연락 대기 남음',
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: colors.accentPrimary,
              backgroundColor: colors.statusIdleSoft,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_hms(noShow.startedAt)} 미승차 처리 · '
            '${hhmm(noShow.expiresAt)} 에 끝나요',
            style: BaraedaTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 관계자 알림 → 보호자 전화 → 학부모 알림 → 보고로 이어지는 진행 순서.
class _NoShowTimeline extends StatelessWidget {
  const new({required this.noShow});

  final NoShowCase noShow;

  @override
  Widget build(BuildContext context) {
    final contacts = noShow.contacts;
    final waitMinutes =
        (noShow.expiresAt.difference(noShow.startedAt).inSeconds / 60).round();
    return BaraedaCard(
      child: StopTimeline(
        stops: [
          Stop(
            name: '관계자에게 알려줬어요',
            address: _hms(noShow.startedAt),
            state: StopState.done,
          ),
          Stop(
            name: '보호자에게 전화',
            address: contacts.isEmpty
                ? '아직 시도하지 않았어요'
                : '${contacts.length}회 시도 · '
                      '${_resultLabel(contacts.last.result)}',
            state: StopState.current,
          ),
          // Ruling 854 — 학부모 알림은 즉시가 아니라 이 승하차지를 출발할 때 나간다.
          const Stop(
            name: '학부모에게는 이 승하차지를 출발할 때 알려요',
            address: '출발 전에 되돌리면 알림이 나가지 않아요',
          ),
          Stop(
            name: '$waitMinutes분이 지나면 관계자에게 보고돼요',
            address: '출발 · 재시도는 관계자 판단이에요',
          ),
        ],
      ),
    );
  }
}

/// 연락 기록 머리줄과 시각순 기록 목록(없으면 안내 문구).
class _NoShowContactLog extends StatelessWidget {
  const new({required this.contacts});

  final List<NoShowContact> contacts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '연락 기록',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Text(
              '${contacts.length}건',
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '아직 남긴 연락 기록이 없어요',
              style: BaraedaTypography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          )
        else
          BaraedaListGroup(
            children: [
              // 서버가 시각순으로 준다 — 화면은 그대로 위에서 아래로 그린다.
              for (final contact in contacts)
                BaraedaListRow(
                  key: ValueKey(
                    'contact-${contact.attemptedAt.toIso8601String()}',
                  ),
                  leadingIcon: contact.attemptType == NoShowAttemptType.call
                      ? 'phone'
                      : 'bell',
                  title:
                      '${_typeLabel(contact.attemptType)} · '
                      '${_resultLabel(contact.result)}',
                  subtitle: _hms(contact.attemptedAt),
                ),
            ],
          ),
      ],
    );
  }
}

/// 화면 아래 고정 단추 줄 — 보호자에게 전화 · 연락 기록 남기기.
class _NoShowActionBar extends StatelessWidget {
  const new({
    required this.busy,
    required this.hasGuardian,
    required this.onCall,
    required this.onRecord,
  });

  final bool busy;

  /// 연결된 보호자 번호가 있는가 — 없으면 전화 단추를 막는다.
  final bool hasGuardian;
  final VoidCallback onCall;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgBase,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BaraedaButton(
                label: '보호자에게 전화',
                icon: 'phone',
                size: BaraedaButtonSize.xl,
                block: true,
                onPressed: busy || !hasGuardian ? null : onCall,
                disabledReason: hasGuardian ? null : '연결된 보호자가 없어요',
              ),
              const SizedBox(height: 8),
              BaraedaButton(
                label: '연락 기록 남기기',
                variant: BaraedaButtonVariant.secondary,
                block: true,
                onPressed: busy ? null : onRecord,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hms(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _typeLabel(NoShowAttemptType type) =>
    type == NoShowAttemptType.call ? '전화' : '문자';

String _resultLabel(NoShowContactResult result) =>
    result == NoShowContactResult.answered ? '응답함' : '무응답';

/// 학생 이름 끝 두 글자 — 사진 없는 아바타(명단 행과 같은 규칙).
class _Initial extends StatelessWidget {
  const new({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initials = name.length >= 2 ? name.substring(name.length - 2) : name;
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.statusIdleSoft,
        borderRadius: BorderRadius.circular(BaraedaRadius.control),
      ),
      child: ExcludeSemantics(
        child: Text(
          initials,
          style: BaraedaTypography.title.copyWith(color: colors.textBrand),
        ),
      ),
    );
  }
}
