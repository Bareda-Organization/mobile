import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 계정 **상태**(`pending`·`active`·`rejected`) 를 담는다.
///
/// `role_policy.dart` 의 `RoleCapabilities` 와 절대 한 파일에 섞지 않는다 —
/// 역할은 "이 계정이 무엇을 할 수 있는가"(정적, `UserRole` 만으로 결정)이고
/// 상태는 "지금 이 앱을 아예 쓸 수 있는가"(동적, 서버가 로그인·`/me`·게이트
/// 이벤트로 실시간으로 알려주는 선행조건)다 — `parent_app` 의 같은 파일과
/// 판단이 같다(§1.1, 보고서 § 아키텍처 결정 2). `RoleCapabilities.of` 는 이
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

/// 임시 비밀번호 강제 변경 표식(API_SPEC §1.4 · §2.5 · §2.10, Ruling 540) —
/// 로그인·`/me` 응답이 켜고, 역할이 비는 모든 경로(로그아웃·세션 만료·변경 성공
/// 뒤 로그아웃)가 [RouterRefreshNotifier] 에서 함께 끈다. 켜져 있는 동안 라우터는
/// 비밀번호 변경 화면 밖으로 보내지 않는다 — 서버가 그 밖의 API 를
/// `403 PASSWORD_CHANGE_REQUIRED` 로 막기 때문이다.
final StateProvider<bool> mustChangePasswordProvider = StateProvider<bool>(
  (ref) => false,
);

/// 세션이 만료돼(재발급 거절) 로그인 화면으로 돌아왔을 때 그 화면이 보여 줄 안내 — 처음 열었거나 직접 로그아웃했으면
/// `null` 이다. 로그인에 성공하면 로그인 화면이 비운다(R46).
final StateProvider<String?> sessionExpiredNoticeProvider =
    StateProvider<String?>((ref) => null);

/// 재발급이 거절돼 로그인이 풀렸다 — REST·WS 두 경로가 같은 처리를 한다. 안내를 **먼저** 남기고 역할을 비운다:
/// 역할이 비면 위치 송신 여부(`transmittingRunIdProvider`)도 같이 사라져 더는 알 수 없다. 운행 중이던 기사에게는
/// 위치 전송이 멈췄다는 것을 더한다 — 그 기사 화면은 로그인 화면으로 바뀌므로 경고도 거기서 한다(R46).
void endSessionAsExpired(Ref ref) {
  final wasTransmitting = ref.read(transmittingRunIdProvider) != null;
  ref.read(sessionExpiredNoticeProvider.notifier).state = wasTransmitting
      ? '로그인이 만료돼 위치 전송이 멈췄습니다. 다시 로그인하면 운행 중인 회차의 위치를 이어서 보냅니다'
      : '로그인이 만료됐습니다. 다시 로그인해 주세요';
  applyRoleAndStatus(
    ref.read(unsupportedRoleProvider.notifier),
    ref.read(currentUserRoleProvider.notifier),
    ref.read(currentAccountStatusProvider.notifier),
    role: null,
    status: null,
  );
}

/// 통신이 끊긴 채 앱을 켜서 **마지막으로 확인한 역할로 들어온 상태**(R52 H2) — `/me` 로 다시 확인하기 전까지 `true`.
/// 다시 확인되면 끄고, 로그아웃 · 세션 만료로 역할이 비어도 끈다.
final StateProvider<bool> unverifiedSessionProvider = StateProvider<bool>(
  (ref) => false,
);

/// 이 기기가 기억한 세션 흔적 — 마지막 역할과 오늘 회차 요약 — 을 지운다. 인증이 거절됐거나 계정이 게이트에 걸렸거나
/// 로그아웃한 뒤에는 통신 두절로 앱을 켜도 그 계정으로 들어갈 수 없다(R52 H2).
void _forgetDeviceSession(Ref ref) {
  unawaited(ref.read(lastSessionStoreProvider).clear());
  unawaited(ref.read(runSummaryStoreProvider).clear());
}

