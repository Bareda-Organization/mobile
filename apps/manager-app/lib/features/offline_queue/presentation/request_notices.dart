import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/offline_queue/presentation/unsent_tally_notifiers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

export 'package:manager_app/features/offline_queue/presentation/unsent_tally_notifiers.dart';

/// 서버로 가지 못한 채 기기에서 지워진 처리를 사용자가 확인할 때까지 남기는 안내 한 건(Ruling 882).
///
/// 두 곳에서 생긴다 — ①큐 재생이 서버의 확정 거절(4xx)로 행을 지울 때(자동 · 쓰기 직전 · 수동 모두)
/// ②앱 시작 `/me` 거절 · 대기·거절 상태 알림으로 이 계정의 저장분을 정리할 때.
/// 학생 이름이 들어가므로 메모리에만 두고 계정 정리 때 비운다. 이름 없이 건수와 마지막 시각만
/// [DroppedTallyNotifier] 가 기기에 따로 남겨 앱을 껐다 켜도 알린다(Ruling 892).
/// 비상 신고 안내는 [UnsentEmergencyNotifier] 가 기기에 따로 남긴다(Ruling 886).
class RequestNotice {
  const new({
    required this.id,
    required this.title,
    required this.body,
    this.counted = false,
  });

  /// 확인(닫기) 대상을 가르는 번호 — 같은 내용이 두 번 나와도 서로 다른 안내다.
  final int id;

  /// 결론 한 줄 — 무엇이 지워졌는가.
  final String title;

  /// 학생 · 처리 · 이유(또는 건수).
  final String body;

  /// 기기에 남기는 거절 건수([droppedTallyProvider])에 한 건으로 세어진 안내인가 — 확인하면 그 건수도 하나 줄인다.
  final bool counted;
}

/// 지운 처리의 안내 목록 — 사용자가 [RequestNoticesNotifier.dismiss] 로 확인할 때까지 남는다.
final NotifierProvider<RequestNoticesNotifier, List<RequestNotice>>
requestNoticesProvider =
    NotifierProvider<RequestNoticesNotifier, List<RequestNotice>>(
      RequestNoticesNotifier.new,
    );

class RequestNoticesNotifier extends Notifier<List<RequestNotice>> {
  var _nextId = 0;

  @override
  List<RequestNotice> build() => const [];

  /// 큐 재생이 확정 거절로 지운 처리를 안내로 남긴다 — 승하차 · 도착 한 건이 한 안내다. 비상 신고는 기기에 남기는
  /// 안내([unsentEmergencyProvider])로 보낸다(Ruling 886).
  void addDropped(List<DroppedRequest> dropped) {
    final emergencies = dropped.where((item) => item.request.isEmergency);
    if (emergencies.isNotEmpty) {
      unawaited(
        ref
            .read(unsentEmergencyProvider.notifier)
            .add(
              count: emergencies.length,
              contact: ref.read(academyContactProvider),
            ),
      );
    }
    final others = dropped.where((item) => !item.request.isEmergency);
    if (others.isEmpty) return;
    unawaited(
      ref
          .read(droppedTallyProvider.notifier)
          .add(count: others.length, contact: null),
    );
    final roster = ref.exists(rosterProvider)
        ? ref.read(rosterProvider).value
        : null;
    state = [
      ...state,
      for (final item in others)
        _describeDropped(item, rosterNameOf(roster, item.request)),
    ];
  }

  /// 이 계정의 저장분을 정리하며 미전송 처리를 버린 일을 안내로 남긴다(앱 시작 `/me` 거절 · 대기·거절 상태).
  /// 비상 신고 [emergencies] 건은 기기 저장 안내([unsentEmergencyProvider])가
  /// 따로 세므로(호출부가 더한다 · Ruling 886) 여기서는 뺀 나머지만 안내로 남긴다.
  void addDiscarded({required int count, required int emergencies}) {
    final others = count - emergencies;
    if (others <= 0) return;
    state = [
      ...state,
      RequestNotice(
        id: _nextId++,
        title: '보내지 못한 처리 $others건이 지워졌어요',
        body: '계정 상태가 바뀌어 이 기기에 쌓아 둔 처리를 서버로 보낼 수 없어요.',
      ),
    ];
  }

  /// 사용자가 안내를 확인했다 — 기기에 남긴 거절 건수로 세어진 안내면 그 건수도 하나 줄인다.
  void dismiss(int id) {
    if (state.any((notice) => notice.id == id && notice.counted)) {
      ref.read(droppedTallyProvider.notifier).dismiss(1);
    }
    state = [
      for (final notice in state)
        if (notice.id != id) notice,
    ];
  }

  RequestNotice _describeDropped(DroppedRequest item, String? studentName) {
    final reason = describeFailure(
      ApiFailure(
        statusCode: item.statusCode,
        code: item.code,
        message: item.message.isEmpty ? '서버가 처리를 받지 않았어요' : item.message,
      ),
    );
    final request = item.request;
    // 명단(메모리)에서 학생을 못 찾으면 기록 시각으로 대신한다(R53 F3) — 이름 없이는 어느 처리인지 알 수 없다.
    final what = studentName == null
        ? '${request.description} · '
              '${DateFormat('M월 d일 HH:mm').format(request.recordedAt)} 기록'
        : '${request.description} · $studentName';
    return RequestNotice(
      id: _nextId++,
      title: '$what — 서버로 보내지 못하고 지워졌어요',
      body: '이유: $reason. 필요하면 다시 처리해 주세요.',
      counted: true,
    );
  }
}

