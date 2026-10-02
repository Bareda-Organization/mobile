import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';

/// 복구 시 자동 동기화 (M-06, API_SPEC §1.7) — 앱이 떠 있는 동안 주기마다
/// 오프라인 큐를 재생한다. [child] 를 그대로 그리는 통과 위젯이라 화면
/// 구성에는 영향이 없다.
///
/// 큐 화면(`offline_queue_screen.dart`)의 재시도 버튼만 두면, 두절 구간에서
/// 처리한 승하차가 통신 복구 뒤에도 **아무도 그 화면을 열지 않는 한 영영
/// 서버에 닿지 않는다.** 쓰기 요청이 뒤따를 때는
/// `OfflineQueueRepository.sendOrQueue` 가 먼저 큐를 흘려보내므로, 이 타이머는
/// **더 이상 처리할 것이 없을 때**(운행 종료 후 등)를 맡는다.
class OfflineQueueAutoSync extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  /// 재생 주기. 위치 전송(2초)과 달리 실시간성이 필요 없고, 두절 중에는
  /// 주기마다 타임아웃을 한 번씩 기다리게 되므로 느슨하게 잡았다.
  static const interval = Duration(seconds: 30);

  final Widget child;

  @override
  ConsumerState<OfflineQueueAutoSync> createState() =>
      _OfflineQueueAutoSyncState();
}

class _OfflineQueueAutoSyncState extends ConsumerState<OfflineQueueAutoSync> {
  Timer? _timer;

  /// 앞 주기가 아직 타임아웃을 기다리는 중이면 겹쳐 돌지 않게 하는 빗장 —
  /// 두절 상태에서는 한 주기가 주기 길이보다 오래 걸릴 수 있다.
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      OfflineQueueAutoSync.interval,
      (_) => unawaited(_flush()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _flush() async {
    // 로그인 전에는 토큰이 없다 — 보내면 401 이고, 재생 규칙상 4xx 는
    // "재시도해도 같은 결과" 라 큐에서 **영구 제거**된다. 쌓아 둔 승하차
    // 처리가 통째로 사라지므로 아예 건드리지 않는다.
    if (ref.read(currentUserRoleProvider) == null) return;
    if (_flushing) return;
    _flushing = true;
    try {
      final repository = ref.read(offlineQueueRepositoryProvider);
      if ((await repository.fetchPending()).isEmpty) return;
      await repository.replayPending();
      if (mounted) ref.invalidate(pendingRequestsProvider);
    } on Object {
      // 화면 액션이 아니라 배경 동작이라 오류를 띄우지 않는다 — 다음 주기가
      // 다시 시도한다(drive_mode 의 위치 전송 틱과 같은 판단).
    } finally {
      _flushing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