/// 앱 시작 시 저장된 refresh 토큰으로 자동 로그인을 시도한다(UF-X-03 분기
/// "앱 재실행"). refresh 토큰이 없으면 즉시 로그아웃 상태로 끝난다 —
/// `/me` 를 부르지 않는다(빈 토큰으로 호출해 401 을 만들 이유가 없다).
///
/// `/me` 응답이 만료된 access 토큰을 만나면 `ApiClient` 의 `_AuthInterceptor`
/// 가 저장된 refresh 로 자동 재발급 후 재시도한다 — 이 provider 는 그 재발급
/// 로직을 다시 구현하지 않는다.
///
/// `/me` 가 서버의 거절이 아닌 실패(연결 실패 · 5xx · 게이트웨이 HTML 오류 등)이고 마지막으로 확인한 역할이 기기에 있으면 그 역할로 들어간다(R52 H2) —
/// 통신 두절 구간에도 저장 명단 · 대기열 · 비상 신고 · 학원 전화가 열려야 한다. 역할이 없으면 지금처럼 오류로
/// 남겨 [다시 시도] 를 보인다. 서버의 거절(401 · 403)만 로그인 화면으로 남기고 저장한 역할을 지운다.
// 자동 재시도를 끈다 — Riverpod 3 은 실패한 provider 를 늘어나는 간격으로 조용히 다시 불러 그동안 스피너만
// 보이는데, 여기서는 곧바로 [다시 시도] 안내를 보이는 것이 낫다(F06-10).
final authBootstrapProvider = FutureProvider<void>(retry: (_, _) => null, (
  ref,
) async {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final refreshToken = await tokenStorage.readRefreshToken();
  if (refreshToken == null) return;

  final authRepository = ref.watch(authRepositoryProvider);
  try {
    await _applyMe(ref, await authRepository.me());
  } on Failure catch (failure) {
    if (!isServerRejection(failure)) {
      if (await _enterWithLastSession(ref)) return;
      rethrow;
    }
    // 서버의 거절(401 · 403) — 로그인 화면으로 남기고, 이 기기가 기억한 역할은 더 쓰지 않는다.
    _forgetDeviceSession(ref);
  } on Object {
    // 재발급까지 실패하면 인터셉터가 이미 토큰을 지웠다(§ api_client.dart
    // onError) — 여기서는 로그인 화면으로 남기는 것으로 충분하다.
  }
});

/// `/me` 응답을 앱 상태에 반영한다 — 앱 시작과 연결 회복 뒤 재확인이 같은 처리를 한다.
Future<void> _applyMe(Ref ref, MeResponse me) async {
  applyRoleAndStatus(
    ref.read(unsupportedRoleProvider.notifier),
    ref.read(currentUserRoleProvider.notifier),
    ref.read(currentAccountStatusProvider.notifier),
    role: me.role,
    status: me.status,
  );
  ref.read(unverifiedSessionProvider.notifier).state = false;
  ref.read(mustChangePasswordProvider.notifier).state = me.mustChangePassword;
  ref.read(academyContactProvider.notifier).state = me.academy?.contact;
  // 계정이 잠기면 서버에서 번호를 못 받는다 — 성공한 로그인의 번호를 기기에 남겨 둔다(`Ruling 825`).
  unawaited(ref.read(academyContactStoreProvider).save(me.academy?.contact));
  _rememberRole(
    ref.read(lastSessionStoreProvider),
    me.role,
    me.status,
    mustChangePassword: me.mustChangePassword,
  );
  if (me.status == AccountStatus.active && me.role == AccountRole.driver) {
    await _resumeMovingRun(ref);
  }
}

