import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';

/// P-09 · API_SPEC §3.14 — 알림 on/off. 학부모는 도착 · 등하원 · 미승차 3개, 학생은 도착 · 운행 시작 2개다.
///
/// 학생이 받는 알림은 도착 · 지연 · 운행 시작뿐이라(`Ruling 411`) 의미 없는 미승차 스위치를 뺀다. 학생의 `운행 시작`은
/// API 에 별도 필드가 없어 `boarding` 에 귀속한다(`Ruling 829`, `UF-P-08`).
///
/// 지연 알림은 설정 항목 자체가 없어(항상 발송, `NotificationSettings` 문서 참고) 스위치 대신 `항상 켜짐` 칩을
/// 둔다.
class NotificationSettingsPanel extends ConsumerWidget {
  const new({required this.isParent, super.key});

  /// 학부모면 `true`(스위치 3개), 학생이면 `false`(스위치 2개).
  final bool isParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const AlertBanner(
        tone: AlertTone.missed,
        body: '알림 설정을 불러오지 못했습니다',
      ),
      data: (settings) =>
          _NotificationSwitches(settings: settings, isParent: isParent),
    );
  }
}

class _NotificationSwitches extends ConsumerStatefulWidget {
  const new({required this.settings, required this.isParent});

  final NotificationSettings settings;
  final bool isParent;

  @override
  ConsumerState<_NotificationSwitches> createState() =>
      _NotificationSwitchesState();
}

class _NotificationSwitchesState extends ConsumerState<_NotificationSwitches> {
  late NotificationSettings _current = widget.settings;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// 서버가 처리한 뒤에야 스위치가 바뀐다(C-10, API_SPEC §1.9) — 응답 전에 먼저 바꾸면
  /// 실패했을 때 거짓 상태가 잠깐 보인다.
  /// 기다리는 동안 스위치를 잠가 같은 요청이 겹쳐 나가지 않게 한다.
  Future<void> _update(NotificationSettings next) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _banner = null;
    });

    try {
      final saved = await ref
          .read(notificationSettingsRepositoryProvider)
          .updateNotificationSettings(next);
      if (!mounted) return;
      setState(() {
        _current = saved;
        _submitting = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      // 값은 건드린 적이 없으므로 되돌릴 것이 없다 — 안내만 띄운다.
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = failureMessage(
          failure,
          fallback: '알림 설정을 바꾸지 못했습니다',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isParent = widget.isParent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSwitch(
          checked: _current.arrive,
          label: '버스 도착 알림',
          sublabel: '버스가 승하차지에 곧 도착할 때',
          disabled: _submitting,
          onChanged: (value) => _update(_current.copyWith(arrive: value)),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSwitch(
          checked: _current.boarding,
          label: isParent ? '등하원 알림' : '운행 시작 알림',
          sublabel: isParent ? '승차 · 하차 · 운행 시작' : '내 버스의 운행이 시작될 때',
          disabled: _submitting,
          onChanged: (value) => _update(_current.copyWith(boarding: value)),
        ),
        if (isParent) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          BaraedaSwitch(
            checked: _current.noShow,
            label: '미승차 알림',
            sublabel: '버스가 왔는데 타지 않았을 때',
            disabled: _submitting,
            onChanged: (value) => _update(_current.copyWith(noShow: value)),
          ),
        ],
        const SizedBox(height: BaraedaSpacing.space2),
        // 지연 알림은 끌 수 없다(NTF-07) — 스위치가 없는 이유를 칩으로 알린다.
        const _AlwaysOnRow(),
        const SizedBox(height: BaraedaSpacing.space2),
        Text(
          '끄면 푸시만 오지 않아요. 알림 목록에는 그대로 남아요.',
          style: BaraedaTypography.bodySm.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (_banner != null) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          AlertBanner(tone: _bannerTone, body: _banner),
        ],
      ],
    );
  }
}

/// `지연 알림 · 버스가 늦으면 항상 알려 드려요 · [항상 켜짐]` — 스위치가 없는 항목.
class _AlwaysOnRow extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const BaraedaListGroup(
      children: [
        BaraedaListRow(
          title: '지연 알림',
          subtitle: '버스가 늦으면 항상 알려 드려요',
          trailing: BaraedaStatusPill(
            status: BaraedaStatus.boarded,
            label: '항상 켜짐',
          ),
        ),
      ],
    );
  }
}
