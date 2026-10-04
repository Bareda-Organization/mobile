import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// OfflineQueueScreen — 오프라인 큐 조회·수동 재전송 (API_SPEC §1.7, M-06,
/// UF-E-07).
///
/// 낙관적 UI 를 두지 않는다(§1.9) — 큐에 쌓인 요청은 서버 2xx 를 받기 전까지
/// 계속 "대기 중" 으로 보여준다.
///
/// 이 화면의 버튼은 **수동** 재전송이다 — 자동 재생은 `OfflineQueueAutoSync`
/// (주기)와 `OfflineQueueRepository.sendOrQueue`(다음 쓰기 직전)가 맡으므로,
/// 이 화면을 한 번도 열지 않아도 복구 후 큐는 비워진다(M-06).
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends ConsumerState<OfflineQueueScreen> {
  bool _replaying = false;
  String? _resultMessage;

  /// 재시도 버튼 — `replayPending()` 은 성공·재시도 불가를 이미 큐에서
  /// 제거해 반환하므로, 여기서는 요약 문구만 만들고 목록을 다시 읽는다.
  Future<void> _replay() async {
    setState(() {
      _replaying = true;
      _resultMessage = null;
    });
    // 예외로 끝나도 버튼이 영구히 잠기지 않게 한다(F06-15).
    String message;
    try {
      final result = await ref
          .read(offlineQueueRepositoryProvider)
          .replayPending();
      message = _describeResult(result);
    } on Object {
      message = '재시도를 완료하지 못했습니다';
    }
    if (!mounted) return;
    setState(() {
      _replaying = false;
      _resultMessage = message;
    });
    ref.invalidate(pendingRequestsProvider);
  }

  /// 잘못 눌러 쌓인 건을 큐에서 지운다 — 서버에 아직 반영되지 않은 처리를 버리는 일이고 학부모 알림도 영영
  /// 가지 않으므로, 무엇이 사라지는지 알리고 빨간 단추로 한 번 묻는다(M10).
  Future<void> _cancel(PendingRequestSummary item) async {
    final colors = context.colors;
    final name = _studentNameOf(item);
    final what = name == null ? item.description : '$name ${item.description}';
    final isRider = item.riderId != null;
    final lost = isRider
        ? '학부모에게 ${item.description.replaceAll(' 처리', '')} 알림도 가지 않아요.'
        : '학원에 알림도 가지 않아요.';
    final redo = isRider ? '명단에서 다시 처리' : '화면에서 다시 보내';
    final confirmed = await showBaraedaConfirmDialog(
      context: context,
      title: '$what${_objectParticle(what)} 삭제할까요?',
      content: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '서버가 받지 못한 처리라 삭제하면 사라져요. $lost 지운 뒤에는 '),
            TextSpan(
              text: redo,
              style: const TextStyle(fontWeight: BaraedaFontWeight.bold),
            ),
            const TextSpan(text: '해 주세요.'),
          ],
        ),
        style: BaraedaTypography.body.copyWith(
          color: colors.textSecondary,
          height: 1.5,
        ),
      ),
      confirmLabel: '삭제',
      cancelLabel: '닫기',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final container = ProviderScope.containerOf(context);
    await ref.read(offlineQueueRepositoryProvider).cancel(item.id);
    container.invalidate(pendingRequestsProvider);
  }

  String _describeResult(ReplayResult result) {
    final parts = <String>[
      if (result.succeeded > 0) '${result.succeeded}건 처리됨',
      if (result.stillPending > 0) '${result.stillPending}건 대기 중',
      if (result.droppedPermanently > 0)
        '${result.droppedPermanently}건 재시도 불가로 제외',
      if (result.failedPermanently > 0)
        '${result.failedPermanently}건 전송 실패(서버가 계속 받지 못함)',
    ];
    if (parts.isEmpty) return '대기 중인 처리가 없어요';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingRequestsProvider);
    final items = pendingAsync.value ?? const <PendingRequestSummary>[];
    return Scaffold(
      appBar: const ManagerHeader(title: '대기열'),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(pendingRequestsProvider.future),
              // 목록이 짧아 한꺼번에 만든다 — 화면 밖 행도 위젯 시험이 바로 찾는다.
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_resultMessage != null) ...[
                      AlertBanner(
                        tone: AlertTone.boarded,
                        body: _resultMessage,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (items.isNotEmpty) ...[
                      AlertBanner(
                        tone: AlertTone.moving,
                        icon: 'clock',
                        title: '못 보낸 처리 ${items.length}건',
                        body: '서버가 받기 전까지는 학부모에게 알림이 가지 않아요.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    pendingAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => WordWrapText(
                        '대기열을 불러오지 못했습니다: ${describeError(error)}',
                      ),
                      data: _buildList,
                    ),
                  ],
                ),
              ),
            ),
          ),
          BottomActionBar(
            children: [
              BaraedaButton(
                label: '지금 다시 보내기',
                icon: 'refresh',
                size: BaraedaButtonSize.xl,
                block: true,
                // 보낼 것이 없으면 누를 일이 없다(시안 `offline-queue--empty` 의 꺼진 단추).
                onPressed: _replaying || items.isEmpty ? null : _replay,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<PendingRequestSummary> items) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: 'check',
        title: '대기 중인 처리가 없어요',
        body: '인터넷이 끊겨서 못 보낸 처리는 여기에 쌓여요. 연결되면 자동으로 보내요.',
      );
    }
    final colors = context.colors;
    // 행 전체가 한 카드 안에 있고 선으로 나뉜다(시안). 카드는 전체 폭이다(`Ruling 592` 와 같은 처리).
    return BaraedaCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.borderSubtle),
            _buildRow(items[i]),
          ],
        ],
      ),
    );
  }

  /// 처리 이름에 학생 이름을 덧붙인다(M2-03) — 페이로드에 이름이 없어, 이미 받아 둔 명단(홈·명단 화면이 채운
  /// 캐시)에서 같은 회차·같은 승차 기록을 찾는다. 명단을 새로 받지 않고(오프라인일 수 있다), 못 찾으면 `null`.
  String? _studentNameOf(PendingRequestSummary item) {
    final match = RegExp(r'^/runs/([^/]+)/riders/([^/]+)$')
        .firstMatch(item.endpoint);
    if (match == null || !ref.exists(rosterProvider)) return null;
    final roster = ref.read(rosterProvider).value;
    if (roster == null || roster.runId != match[1]) return null;
    for (final stop in roster.stops) {
      for (final student in stop.students) {
        if (student.riderId == match[2]) return student.name;
      }
    }
    return null;
  }

  String _titleOf(PendingRequestSummary item) {
    final name = _studentNameOf(item);
    return name == null ? item.description : '${item.description} · $name';
  }

  Widget _buildRow(PendingRequestSummary item) {
    final colors = context.colors;
    final time = DateFormat('HH:mm:ss').format(item.createdAt.toLocal());
    // 서버가 5xx 를 되풀이해 재생에서 뺀 행은 더 기다리지 않는다 — 보내지 못했음을 알리고 사용자가 정리한다.
    final detail = item.failed
        ? '$time · 서버가 계속 받지 못했어요. 삭제하고 다시 처리'
        : '$time · 대기 중';
    return Padding(
      key: ValueKey('queue-row-${item.id}'),
      padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titleOf(item),
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
              ),
              BaraedaStatusPill(
                status: item.failed
                    ? BaraedaStatus.missed
                    : BaraedaStatus.waiting,
                label: item.failed ? '전송 실패' : '전송 대기',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: WordWrapText(
                  detail,
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              BaraedaButton(
                label: '삭제',
                size: BaraedaButtonSize.sm,
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => unawaited(_cancel(item)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 목적격 조사 — 마지막 글자에 받침이 있으면 `을`, 없으면 `를`(한글이 아니면 `를`).
String _objectParticle(String word) {
  if (word.isEmpty) return '를';
  final last = word.runes.last;
  if (last < 0xAC00 || last > 0xD7A3) return '를';
  return (last - 0xAC00) % 28 == 0 ? '를' : '을';
}
