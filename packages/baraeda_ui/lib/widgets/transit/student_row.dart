// 탑승자 명단의 한 줄 — 매니저 앱 정류장별 명단, 관계자 웹 학생 명부 공통.
// 원본: `frontend/design-system/components/transit/StudentRow.jsx`.

import 'dart:math' as math;

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:flutter/material.dart';

const double _avatarWidth = 38;

/// 이름·번호 칸의 최소 폭 — 13자리 번호가 한 줄에 들어가는 폭이다.
const double _nameMinWidth = 140;

/// 동승자 앱이 결정하는 탑승 상태.
enum RideStatus { boarded, alighted, absent, missed, waiting }

class _RideMeta {
  const _RideMeta(this.label, this.status);

  final String label;
  final BaraedaStatus status;

  static const _table = {
    RideStatus.boarded: _RideMeta('탑승 완료', BaraedaStatus.boarded),
    RideStatus.alighted: _RideMeta('하차 완료', BaraedaStatus.boarded),
    RideStatus.absent: _RideMeta('미등원', BaraedaStatus.idle),
    RideStatus.missed: _RideMeta('미승차', BaraedaStatus.missed),
    RideStatus.waiting: _RideMeta('대기', BaraedaStatus.idle),
  };

  static _RideMeta of(RideStatus ride) => _table[ride]!;
}

/// 탑승자 명단 한 줄.
class StudentRow extends StatelessWidget {
  const StudentRow({
    super.key,
    this.name,
    this.photoUrl,
    this.photoHeaders,
    this.meta,
    this.phone,
    this.ride = RideStatus.waiting,
    this.selected = false,
    this.onSelect,
    this.onCall,
    this.actions,
  });

  final String? name;

  /// 육안 확인용 사진 — §4.2. **미등록 학생이 예외가 아니라 기본 상태**라
  /// `null` 이면 이름 뒤 2자 이니셜로 대체한다(2026-09-14 계약 확정).
  /// URL 이 있어도 로딩 중이거나 로드에 실패하면 같은 이니셜 자리로
  /// 떨어진다 — 깨진 이미지 아이콘을 보여주지 않는다.
  final String? photoUrl;

  /// 사진 요청에 실을 헤더 — 사진이 로그인 토큰을 요구한다(Ruling 377). 이 패키지는
  /// 토큰을 모르므로 앱이 `Authorization` 을 만들어 넘긴다. 공개 주소면 `null`.
  final Map<String, String>? photoHeaders;

  /// 정류장 · 반 · 보호자 등 한 줄.
  final String? meta;
  final String? phone;
  final RideStatus ride;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onCall;

  /// 상태 pill 대신 넣을 컨트롤(탑승/미등원/하차 전환 버튼).
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rideMeta = _RideMeta.of(ride);
    final initials = name != null && name!.length >= 2
        ? name!.substring(name!.length - 2)
        : (name ?? '');

    return Semantics(
      button: onSelect != null,
      selected: selected,
      child: Material(
        color: selected ? colors.bgSubtle : colors.surfaceCard,
        child: InkWell(
          onTap: onSelect,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space4,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  Container(
                    width: _avatarWidth,
                    height: _avatarWidth,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colors.bgSubtle,
                      shape: BoxShape.circle,
                    ),
                    // 이니셜은 이름을 줄인 그림일 뿐이라 낭독하지 않는다 — 이름 Text 가 읽는다(F07-10).
                    child: ExcludeSemantics(
                      child: _StudentAvatar(
                        photoUrl: photoUrl,
                        photoHeaders: photoHeaders,
                        initials: initials,
                        textColor: colors.textBrand,
                      ),
                    ),
                  ),
                  const SizedBox(width: BaraedaSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (name != null)
                          Text(
                            name!,
                            style: BaraedaTypography.bodySm.copyWith(
                              height: 1.4,
                              fontWeight: BaraedaFontWeight.medium,
                            ),
                          ),
                        if (meta != null)
                          Text(
                            meta!,
                            style: BaraedaTypography.micro.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (phone != null && onCall != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: BaraedaSpacing.space2,
                      ),
                      child: _CallButton(onCall: onCall!),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: BaraedaSpacing.space2),
                    // 이름·번호 칸이 [_nameMinWidth] 밑으로 좁아지지 않도록 오른쪽 컨트롤의 폭을 제한한다 —
                    // 안 그러면 큰 글자·좁은 폭에서 이름이 한 글자씩 세로로 쪼개진다(R46). 넘치는 컨트롤은
                    // 자기 안에서 다음 줄로 넘어간다(`Wrap`).
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          0,
                          box.maxWidth -
                              _avatarWidth -
                              BaraedaSpacing.space3 -
                              BaraedaSpacing.space2 -
                              (phone != null && onCall != null
                                  ? BaraedaSpacing.space2 +
                                        BaraedaSpacing.tapMin
                                  : 0) -
                              _nameMinWidth,
                        ),
                      ),
                      child:
                          actions ??
                          BaraedaStatusPill(
                            status: rideMeta.status,
                            label: rideMeta.label,
                            dot: false,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 명단 행 아바타 — §4.2 대체 표시 규칙.
/// `photoUrl` 이 없으면(널 허용, 미등록이 기본 상태) 곧장 이니셜.
/// 있으면 이미지를 그리되, **로딩 중이거나 로드에 실패해도 이니셜
/// 자리를 그대로 유지**한다(깨진 이미지 아이콘·에러 화면을 보여주지 않음).
class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar({
    required this.photoUrl,
    required this.photoHeaders,
    required this.initials,
    required this.textColor,
  });

  final String? photoUrl;
  final Map<String, String>? photoHeaders;
  final String initials;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return _initials();
    }
    return Image.network(
      url,
      headers: photoHeaders,
      width: 38,
      height: 38,
      // 38px 자리에 원본(수 MP)을 그대로 디코딩하면 행 수만큼 메모리가 오른다.
      cacheWidth: (38 * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      // `loadingBuilder` 의 progress 는 "시작 전"과 "다 됨"이 똑같이 null
      // 이라 두 상태를 못 가른다. `frameBuilder` 의 frame 은 프레임이 실제로
      // 디코드된 뒤에만 null 이 아니므로, 로딩 중(첫 프레임 전)과 완료를
      // 정확히 가를 수 있다.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded || frame != null ? child : _initials(),
      errorBuilder: (context, error, stackTrace) => _initials(),
    );
  }

  Widget _initials() {
    return Text(
      initials,
      style: BaraedaTypography.labelSm.copyWith(
        fontSize: 14,
        height: 1,
        fontWeight: BaraedaFontWeight.bold,
        color: textColor,
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.onCall});

  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '보호자에게 연락',
      child: Material(
        color: colors.surfaceCard,
        shape: CircleBorder(side: BorderSide(color: colors.borderSubtle)),
        child: InkWell(
          onTap: onCall,
          customBorder: const CircleBorder(),
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          // 도로 위에서 누르는 버튼이라 터치 영역은 최소 48 이다(F07-10).
          child: SizedBox(
            width: BaraedaSpacing.tapMin,
            height: BaraedaSpacing.tapMin,
            child: Center(
              child: BaraedaIcon(
                'phone',
                size: 18,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
