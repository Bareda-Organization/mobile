import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 서버로 가지 못한 채 기기에서 지워진 처리를 사용자가 확인할 때까지 남기는 안내 한 건(Ruling 882).
///
/// 두 곳에서 생긴다 — ①큐 재생이 서버의 확정 거절(4xx)로 행을 지울 때(자동 · 쓰기 직전 · 수동 모두)
/// ②앱 시작 `/me` 거절 · 대기·거절 상태 알림으로 이 계정의 저장분을 정리할 때.
class RequestNotice {
  const new({
    required this.id,
    required this.title,
    required this.body,
    this.emergency = false,
    this.contact,
  });

  /// 확인(닫기) 대상을 가르는 번호 — 같은 내용이 두 번 나와도 서로 다른 안내다.
  final int id;

  /// 결론 한 줄 — 무엇이 지워졌는가.
  final String title;

  /// 학생 · 처리 · 이유(또는 건수).
  final String body;

  /// 비상 신고가 서버에 닿지 못한 채 지워졌는가 — 학원 전화 단추를 함께 띄운다.
  final bool emergency;

  /// 학원 전화번호 — 안내를 만드는 순간 값을 잡아 둔다(계정을 정리하면 메모리의 번호가 비워진다).
  final String? contact;
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

  /// 큐 재생이 확정 거절로 지운 처리를 안내로 남긴다 — 한 건이 한 안내다.
  void addDropped(List<DroppedRequest> dropped) {
    final roster = ref.exists(rosterProvider)
        ? ref.read(rosterProvider).value
        : null;
    final contact = ref.read(academyContactProvider);
    state = [
      ...state,
      for (final item in dropped)
        _describeDropped(item, rosterNameOf(roster, item.request), contact),
    ];
  }

  /// 이 계정의 저장분을 정리하며 미전송 처리를 버린 일을 안내로 남긴다(앱 시작 `/me` 거절 · 대기·거절 상태).
  /// [emergencies] 가 있으면 서버에 닿지 못한 비상 신고를 학원에 직접 알리게 한다(`Ruling 616`).
  void addDiscarded({
    required int count,
    required int emergencies,
    required String? contact,
  }) {
    state = [
      ...state,
      RequestNotice(
        id: _nextId++,
        title: '보내지 못한 처리 $count건이 지워졌어요',
        body: emergencies == 0
            ? '계정 상태가 바뀌어 이 기기에 쌓아 둔 처리를 서버로 보낼 수 없어요.'
            : '비상 신고 $emergencies건이 서버에 전달되지 못했으니 학원에 직접 알려 주세요.',
        emergency: emergencies > 0,
        contact: contact,
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

  RequestNotice _describeDropped(
    DroppedRequest item,
    String? studentName,
    String? contact,
  ) {
    final reason = describeFailure(
      ApiFailure(
        statusCode: item.statusCode,
        code: item.code,
        message: item.message.isEmpty ? '서버가 처리를 받지 않았어요' : item.message,
      ),
    );
    final request = item.request;
    if (request.isEmergency) {
      return RequestNotice(
        id: _nextId++,
        title: '비상 신고가 전송되지 않았습니다',
        body:
            '${request.description} · 서버가 거절해 지워졌어요 — $reason. '
            '학원에 직접 알려 주세요.',
        emergency: true,
        contact: contact,
      );
    }
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
    if (notices.isEmpty) return child;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;
    return Column(
      children: [
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
        // 안내가 상태 막대 아래를 차지하므로 아래 화면은 위쪽 안전 영역을 다시 비키지 않는다.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _NoticeBanner extends ConsumerWidget {
  const new({required this.notice});

  final RequestNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlertBanner(
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
        ),
        if (notice.emergency) ...[
          const SizedBox(height: 8),
          AcademyCallCard(lead: '학원에 바로 전화해 주세요', contact: notice.contact),
        ],
      ],
    );
  }
}