/// 명단(이미 받아 둔 것)에서 요청이 가리키는 학생의 이름 — 승하차 처리(`/runs/{runId}/riders/{riderId}`)만 해당하고,
/// 같은 회차가 아니거나 못 찾으면 `null`. 큐 행의 본문에는 이름이 없다(M2-03).
String? rosterNameOf(RosterResponse? roster, PendingRequestSummary request) {
  final match = RegExp(r'^/runs/([^/]+)/riders/([^/]+)$')
      .firstMatch(request.endpoint);
  if (match == null || roster == null || roster.runId != match[1]) return null;
  for (final stop in roster.stops) {
    for (final student in stop.students) {
      if (student.riderId == match[2]) return student.name;
    }
  }
  return null;
}

/// 앱 전체 맨 위에 [requestNoticesProvider] 의 안내를 띄우는 통과 위젯 — `MaterialApp.router` 의
/// `builder` 에 건다.
/// 안내가 없으면 [child] 를 그대로 돌려준다. 운행 중 화면 · 비상 화면 · 로그인 화면 어디에 있든 보이고, 사용자가
/// [확인] 을 누를 때까지 남는다.
class RequestNoticesHost extends ConsumerWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(requestNoticesProvider);
    final unsent = ref.watch(unsentEmergencyProvider);
    // 이번 실행에서 이름과 함께 띄운 안내는 따로 있으니, 기기에 남긴 건수에서 그만큼은 뺀다 — 앱을 껐다 켜거나 로그아웃으로
    // 이름 안내가 비면 남은 건수가 이름 없이 뜬다(Ruling 892).
    final droppedTally = ref.watch(droppedTallyProvider);
    final restored =
        (droppedTally?.count ?? 0) -
        notices.where((notice) => notice.counted).length;
    final hasBanner = notices.isNotEmpty || unsent != null || restored > 0;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;
    // 안내가 있든 없든 [child] 는 같은 자리에 둔다 — 안내가 뜨고 지워질 때 아래 화면(내비게이터)이 새로 만들어져
    // 입력 중인 내용과 화면 이동 상태를 잃지 않게 한다.
    return Column(
      children: [
        if (!hasBanner)
          const SizedBox.shrink()
        else
          Material(
            color: context.colors.bgBase,
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (unsent != null) ...[
                        _UnsentEmergencyBanner(unsent: unsent),
                        const SizedBox(height: 8),
                      ],
                      if (droppedTally != null && restored > 0) ...[
                        _DroppedTallyBanner(
                          count: restored,
                          lastAt: droppedTally.lastAt,
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final notice in notices) ...[
                        _NoticeBanner(notice: notice),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 안내가 상태 막대 아래를 차지하는 동안 아래 화면은 위쪽 안전 영역을 다시 비키지 않는다.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: hasBanner,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 기기에 남긴 비상 신고 미전송 안내 — [확인] 전까지 로그인 화면을 포함한 어느 화면에서나 보인다(Ruling 886).
class _UnsentEmergencyBanner extends ConsumerWidget {
  const new({required this.unsent});

  final UnsentEmergency unsent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastAt = DateFormat('M월 d일 HH:mm').format(unsent.lastAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlertBanner(
          tone: AlertTone.missed,
          title: '이 기기에서 보낸 비상 신고 ${unsent.count}건이 전송되지 않았어요',
          body: '학원에 직접 알려 주세요 · 마지막 $lastAt',
          action: BaraedaButton(
            label: '확인',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => ref
                .read(unsentEmergencyProvider.notifier)
                .dismiss(unsent.count),
          ),
        ),
        const SizedBox(height: 8),
        // 그때 저장한 번호만 쓴다(R53 F4) — 번호가 없다고 지금 로그인한 계정의 학원 번호로 대신하면, 다른 학원에서
        // 보낸 비상 신고 안내가 엉뚱한 학원 전화로 이어진다.
        if (looksLikePhoneNumber(unsent.contact))
          AcademyCallCard(lead: '학원에 바로 전화해 주세요', contact: unsent.contact)
        else
          const BaraedaCard(
            tone: BaraedaCardTone.mist,
            child: WordWrapText('학원 번호를 몰라요 · 학원에 직접 연락해 주세요'),
          ),
      ],
    );
  }
}

/// 기기에 남긴 승하차·도착 거절 안내 — 학생 이름 없이 건수와 마지막 시각만 보인다. [확인] 전까지 남는다(Ruling 892).
class _DroppedTallyBanner extends ConsumerWidget {
  const new({required this.count, required this.lastAt});

  final int count;
  final DateTime lastAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = DateFormat('M월 d일 HH:mm').format(lastAt.toLocal());
    return AlertBanner(
      tone: AlertTone.missed,
      title: '서버로 보내지 못하고 지워진 처리가 $count건 있어요',
      body: '필요하면 다시 처리해 주세요 · 마지막 $at',
      action: BaraedaButton(
        label: '확인',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: () => ref.read(droppedTallyProvider.notifier).dismiss(count),
      ),
    );
  }
}

class _NoticeBanner extends ConsumerWidget {
  const new({required this.notice});

  final RequestNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertBanner(
      tone: AlertTone.missed,
      title: notice.title,
      body: notice.body,
      action: BaraedaButton(
        label: '확인',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: () =>
            ref.read(requestNoticesProvider.notifier).dismiss(notice.id),
      ),
    );
  }
}
