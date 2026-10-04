// 부품 견본 — `mkit/kit.html` 의 절 순서대로 R48 부품을 한 화면에 늘어놓는다.
// 화면을 눈으로 확인하거나 다음 갈래가 부품을 고를 때 본다.
//
// ⚠ **앱 빌드에 들어가지 않는다.** `lib/baraeda_ui.dart` 가 이 파일을 내보내지 않고
// (`export` 없음) 앱 어디에서도 가져오지 않는다 — Dart 는 가져온 라이브러리만 컴파일한다.
// 띄우려면 임시 진입점에서 `package:baraeda_ui/widgets/dev/kit_gallery.dart` 를 직접 가져온다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 부품 견본 화면. [dark] 가 true 면 다크 구역 색으로, [initialScrollOffset] 으로
/// 위쪽 · 아래쪽 절을 나눠 볼 수 있다.
class KitGallery extends StatefulWidget {
  const new({super.key, this.dark = false, this.initialScrollOffset = 0});

  /// true 면 다크 구역(운행 모드) 색으로 그린다.
  final bool dark;
  final double initialScrollOffset;

  @override
  State<KitGallery> createState() => _KitGalleryState();
}

class _KitGalleryState extends State<KitGallery> {
  String _segment = 'today';
  bool _alarm = true;
  bool _pickedWait = false;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = widget.dark ? BaraedaTheme.dark() : BaraedaTheme.light();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        appBar: AppHeader(
          title: '부품 견본',
          subtitle: '바래다 리디자인판 · 앱 부품',
          actions: BaraedaSosButton(onPressed: () {}),
        ),
        bottomNavigationBar: BaraedaTabBar(
          currentIndex: _tab,
          onChanged: (i) => setState(() => _tab = i),
          items: const [
            BaraedaTabItem(icon: 'list', label: '명단'),
            BaraedaTabItem(icon: 'bus', label: '회차'),
            BaraedaTabItem(icon: 'bell', label: '알림', badge: 2),
            BaraedaTabItem(icon: 'user-round', label: '내 정보'),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            controller: ScrollController(
              initialScrollOffset: widget.initialScrollOffset,
            ),
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
            children: [
              ..._chips(),
              ..._buttons(context),
              ..._forms(),
              ..._rows(),
              ..._feedback(context),
              ..._cards(),
              ..._mapParts(),
            ],
          ),
        ),
      ),
    );
  }

  // ── 구역 제목 ──
  Widget _h(String text) => Padding(
    padding: const EdgeInsets.only(
      top: BaraedaSpacing.space5,
      bottom: BaraedaSpacing.space2,
    ),
    child: Text(
      text,
      style: BaraedaTypography.micro.copyWith(
        color: BaraedaColors.light.textSecondary,
        fontWeight: BaraedaFontWeight.bold,
      ),
    ),
  );

  List<Widget> _chips() => [
    _h('상태 칩 5종 · 종료 ■ 이동 중 ▶ 확정 ● 대기 ○ 위험 ▲'),
    const Wrap(
      spacing: BaraedaSpacing.space2,
      runSpacing: BaraedaSpacing.space2,
      children: [
        BaraedaStatusPill(status: BaraedaStatus.idle, label: '종료'),
        BaraedaStatusPill(status: BaraedaStatus.moving, label: '이동 중'),
        BaraedaStatusPill(status: BaraedaStatus.boarded, label: '확정'),
        BaraedaStatusPill(status: BaraedaStatus.waiting, label: '대기'),
        BaraedaStatusPill(status: BaraedaStatus.missed, label: '미승차'),
        BaraedaStatusPill(
          status: BaraedaStatus.idle,
          label: '미등원(회색 끝남)',
          size: BaraedaStatusPillSize.lg,
        ),
      ],
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    const Wrap(
      spacing: BaraedaSpacing.space2,
      children: [
        BaraedaFilterPill(label: '전체 14', selected: true),
        BaraedaFilterPill(label: '운행 중'),
        BaraedaFilterPill(label: '종료'),
      ],
    ),
  ];

  List<Widget> _buttons(BuildContext context) => [
    _h('버튼 · 44 · 48 · 64'),
    BaraedaButton(label: '주 버튼 48', block: true, onPressed: () {}),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '보조 버튼 48',
      variant: BaraedaButtonVariant.secondary,
      block: true,
      onPressed: () {},
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '고스트 버튼 48',
      variant: BaraedaButtonVariant.ghost,
      block: true,
      onPressed: () {},
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '위험 버튼 48',
      variant: BaraedaButtonVariant.danger,
      icon: 'triangle-alert',
      block: true,
      onPressed: () {},
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButtonRow(
      children: [
        BaraedaButton(
          label: '탑승',
          size: BaraedaButtonSize.sm,
          onPressed: () {},
        ),
        BaraedaButton(
          label: '미승차',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: () {},
        ),
      ],
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '큰 주 버튼 64',
      size: BaraedaButtonSize.xl,
      icon: 'bus',
      block: true,
      onPressed: () {},
    ),
    _h('UX 개선 부품 · 꺼진 단추 + 이유 · 단추 안 긴 이름'),
    const BaraedaButton(
      label: '변경하기',
      block: true,
      disabledReason: '새 비밀번호를 입력하면 눌러요',
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    BaraedaButton(
      label: '도착 처리',
      name: '새솔초등학교 정문 건너편 버스정류장 앞',
      size: BaraedaButtonSize.xl,
      icon: 'check',
      block: true,
      onPressed: () {},
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    BaraedaButton(
      label: '토스트 띄우기',
      variant: BaraedaButtonVariant.soft,
      block: true,
      onPressed: () => showBaraedaToast(
        context,
        message: '새솔초 정문 도착 처리했어요 · 12:36',
        actionLabel: '되돌리기',
        onAction: () {},
      ),
    ),
  ];

  List<Widget> _forms() => [
    _h('구간 선택 · 입력 칸 · 스위치'),
    BaraedaSegmentedControl(
      block: true,
      value: _segment,
      onChanged: (v) => setState(() => _segment = v),
      options: const [
        BaraedaSegmentedOption('today', label: '오늘'),
        BaraedaSegmentedOption('tomorrow', label: '내일'),
      ],
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    const BaraedaInput(
      label: '아이디',
      hint: '아이디를 입력하세요',
      kind: BaraedaInputKind.username,
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    const BaraedaInput(
      label: '비밀번호',
      error: '비밀번호가 올바르지 않아요 (남은 시도 3회)',
      kind: BaraedaInputKind.currentPassword,
      obscureText: true,
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaSwitch(
      checked: _alarm,
      label: '오늘 탑승',
      sublabel: '잔여 변경 1회',
      onChanged: (v) => setState(() => _alarm = v),
    ),
    BaraedaSwitch(
      checked: _pickedWait,
      label: '도착 알림',
      sublabel: '꺼짐',
      onChanged: (v) => setState(() => _pickedWait = v),
    ),
  ];

  List<Widget> _rows() => [
    _h('목록 칸 · 높이 56 이상 · 보조 줄 두 줄까지'),
    BaraedaListGroup(
      children: [
        BaraedaListRow(
          leadingIcon: 'bus',
          title: '2호차 등원',
          subtitle: '12:20 출발 · 푸른아파트 앞',
          trailing: const BaraedaStatusPill(
            status: BaraedaStatus.boarded,
            label: '확정',
          ),
          onTap: () {},
        ),
        BaraedaListRow(
          leadingIcon: 'lock',
          title: '비밀번호 변경',
          trailing: const BaraedaIcon('chevron-right'),
          onTap: () {},
        ),
        const BaraedaListRow(
          title: '부천중동 센트럴파크 푸르지오 2단지 아파트 정문 앞 버스정류장 (구 중동초 건너편)',
          subtitle: '오늘 탑승 학생 없음 · 미등원 2명 · 보호자 연락 가능한 학생 없음',
        ),
      ],
    ),
    _h('불러오는 중 · 뼈대'),
    const BaraedaSkeletonList(count: 2),
    _h('승하차지 타임라인 · 지난 · 지금 · 이후 · 건너뜀 · 추가'),
    const BaraedaCard(
      padding: EdgeInsets.symmetric(vertical: BaraedaSpacing.space2),
      child: StopTimeline(
        stops: [
          Stop(
            name: '푸른아파트 앞',
            address: '학생 4명 · 도착 12:21',
            time: '12:21',
            state: StopState.done,
          ),
          Stop(
            name: '중앙공원 앞',
            address: '다음 승하차지 · 학생 3명',
            time: '12:31',
            state: StopState.current,
          ),
          Stop(name: '행복마을 입구', time: '12:38', state: StopState.next),
          Stop(name: '한빛빌라', state: StopState.skipped),
          Stop(name: '달빛어린이집', time: '12:44', state: StopState.added),
        ],
      ),
    ),
  ];

  List<Widget> _feedback(BuildContext context) => [
    _h('연결 끊김 · 오프라인 띠'),
    const BaraedaConnectionStrip(
      state: BaraedaConnectionState.offline,
      message: '연결이 끊겼어요 · 처리 대기 2건',
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    const BaraedaConnectionStrip(
      state: BaraedaConnectionState.reconnecting,
      message: '다시 연결하는 중…',
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    const BaraedaConnectionStrip(
      state: BaraedaConnectionState.restored,
      message: '다시 연결됐어요 · 2건 보냈어요',
    ),
    _h('알림 띠 4종'),
    const AlertBanner(tone: AlertTone.info, title: '확정 전 · 출발 30분 전에 확정돼요'),
    const SizedBox(height: BaraedaSpacing.space2),
    const AlertBanner(tone: AlertTone.moving, title: '버스가 10분 늦어요 · 교통 체증'),
    const SizedBox(height: BaraedaSpacing.space2),
    const AlertBanner(tone: AlertTone.boarded, title: '탑승 처리됐어요'),
    const SizedBox(height: BaraedaSpacing.space2),
    AlertBanner(
      tone: AlertTone.missed,
      title: '보내지 못했어요 · 다시 시도해 주세요',
      action: BaraedaButton(
        label: '다시 시도',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: () {},
      ),
    ),
    _h('빈 상태'),
    const EmptyState(title: '오늘 배정된 운행이 없어요', body: '배정되면 여기에 나타나요'),
    _h('하단 시트 · 대화상자 (눌러서 열기)'),
    BaraedaButton(
      label: '하단 시트',
      variant: BaraedaButtonVariant.secondary,
      block: true,
      onPressed: () => showBaraedaBottomSheet<void>(
        context: context,
        title: '도착 처리',
        showCloseButton: true,
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('되돌릴 수 없어요. 새솔초 정문에 도착했나요?'),
            const SizedBox(height: BaraedaSpacing.space3),
            BaraedaButton(
              label: '도착했어요',
              block: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '위험 확인 대화상자',
      variant: BaraedaButtonVariant.secondary,
      block: true,
      onPressed: () => showBaraedaConfirmDialog(
        context: context,
        title: '김민준 학생을 미승차 처리할까요?',
        body: '처리하면 학부모 · 보호자에게 바로 알림이 나가고 연락 대기 시간이 시작돼요.',
        confirmLabel: '미승차 처리',
        cancelLabel: '닫기',
        danger: true,
      ),
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaButton(
      label: '3단 선택 대화상자',
      variant: BaraedaButtonVariant.secondary,
      block: true,
      onPressed: () => showBaraedaActionDialog<String>(
        context: context,
        title: '로그아웃 전에 확인해 주세요',
        body: '아직 보내지 못한 처리 3건은 버려집니다.',
        actions: const [
          BaraedaDialogAction(label: '대기열 3건 먼저 보기', value: 'queue'),
          BaraedaDialogAction(
            label: '그래도 로그아웃',
            value: 'logout',
            variant: BaraedaButtonVariant.dangerOutline,
          ),
          BaraedaDialogAction(
            label: '닫기',
            value: 'close',
            variant: BaraedaButtonVariant.ghost,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _cards() => [
    _h('카드 · 숫자 칸 · 제출 영수증'),
    const Row(
      children: [
        Expanded(
          child: StatCard(label: '오늘 운행', value: '3', unit: '건'),
        ),
        SizedBox(width: BaraedaSpacing.space2),
        Expanded(
          child: StatCard(
            label: '미승차',
            value: '2',
            unit: '명',
            tone: StatCardTone.missed,
          ),
        ),
      ],
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    const BaraedaCard(
      highlight: true,
      child: Text('강조 카드(위쪽 3px 초록 선) — 지금 가장 중요한 칸 하나만'),
    ),
    const SizedBox(height: BaraedaSpacing.space3),
    const BaraedaReceiptCard(
      title: '승인 요청을 보냈어요',
      rows: [
        BaraedaReceiptRow('회차', '하원 · 14:40 출발'),
        BaraedaReceiptRow('변경', '승하차지 변경'),
        BaraedaReceiptRow('사유', '학원 일정 변경'),
      ],
    ),
  ];

  List<Widget> _mapParts() => [
    _h('지도 단추 · 비상 버튼 3형태'),
    Wrap(
      spacing: BaraedaSpacing.space3,
      runSpacing: BaraedaSpacing.space3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const BaraedaMapTag(label: '12:14:08 기준'),
        BaraedaMapButton(
          icon: 'crosshair',
          semanticLabel: '내 위치',
          onPressed: () {},
        ),
        BaraedaMapButton(
          icon: 'route',
          semanticLabel: '경로',
          label: '노선 보기',
          onPressed: () {},
        ),
        BaraedaSosButton(onPressed: () {}),
        BaraedaSosButton(form: BaraedaSosForm.floating, onPressed: () {}),
      ],
    ),
    const SizedBox(height: BaraedaSpacing.space2),
    BaraedaSosButton(form: BaraedaSosForm.wide, onPressed: () {}),
    const SizedBox(height: BaraedaSpacing.space6),
  ];
}
