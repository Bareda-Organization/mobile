import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';

/// 계정 **상태**(`pending`·`active`·`rejected`) 를 담는다.
///
/// `role_policy.dart` 의 `RoleCapabilities` 와 절대 한 파일에 섞지 않는다 —
/// 역할은 "이 계정이 무엇을 할 수 있는가"(정적, `UserRole` 만으로 결정)이고
/// 상태는 "지금 이 앱을 아예 쓸 수 있는가"(동적, 서버가 로그인·`/me`·게이트
/// 이벤트로 실시간으로 알려주는 선행조건)다 — 서로 다른 것을 가른다는 것이
/// `IMPLEMENTATION_PLAN.md §5.0` 계정 상태 게이트 표의 전제이고, 여기서도
/// 그대로 지킨다(보고서 § 아키텍처 결정 2). `RoleCapabilities.of` 는 이
/// provider 를 참조하지 않는다.
final StateProvider<AccountStatus?> currentAccountStatusProvider =
    StateProvider<AccountStatus?>((ref) => null);

/// `GET /me` 가 이 앱이 모르는 역할을 돌려줬을 때만 `true`(§2.10). 로그인
/// 자체는 서버 기준으로 성공했으므로 크래시가 아니라 안내로 갈라야 한다
/// (user_role.dart 의 `fromWireValueOrNull` 이 죽지 않게 한 것과 같은 이유).
/// 라우터에 별도 화면을 두지 않고 로그인 화면이 이 값을 직접 읽어 인라인
/// 안내로 처리한다 — 목표 표의 화면 4종에 없는 화면을 새로 만들지 않기
/// 위해서다(COMMON.md §6 "목표 표에 없는 기능을 더하지 마라").
final StateProvider<bool> unsupportedRoleProvider = StateProvider<bool>(
  (ref) => false,
);

/// 앱 시작 시 저장된 refresh 토큰으로 자동 로그인을 시도한다(UF-X-03 분기
/// "앱 재실행"). refresh 토큰이 없으면 즉시 로그아웃 상태로 끝난다 —
/// `/me` 를 부르지 않는다(빈 토큰으로 호출해 401 을 만들 이유가 없다).
///
/// `/me` 응답이 만료된 access 토큰을 만나면 `ApiClient` 의 `_AuthInterceptor`
/// 가 저장된 refresh 로 자동 재발급 후 재시도한다 — 이 provider 는 그 재발급
/// 로직을 다시 구현하지 않는다.
// 자동 재시도를 끈다 — Riverpod 3 은 실패한 provider 를 늘어나는 간격으로 조용히 다시 불러 그동안 스피너만
// 보이는데, 여기서는 곧바로 [다시 시도] 안내를 보이는 것이 낫다(F05-10).
final authBootstrapProvider = FutureProvider<void>(retry: (_, _) => null, (
  ref,
) async {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final refreshToken = await tokenStorage.readRefreshToken();
  if (refreshToken == null) return;

  final authRepository = ref.watch(authRepositoryProvider);
  try {
    final me = await authRepository.me();
    applyRoleAndStatus(
      ref.read(unsupportedRoleProvider.notifier),
      ref.read(currentUserRoleProvider.notifier),
      ref.read(currentAccountStatusProvider.notifier),
      role: me.role,
      status: me.status,
    );
  } on Failure catch (failure) {
    // F05-10 — 연결이 끊겼거나 서버가 잠깐 죽은 것은 로그인이 풀린 것이 아니다. 토큰은 그대로 두고
    // 앱이 [다시 시도] 를 보이게 오류로 남긴다. 그 밖(401 등 인증 거절)은 로그인 화면으로 남긴다.
    if (failure is NetworkFailure ||
        (failure is ApiFailure && failure.statusCode >= 500)) {
      rethrow;
    }
  } on Object {
    // 재발급까지 실패하면 인터셉터가 이미 토큰을 지웠다(§ api_client.dart
    // onError) — 여기서는 로그인 화면으로 남기는 것으로 충분하다.
  }
});

/// 로그아웃(2026-09-23 사용자 지시) — 서버에 알리고, **실패해도** 이 기기의 역할·상태를 비운다. 역할이
/// 비면 라우터가 로그인 화면으로 보낸다(판정은 라우터 한 곳). 토큰은 `AuthApi.logout` 이 성패와 무관하게
/// 지운다 — 여기서 역할까지 비우지 않으면 토큰 없이 로그인된 화면에 갇혀 요청마다 401 이 난다.
///
/// provider 를 await 전에 모두 읽어 둔다 — 로그아웃하면서 화면이 사라지면 그 뒤의 `ref` 는 쓸 수 없다.
Future<void> signOut(WidgetRef ref) async {
  final repository = ref.read(authRepositoryProvider);
  final unsupported = ref.read(unsupportedRoleProvider.notifier);
  final role = ref.read(currentUserRoleProvider.notifier);
  final status = ref.read(currentAccountStatusProvider.notifier);
  try {
    await repository.logout();
  } finally {
    applyRoleAndStatus(unsupported, role, status, role: null, status: null);
  }
}

