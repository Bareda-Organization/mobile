import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/manager_connection.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/ui/saved_runs_notice.dart';
import 'package:manager_app/features/home/domain/models/manager_run.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_list.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_screen_parts.dart';

/// 명단 화면의 뼈대 — 머리글(부제 · 연결 끊김 띠)과, 선택된 회차가 있을 때 본문.
class RosterView extends ConsumerWidget {
  const new({required this.interaction, super.key});

  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(selectedManagerRunProvider);
    final roster = ref.watch(rosterProvider).value;
    final offlineSince = runId == null
        ? null
        : ref.watch(managerOfflineSinceProvider(runId));
    return Scaffold(
      appBar: ManagerHeader(
        title: '명단',
        subtitle: _subtitleOf(roster, run, readOnly: interaction.readOnly),
        // 탭으로 열린 명단은 뒤로 갈 곳이 없다 — 기사의 조회 전용만 뒤로 가기가 있다.
        onBack: interaction.readOnly
            ? () => Navigator.of(context).maybePop()
            : null,
        // 연결이 끊겨 있으면 맨 위에 언제부터인지 띠로 알린다(시안 `roster-escort--offline`).
        strip: offlineSince == null
            ? null
            : BaraedaConnectionStrip(
                state: BaraedaConnectionState.offline,
                message: '인터넷 연결 없음 · ${hhmm(offlineSince)} 부터',
              ),
      ),
      body: runId == null
          ? const EmptyState(
              icon: 'list',
              title: '선택된 회차가 없어요',
              body: '회차 탭에서 오늘 운행을 골라 주세요.',
            )
          : _RosterBody(runId: runId, interaction: interaction),
    );
  }
}

String? _subtitleOf(
  RosterResponse? roster,
  ManagerRun? run, {
  required bool readOnly,
}) {
  final bus = roster?.busNo ?? run?.busNo;
  final direction = roster?.direction ?? run?.direction;
  if (bus == null || direction == null) return null;
  final tail = readOnly
      ? '조회 전용'
      : run == null
      ? null
      : run.runStatus == RunStatus.moving
      ? '운행 중'
      : '${hhmm(run.departTime)} 출발';
  return [bus, directionLabel(direction), ?tail].join(' · ');
}

/// 명단 본문 — 저장본 안내 · 연결 띠 아래에서 명단 상태(불러오는 중 · 오류 · 목록)를 가른다.
class _RosterBody extends ConsumerWidget {
  const new({required this.runId, required this.interaction});

  final String runId;
  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(rosterProvider);
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canDecide =
        !interaction.readOnly &&
        (capabilities?.canDecideBoardingStatus ?? false);
    final run = ref.watch(selectedManagerRunProvider);

    // ManagerChannelBanner 는 rosterAsync.when(...) 의 모든 분기 바깥에 둔다 — "명단
    // 없음"(정상, data 분기)과
    // "연결 끊김"(비정상)이 화면에서 구별돼야 한다(ManagerChannelBanner 문서 참고).
    return Column(
      children: [
        // 오늘 회차 목록이 저장본이면 홈과 같은 안내를 맨 위에 띄운다.
        const SavedRunsBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          // 재연결 중은 맨 위 연결 끊김 띠가 알린다 — 같은 사건을 두 번 알리지 않는다.
          child: ManagerChannelBanner(runId: runId, hideReconnecting: true),
        ),
        Expanded(
          // 갱신이 실패해도 마지막으로 받은 명단을 지우지 않는다 — 오류는 목록 위에 따로 알린다.
          child: rosterAsync.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const RosterSkeleton(),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 40),
                EmptyState(
                  icon: 'wifi-off',
                  title: '명단을 불러오지 못했어요',
                  body: '${describeError(error)}\n연결되면 자동으로 다시 불러와요.',
                  action: BaraedaButton(
                    label: '다시 시도',
                    icon: 'refresh',
                    onPressed: () => ref.invalidate(rosterProvider),
                  ),
                ),
              ],
            ),
            data: (roster) => RosterList(
              runId: runId,
              canDecide: canDecide,
              run: run,
              roster: roster,
              interaction: interaction,
            ),
          ),
        ),
      ],
    );
  }
}
