import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 서버로 가지 못한 채 기기에서 지워진 처리를 사용자가 확인할 때까지 남기는 안내 한 건(Ruling 882).
///
/// 두 곳에서 생긴다 — ①큐 재생이 서버의 확정 거절(4xx)로 행을 지울 때(자동 · 쓰기 직전 · 수동 모두)
/// ②앱 시작 `/me` 거절 · 대기·거절 상태 알림으로 이 계정의 저장분을 정리할 때.
/// 학생 이름이 들어가므로 메모리에만 두고 계정 정리 때 비운다.
/// 비상 신고 안내는 [UnsentEmergencyNotifier] 가 기기에 따로 남긴다(Ruling 886).
class RequestNotice {
  const new({required this.id, required this.title, required this.body});

  /// 확인(닫기) 대상을 가르는 번호 — 같은 내용이 두 번 나와도 서로 다른 안내다.
  final int id;

  /// 결론 한 줄 — 무엇이 지워졌는가.
  final String title;

  /// 학생 · 처리 · 이유(또는 건수).
  final String body;
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
      ref
          .read(unsentEmergencyProvider.notifier)
          .add(
            count: emergencies.length,
            contact: ref.read(academyContactProvider),
          );
    }
    final others = dropped.where((item) => !item.request.isEmergency);
    if (others.isEmpty) return;
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

  /// 사용자가 안내를 확인했다.
  void dismiss(int id) {
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
    final what = studentName == null
        ? request.description
        : '${request.description} · $studentName';
    return RequestNotice(
      id: _nextId++,
      title: '$what — 서버로 보내지 못하고 지워졌어요',
      body: '이유: $reason. 필요하면 다시 처리해 주세요.',
    );
  }
}

/// 서버가 거절해 지워진 비상 신고의 기기 저장 안내 — 사용자가 [확인] 할 때까지 앱을 끄거나 로그아웃해도 남는다
/// (Ruling 886). 앱이 켜질 때 저장분을 읽어 오고, 읽기 · 쓰기는 한 줄로 이어 붙여 서로 덮지 않게 한다.
final NotifierProvider<UnsentEmergencyNotifier, UnsentEmergency?>
unsentEmergencyProvider =
    NotifierProvider<UnsentEmergencyNotifier, UnsentEmergency?>(
      UnsentEmergencyNotifier.new,
    );

class UnsentEmergencyNotifier extends Notifier<UnsentEmergency?> {
  var _tail = Future<void>.value();

  @override
  UnsentEmergency? build() {
    _enqueue(() async {
      final saved = await ref.read(unsentEmergencyStoreProvider).read();
      if (ref.mounted) state = saved;
    });
    return null;
  }

  /// 비상 신고 [count] 건이 전송되지 못하고 지워졌다 — 건수를 더하고 시각을 지금으로, 번호는 [contact] 를 우선한다
  /// (없으면 앞서 남긴 번호 · 기기에 저장된 번호).
  void add({required int count, required String? contact}) {
    _enqueue(() async {
      final previous = state;
      final next = UnsentEmergency(
        count: (previous?.count ?? 0) + count,
        lastAt: ref.read(clockProvider).now(),
        contact:
            contact ??
            previous?.contact ??
            await ref.read(academyContactStoreProvider).read(),
      );
      if (!ref.mounted) return;
      state = next;
      await ref.read(unsentEmergencyStoreProvider).write(next);
    });
  }

  /// 사용자가 확인했다 — 기기의 저장분도 지운다.
  void dismiss() {
    _enqueue(() async {
      if (ref.mounted) state = null;
      await ref.read(unsentEmergencyStoreProvider).clear();
    });
  }

  void _enqueue(Future<void> Function() job) {
    _tail = _tail.then((_) => job());
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
    final hasBanner = notices.isNotEmpty || unsent != null;
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
          title: '이 기기에서 보낸 비상 신고 ${unsent.count}건이 전송되지 않았습니다',
          body: '학원에 직접 알려 주세요 · 마지막 $lastAt',
          action: BaraedaButton(
            label: '확인',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () =>
                ref.read(unsentEmergencyProvider.notifier).dismiss(),
          ),
        ),
        const SizedBox(height: 8),
        AcademyCallCard(lead: '학원에 바로 전화해 주세요', contact: unsent.contact),
      ],
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