/// 활성 계정의 역할만 기기에 남긴다 — 대기 · 거절 · 지원하지 않는 계정과 임시 비밀번호 상태(변경 화면을 거쳐야 한다)는
/// 오프라인으로 들어갈 자격이 없다.
void _rememberRole(
  LastSessionStore store,
  AccountRole? role,
  AccountStatus? status, {
  required bool mustChangePassword,
}) {
  final supported =
      role != null && UserRole.fromWireValueOrNull(role.wireValue) != null;
  if (role != null &&
      status == AccountStatus.active &&
      supported &&
      !mustChangePassword) {
    unawaited(store.saveRole(role));
  } else {
    unawaited(store.clear());
  }
}

/// 연결이 닿지 않을 때 기기에 남긴 마지막 역할로 들어간다. 남긴 것이 없으면 `false`.
Future<bool> _enterWithLastSession(Ref ref) async {
  final role = await ref.read(lastSessionStoreProvider).readRole();
  if (role == null) return false;
  applyRoleAndStatus(
    ref.read(unsupportedRoleProvider.notifier),
    ref.read(currentUserRoleProvider.notifier),
    ref.read(currentAccountStatusProvider.notifier),
    role: role,
    status: AccountStatus.active,
  );
  ref.read(unverifiedSessionProvider.notifier).state = true;
  ref.read(academyContactProvider.notifier).state = await ref
      .read(academyContactStoreProvider)
      .read();
  return true;
}

/// 마지막 역할로 들어온 세션을 `/me` 로 다시 확인한다(R52 H2) — 연결이 돌아오는 주기 · 앱 복귀 · 서버 도달
/// 신호마다 부른다. 아직 닿지 않으면 그대로 두고 다음 기회를 기다린다. 인증 거절은 인터셉터가 세션 만료로 처리한다.
final Provider<Future<void> Function()> sessionReverifierProvider =
    Provider<Future<void> Function()>((ref) {
      var running = false;
      return () async {
        if (running || !ref.read(unverifiedSessionProvider)) return;
        running = true;
        try {
          await _applyMe(ref, await ref.read(authRepositoryProvider).me());
          ref.invalidate(meProvider);
        } on Failure catch (failure) {
          // 서버가 이 계정을 거절했다는 증거(401 · 403)가 있을 때만 끝낸다 —
          // 연결 두절 · 5xx · 게이트웨이 HTML 오류 ·
          // 그 밖의 실패는 마지막 역할 그대로 다음 기회를 기다린다(끝내면 대기열 · 비상 신고 대기분까지 버려진다).
          // 401 은 인터셉터가 세션 만료로 끝내므로 그 밖만 여기서 끝낸다.
          if (isServerRejection(failure)) {
            _forgetDeviceSession(ref);
            final expiredByInterceptor =
                failure is ApiFailure && failure.statusCode == 401;
            if (!expiredByInterceptor) endSessionAsExpired(ref);
          }
        } on Object {
          // 그 밖의 예외는 다음 기회에.
        } finally {
          running = false;
        }
      };
    });

/// 운행 중에 앱을 완전히 껐다 켜면 메모리 값인 선택 회차가 비어 위치 송신이 멎는다 — 오늘 회차(§4.1)에서
/// 운행 중이고 내가 기사인 회차를 찾아 채우면 앱 전역 송신기가 그대로 돈다. 화면은 옮기지 않는다
/// (기사가 보던 곳을 가로채지 않는다). 목록을 못 받으면 조용히 넘어간다 — 홈에서 직접 고르면 된다.
Future<void> _resumeMovingRun(Ref ref) async {
  try {
    final runs = await ref.read(managerRunRepositoryProvider).fetchRuns();
    final run = pickResumableRun(runs);
    final selected = ref.read(selectedRunIdProvider.notifier);
    if (run != null && selected.state == null) selected.state = run.runId;
  } on Object {
    // 송신 재개는 부가 동작이라 실패해도 로그인 복구를 막지 않는다.
  }
}

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