/// 로그아웃 확인 대화 1회 → 확정 시 [signOut] 재사용. 실패해도 [signOut]
/// 자체가 역할·상태를 비운다(그 함수 문서 참고) — 여기서 에러를 따로
/// 처리하지 않는다.
///
/// **F2(2026-09-26) — `settings_screen.dart`·`pending_approval_screen.dart`
/// 가 이 함수 하나를 공유한다.** 화면마다 확인 대화를 새로 만들면 문구·
/// 동작이 갈릴 위험이 있어(실제로 두 화면이 이 함수가 생기기 전까지
/// 갈려 있었다), `features/` 어느 쪽도 소유하지 않는 `core/auth` 에 둔다
/// (`CONVENTIONS_FLUTTER.md §2` "기능끼리 서로 import 하지 않음").
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('로그아웃'),
      content: const Text('로그아웃 하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('로그아웃하기'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    try {
      await signOut(ref);
    } on Failure {
      // 이미 로그아웃 처리됐다 — 위 주석 참고.
    }
  }
}

/// 로그인·`/me` 성공 응답을 역할·상태 provider 에 반영하는 유일한 통로 —
/// 화면마다 이 매핑을 다시 적지 않는다. 로그인 화면도 이 함수를 그대로 쓴다.
///
/// `Ref` 대신 세 `StateController` 를 직접 받는다 — `ref.read(x.notifier)`
/// 가 돌려주는 `StateController<T>` 는 호출부가 `Ref`(provider 안)든
/// `WidgetRef`(화면)든 같은 구체 타입이라, Riverpod 3 에서 더는 공통
/// 상위 타입이 없는 두 `ref` 타입을 매개변수로 통일하지 않고도 이 함수
/// 하나를 양쪽에서 그대로 쓸 수 있다.
void applyRoleAndStatus(
  StateController<bool> unsupportedRoleController,
  StateController<UserRole?> userRoleController,
  StateController<AccountStatus?> accountStatusController, {
  required AccountRole? role,
  required AccountStatus? status,
}) {
  final userRole = role == null
      ? null
      : UserRole.fromWireValueOrNull(role.wireValue);
  unsupportedRoleController.state = role != null && userRole == null;
  userRoleController.state = userRole;
  accountStatusController.state = status;
}

/// `GoRouter.refreshListenable` 로 물릴 브리지 — Riverpod provider 변화와
/// `ApiClient.gateEvents`(403 `AUTH_PENDING`/`AUTH_REJECTED`) 를 `ChangeNotifier`
/// 신호 하나로 합친다. go_router 는 `redirect` 를 내비게이션 시점에만
/// 재평가하므로, 세션 중간에 계정이 게이트된 경우(목표 표 7항)는 이 알림이
/// 없으면 화면이 다음 사용자 조작 전까지 대기 화면으로 못 옮겨간다.
class RouterRefreshNotifier extends ChangeNotifier {
  /// `ref` 로 provider 변화를 구독하고 게이트 스트림을 함께 문다.
  RouterRefreshNotifier(this._ref) {
    _roleSub = _ref.listen<UserRole?>(
      currentUserRoleProvider,
      (_, _) => notifyListeners(),
    );
    _statusSub = _ref.listen<AccountStatus?>(
      currentAccountStatusProvider,
      (_, _) => notifyListeners(),
    );
    _unsupportedSub = _ref.listen<bool>(
      unsupportedRoleProvider,
      (_, _) => notifyListeners(),
    );
    _gateSubscription = _ref.read(apiClientProvider).gateEvents.listen((
      reason,
    ) {
      _ref.read(currentAccountStatusProvider.notifier).state = switch (reason) {
        AccountGateReason.pending => AccountStatus.pending,
        AccountGateReason.rejected => AccountStatus.rejected,
      };
    });
    // SE — WS 재발급까지 실패하면(공유 패키지 C1 `sessionExpired`) REST
    // 로그인 만료와 같은 경로로 보낸다. `signOut()` 의 실패 갈래가 쓰는
    // 것과 같은 [applyRoleAndStatus] 호출이다 — 이미 토큰은
    // `TokenRefresher.refresh()` 가 지운 뒤라 서버에 다시 알릴 것이 없다.
    _sessionExpiredSubscription = _ref
        .read(webSocketClientProvider)
        .sessionExpired
        .listen((_) {
          applyRoleAndStatus(
            _ref.read(unsupportedRoleProvider.notifier),
            _ref.read(currentUserRoleProvider.notifier),
            _ref.read(currentAccountStatusProvider.notifier),
            role: null,
            status: null,
          );
        });
  }

  final Ref _ref;
  late final ProviderSubscription<UserRole?> _roleSub;
  late final ProviderSubscription<AccountStatus?> _statusSub;
  late final ProviderSubscription<bool> _unsupportedSub;
  late final StreamSubscription<AccountGateReason> _gateSubscription;
  late final StreamSubscription<void> _sessionExpiredSubscription;

  @override
  void dispose() {
    _roleSub.close();
    _statusSub.close();
    _unsupportedSub.close();
    unawaited(_gateSubscription.cancel());
    unawaited(_sessionExpiredSubscription.cancel());
    super.dispose();
  }
}

/// [RouterRefreshNotifier] 싱글턴 — `routerProvider` 가 이것을
/// `refreshListenable` 로 넘긴다.
final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});
