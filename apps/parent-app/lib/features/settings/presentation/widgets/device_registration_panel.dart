import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:uuid/uuid.dart';

/// AUTH-11 · API_SPEC §2.11 — 이 기기의 푸시 알림 수신 등록.
///
/// **`pending` 상태에서도 동작해야 한다**(§2.11 "인증된 전 역할 —
/// `pending` 포함, 승인 결과 알림이 대상") — 그래서 이 위젯은 계정 상태를
/// 스스로 확인하지 않는다. 이 화면 자체가 `pending` 계정에서 실제로
/// 열리는지는 `router.dart`(F2 소유, 이번 범위 밖)가 결정한다 — 보고서
/// §2 참고.
///
/// 이 저장소에는 FCM·APNs SDK 가 없다(`baraeda_core`·앱 어디에도 부재,
/// 확인됨) — 그래서 `token` 은 실제 푸시 토큰이 아니라 기기별로 한 번만
/// 만드는 자리표시 값이다. 실제 SDK 연동은 이번 범위 밖.
class DeviceRegistrationPanel extends ConsumerStatefulWidget {
  const DeviceRegistrationPanel({super.key});

  @override
  ConsumerState<DeviceRegistrationPanel> createState() =>
      _DeviceRegistrationPanelState();
}

class _DeviceRegistrationPanelState
    extends ConsumerState<DeviceRegistrationPanel> {
  bool? _registered;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = await ref
        .read(deviceRegistrationStorageProvider)
        .readToken();
    if (!mounted) return;
    setState(() => _registered = token != null);
  }

  String get _platform => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'web',
  };

  Future<void> _toggle(bool value) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _banner = null;
    });

    final storage = ref.read(deviceRegistrationStorageProvider);
    final repository = ref.read(authRepositoryProvider);

    try {
      if (value) {
        final deviceId = await storage.readOrCreateDeviceId();
        final token = const Uuid().v4();
        await repository.registerDevice(
          DeviceRegistrationRequest(
            token: token,
            platform: _platform,
            deviceId: deviceId,
          ),
        );
        await storage.saveToken(token);
      } else {
        final token = await storage.readToken();
        if (token != null) {
          await repository.unregisterDevice(token);
        }
        await storage.clearToken();
      }
      if (!mounted) return;
      setState(() {
        _registered = value;
        _submitting = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(:final message) => message,
          _ => '기기 등록 상태를 바꾸지 못했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_registered == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSwitch(
          checked: _registered!,
          label: '이 기기에서 알림 받기',
          sublabel: '꺼두면 이 기기로는 푸시 알림이 오지 않습니다',
          disabled: _submitting,
          onChanged: _toggle,
        ),
        if (_banner != null) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          AlertBanner(tone: _bannerTone, body: _banner),
        ],
      ],
    );
  }
}