/// 로그인 성공 응답을 앱 상태에 반영한다 — 로그인 화면과 가입 직후 자동 로그인이 같은 처리를 하게 하는 한 곳이다.
/// 역할·상태 · 만료 안내 비우기 · 비밀번호 강제 변경 표식 · 학원 연락처(메모리 + 기기 저장)를 함께 채운다.
/// 계정이 잠기면 서버에서 번호를 못 받으니 성공한 로그인의 번호를 기기에 남겨 둔다(`Ruling 825`).
void applyLoginResponse(WidgetRef ref, LoginResponse response) {
  applyRoleAndStatus(
    ref.read(unsupportedRoleProvider.notifier),
    ref.read(currentUserRoleProvider.notifier),
    ref.read(currentAccountStatusProvider.notifier),
    role: response.role,
    status: response.status,
  );
  ref.read(sessionExpiredNoticeProvider.notifier).state = null;
  ref.read(mustChangePasswordProvider.notifier).state =
      response.mustChangePassword;
  ref.read(academyContactProvider.notifier).state = response.academy?.contact;
  unawaited(
    ref.read(academyContactStoreProvider).save(response.academy?.contact),
  );
  ref.read(unverifiedSessionProvider.notifier).state = false;
  _rememberRole(
    ref.read(lastSessionStoreProvider),
    response.role,
    response.status,
    mustChangePassword: response.mustChangePassword,
  );
}

