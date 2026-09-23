import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:uuid/uuid.dart';

/// NTF-12 · API_SPEC §2.11 — 이 기기의 푸시 알림 수신 등록. (이전 판은
/// `AUTH-11` 로 잘못 표기돼 있었다 — `FEATURE_SPEC.md:269` 의 `AUTH-11` 은
/// "계정↔레코드 연결"이라 이 기능과 무관하고, `FEATURE_SPEC.md:688` 의
/// `NTF-12` "푸시 단말 등록·해지 — 전 역할, `pending` 포함"이 정확히
/// 이 위젯을 가리킨다. P2 수정 라운드에서 화면×기능ID 표를 만들다 발견,
/// 역할 분기와는 무관한 별도 결함.)
///
/// **`pending` 상태에서도 동작해야 한다**(§2.11 "인증된 전 역할 —
/// `pending` 포함, 승인 결과 알림이 대상") — 그래서 이 위젯은 계정 상태를
/// 스스로 확인하지 않는다. `router.dart` 는 `pending`·`rejected` 계정을
/// 예외 없이 `PendingApprovalScreen` 으로 보내므로(§2.11 Ruling 267 —
/// router 는 고치지 않는다), 그 화면이 이 패널을 직접 품어 `pending`
/// 계정도 단말 등록에 접근할 수 있게 한다. `features/settings` 의
/// `SettingsScreen` 도 (active 계정 대상으로) 같은 위젯을 그대로 쓴다 —
/// `core/devices` 로 승격한 이유가 이 두 feature 의 공유다.
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
    final token = await ref.read(deviceRegistrationStorageProvider).readToken();
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
    // `_registered` 는 mutable `State` 필드라 null 체크만으로는 흐름
    // 분석이 non-nullable 로 승격해 주지 않는다(CONVENTIONS_FLUTTER.md
    // §9, null-assertion 금지) — 지역 변수로 먼저 붙잡아 `registered` 를
    // 쓴다.
    final registered = _registered;
    if (registered == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSwitch(
          checked: registered,
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
