import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/bottom_notice_stack.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';

/// 위치 송신 상태의 [PositionAvailability] 를 화면 문구로 옮긴다 — 정상(`available`)이거나
/// 아직 모르면(`null`) 아무것도 보여주지 않는다.
String? positionGuidance(PositionAvailability? availability) =>
    switch (availability) {
      PositionAvailability.permissionDenied => '위치 권한이 꺼져 있어요',
      PositionAvailability.serviceDisabled => '기기 위치 서비스가 꺼져 있어요',
      PositionAvailability.available || null => null,
    };

String? _positionGuidanceBody(PositionAvailability? availability) =>
    availability == null || availability == PositionAvailability.available
    ? null
    : '학부모 화면에 버스 위치가 안 보여요.';

/// 알림을 중요한 순서로 모은다 — 접힌 상태에서는 첫 건만 보인다([BottomNoticeStack]).
/// 도착 처리 실패 > 명단 조회 실패 > 위치 송신 불가 > 카카오내비 미설치 > 길안내 안내 순이다:
/// 지금 조작이 막힌 것을 앞에, 알려 주는 것을 뒤에 둔다.
List<BottomNotice> collectDriveNotices(
  WidgetRef ref, {
  required AsyncValue<RosterResponse> rosterAsync,
  required PositionAvailability? availability,
  required String? errorMessage,
  required bool naviNotInstalled,
  required String? navNotice,
}) {
  final guidance = positionGuidance(availability);
  return [
    if (errorMessage != null)
      BottomNotice(tone: AlertTone.missed, body: errorMessage),
    if (rosterAsync.hasError)
      _rosterFailureNotice(
        ref,
        rosterAsync.error!,
        stale: rosterAsync.hasValue,
      ),
    if (guidance != null)
      BottomNotice(
        tone: AlertTone.missed,
        body: '$guidance ${_positionGuidanceBody(availability)}',
        action: BaraedaButton(
          label: '설정 열기',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: () => unawaited(
            ref.read(settingsOpenerProvider)(
              availability == PositionAvailability.permissionDenied
                  ? DeviceSettingsPage.app
                  : DeviceSettingsPage.location,
            ),
          ),
        ),
      ),
    if (naviNotInstalled)
      BottomNotice(
        tone: AlertTone.missed,
        body: '카카오내비가 설치돼 있지 않아요. 설치한 뒤 다시 눌러 주세요.',
        action: BaraedaButton(
          label: '설치하기',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: () => unawaited(
            ref.read(uriOpenerProvider)(
              ref.read(kakaoNaviLauncherProvider).installUri,
            ),
          ),
        ),
      ),
    if (navNotice != null)
      BottomNotice(tone: AlertTone.moving, body: navNotice),
  ];
}

/// 명단 조회 실패 안내 + [다시 시도]. [stale] 이면 화면의 명단이 마지막 성공분이라는 뜻이다.
BottomNotice _rosterFailureNotice(
  WidgetRef ref,
  Object error, {
  required bool stale,
}) => BottomNotice(
  tone: AlertTone.missed,
  body: stale
      ? '최신 명단을 불러오지 못했어요 · 이전 명단을 보고 있어요: ${describeError(error)}'
      : '명단을 불러오지 못했어요: ${describeError(error)}',
  action: BaraedaButton(
    label: '다시 시도',
    size: BaraedaButtonSize.sm,
    variant: BaraedaButtonVariant.secondary,
    onPressed: () => ref.invalidate(driveModeRosterProvider),
  ),
);