/// 로그인·`/me` 성공 응답을 역할·상태 provider 에 반영하는 유일한 통로 —
/// 화면마다 이 매핑을 다시 적지 않는다. 로그인 화면도 이 함수를 그대로 쓴다.
///
/// `Ref` 대신 세 `StateController` 를 직접 받는다 — `ref.read(x.notifier)`
/// 가 돌려주는 `StateController<T>` 는 호출부가 `Ref`(provider 안)든
/// `WidgetRef`(화면)든 같은 구체 타입이라, Riverpod 3 에서 더는 공통
/// 상위 타입이 없는 두 `ref` 타입을 매개변수로 통일하지 않고도 이 함수
/// 하나를 양쪽에서 그대로 쓸 수 있다(`parent_app` 과 같은 이유).
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
  new(this._ref) {
    _roleSub = _ref.listen<UserRole?>(currentUserRoleProvider, (
      previous,
      next,
    ) {
      // 로그아웃·세션 만료(어느 경로든)로 역할이 비면 이 계정 소유의 상태를 함께 버린다(F06-02).
      if (previous != null && next == null) _clearAccountScopedState();
      notifyListeners();
    });
    _statusSub = _ref.listen<AccountStatus?>(
      currentAccountStatusProvider,
      (_, _) => notifyListeners(),
    );
    _unsupportedSub = _ref.listen<bool>(
      unsupportedRoleProvider,
      (_, _) => notifyListeners(),
    );
    _mustChangeSub = _ref.listen<bool>(
      mustChangePasswordProvider,
      (_, _) => notifyListeners(),
    );
    _gateSubscription = _ref.read(apiClientProvider).gateEvents.listen((
      reason,
    ) {
      _ref.read(currentAccountStatusProvider.notifier).state = switch (reason) {
        AccountGateReason.pending => AccountStatus.pending,
        AccountGateReason.rejected => AccountStatus.rejected,
      };
      // 대기 · 거절 계정은 통신 두절로 앱을 켜도 기억한 역할로 들어갈 수 없다.
      _forgetDeviceSession(_ref);
    });
    // 재발급이 401 로 거절돼(REST) 로그인이 풀렸다 — WS `sessionExpired` 와 같은 처리(K-02①).
    // 토큰은 재발급기가 이미 지웠으므로 서버에 알릴 것이 없다.
    _sessionExpiredSubscription = _ref
        .read(apiClientProvider)
        .sessionExpired
        .listen((_) {
          // 앱을 켜 세션을 되살리다 거절된 경우(M-2) — 역할이 원래 비어 있어 위 "역할이 비는 순간" 정리가 돌지 않는다.
          // 지난 계정이 기기에 남긴 명단·대기열이 그대로 남지 않게 같은 정리를 직접 태운다.
          final restoreFailed = _ref.read(currentUserRoleProvider) == null;
          endSessionAsExpired(_ref);
          if (restoreFailed) _clearAccountScopedState();
        });
  }

  /// 다음 계정이 이전 계정의 회차 목록·선택값을 보거나, 이전 계정의 대기 요청을 자기 토큰으로 재생하지
  /// 못하게 한다. 큐에는 사용자 열이 없어 비우는 수밖에 없다 — 로그아웃하면 미전송 처리는 버려진다.
  void _clearAccountScopedState() {
    _ref
      ..invalidate(todayRunsProvider)
      ..invalidate(emergencyListProvider)
      ..invalidate(rosterProvider)
      ..invalidate(driveModeRosterProvider)
      ..invalidate(routeProvider);
    _ref.read(selectedRunIdProvider.notifier).state = null;
    _ref.read(mustChangePasswordProvider.notifier).state = false;
    _ref.read(unverifiedSessionProvider.notifier).state = false;
    _ref.read(academyContactProvider.notifier).state = null;
    // 로그아웃 · 세션 만료 뒤에는 이 기기가 기억한 역할로 다시 들어갈 수 없다(R52 H2).
    _forgetDeviceSession(_ref);
    _ref.read(transmissionEndedRunIdProvider.notifier).state = null;
    _ref.read(lastArriveResultProvider.notifier).state = null;
    unawaited(_discardOfflineQueue());
  }

  /// 기기에 남긴 이 계정의 것을 지운다. **명단(학생 특이사항 포함)을 먼저** 지운다 — 대기열 쪽이 예외를 던져도
  /// 개인정보는 남지 않는다(M-2). 명단 삭제가 실패해도 대기열 정리는 그대로 이어진다(`finally`).
  Future<void> _discardOfflineQueue() async {
    try {
      // 기기에 저장한 명단도 이 계정의 것이다(M-M3) — 다음 계정이 보면 안 된다.
      await _ref.read(rosterCacheProvider).clear();
    } finally {
      await _discardPendingRequests();
    }
  }

  /// 대기 요청을 버린다. 세션이 만료돼서 버리는 것이면(로그인 화면에 만료 안내가 있다) 버려지는 건수를 그 안내에
  /// 더한다 — 직접 로그아웃은 확인 창이 이미 알려 준다(`Ruling 388`). 비상 신고가 섞여 있으면 따로 밝힌다:
  /// 서버에 전달되지 못했으니 학원에 직접 알려야 한다(`Ruling 616`).
  Future<void> _discardPendingRequests() async {
    final queue = _ref.read(offlineQueueRepositoryProvider);
    final discarded = await queue.fetchPending();
    await queue.clear();
    final notice = _ref.read(sessionExpiredNoticeProvider);
    if (notice == null || discarded.isEmpty) return;
    final emergencies = discarded
        .where((request) => request.isEmergency)
        .length;
    final emergencyNote = emergencies == 0
        ? ''
        : ' — 비상 신고 $emergencies건이 서버에 전달되지 못했으니 '
              '학원에 직접 알려 주세요';
    _ref.read(sessionExpiredNoticeProvider.notifier).state =
        '$notice 보내지 못한 처리 ${discarded.length}건은 '
        '버려졌습니다$emergencyNote';
  }

  final Ref _ref;
  late final ProviderSubscription<UserRole?> _roleSub;
  late final ProviderSubscription<AccountStatus?> _statusSub;
  late final ProviderSubscription<bool> _unsupportedSub;
  late final ProviderSubscription<bool> _mustChangeSub;
  late final StreamSubscription<AccountGateReason> _gateSubscription;
  late final StreamSubscription<void> _sessionExpiredSubscription;

  @override
  void dispose() {
    _roleSub.close();
    _statusSub.close();
    _unsupportedSub.close();
    _mustChangeSub.close();
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
