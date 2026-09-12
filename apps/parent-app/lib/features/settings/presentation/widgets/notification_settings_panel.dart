import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';

/// P-09 · API_SPEC §3.14 — 알림 항목 3개(도착·등하원·미승차) on/off.
///
/// 지연 알림은 설정 항목 자체가 없어(항상 발송, `NotificationSettings`
/// 문서 참고) 스위치를 두지 않는다.
class NotificationSettingsPanel extends ConsumerWidget {
  const NotificationSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const AlertBanner(
        tone: AlertTone.missed,
        body: '알림 설정을 불러오지 못했습니다',
      ),
      data: (settings) => _NotificationSwitches(settings: settings),
    );
  }
}

class _NotificationSwitches extends ConsumerStatefulWidget {
  const _NotificationSwitches({required this.settings});

  final NotificationSettings settings;

  @override
  ConsumerState<_NotificationSwitches> createState() =>
      _NotificationSwitchesState();
}

class _NotificationSwitchesState
    extends ConsumerState<_NotificationSwitches> {
  late NotificationSettings _current = widget.settings;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  Future<void> _update(NotificationSettings next) async {
    if (_submitting) return;
    final previous = _current;
    setState(() {
      _current = next;
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
      setState(() {
        // 서버가 거부한 값을 화면에 남겨 두지 않는다 — 되돌린다.
        _current = previous;
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(:final message) => message,
          _ => '알림 설정을 바꾸지 못했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSwitch(
          checked: _current.arrive,
          label: '버스 도착 알림',
          disabled: _submitting,
          onChanged: (value) => _update(_current.copyWith(arrive: value)),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSwitch(
          checked: _current.boarding,
          label: '등하원 알림',
          sublabel: '승차 · 하차 · 운행 시작',
          disabled: _submitting,
          onChanged: (value) => _update(_current.copyWith(boarding: value)),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSwitch(
          checked: _current.noShow,
          label: '미승차 알림',
          disabled: _submitting,
          onChanged: (value) => _update(_current.copyWith(noShow: value)),
        ),
        if (_banner != null) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          AlertBanner(tone: _bannerTone, body: _banner),
        ],
      ],
    );
  }
}
