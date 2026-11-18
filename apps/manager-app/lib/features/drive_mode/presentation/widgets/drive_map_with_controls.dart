import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/navigation/domain/models/navigation_scope.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

/// 지도 + 왼쪽 위 [다음 목적지] · [남은 전 구간] 두 단추 · 오른쪽 아래 `크게 보기`
/// (노선 지도 화면, `Ruling 829`).
class DriveMapWithControls extends StatelessWidget {
  const new({
    required this.height,
    required this.transmission,
    this.showNavigation = false,
    this.onNavigation,
    super.key,
  });

  final double height;
  final PositionTransmission transmission;

  /// 길안내 두 단추를 그릴지 — 누를 수 없을 때도(여는 중) 자리는 유지한다.
  final bool showNavigation;

  /// null 이면 길안내 단추가 비활성으로 그려진다.
  final void Function(NavigationScope scope)? onNavigation;

  @override
  Widget build(BuildContext context) {
    final onNavigation = this.onNavigation;
    return Stack(
      children: [
        DriveMapPanel(height: height, busPosition: transmission.busPosition),
        if (showNavigation)
          Positioned(
            left: 8,
            top: 8,
            right: 64,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BaraedaMapButton(
                  icon: 'navigation',
                  label: '다음 목적지',
                  semanticLabel: '카카오내비',
                  onPressed: onNavigation == null
                      ? null
                      : () => onNavigation(NavigationScope.next),
                ),
                BaraedaMapButton(
                  icon: 'route',
                  label: '남은 전 구간',
                  semanticLabel: '카카오내비',
                  onPressed: onNavigation == null
                      ? null
                      : () => onNavigation(NavigationScope.remaining),
                ),
              ],
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: BaraedaMapButton(
            icon: 'map',
            semanticLabel: '노선 크게 보기',
            onPressed: () => unawaited(context.push(AppRoutes.routeMap)),
          ),
        ),
      ],
    );
  }
}
