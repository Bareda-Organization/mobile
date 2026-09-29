import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

import '../../support/fake_token_storage.dart';
import '../../support/manager_run_fixture.dart';

class _MeAuthRepository implements AuthRepository {
  _MeAuthRepository(this.role);

  final AccountRole role;

  @override
  Future<MeResponse> me() async => MeResponse(
    accountId: 'a1',
    loginId: 'driver011',
    name: '기사',
    phone: '010-0000-0000',
    role: role,
    status: AccountStatus.active,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RunsRepository implements ManagerRunRepository {
  _RunsRepository(this.runs);

  final List<ManagerRun> runs;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async => runs;
}

/// 앱을 완전히 껐다 켜면 메모리 값인 선택 회차가 사라져 운행 중이어도 위치 송신이 멎는다(R34 M1) —
/// 로그인 복구 직후 오늘 운행 중(`moving`)이고 내가 기사로 배치된 회차를 다시 골라 송신기를 잇는다.
void main() {
  Future<ProviderContainer> recover({
    AccountRole role = AccountRole.driver,
    required List<ManagerRun> runs,
  }) async {
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(
          FakeTokenStorage(seedRefreshToken: 'refresh'),
        ),
        authRepositoryProvider.overrideWithValue(_MeAuthRepository(role)),
        managerRunRepositoryProvider.overrideWithValue(_RunsRepository(runs)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authBootstrapProvider.future);
    // 앱 루트가 하는 것처럼 송신 대상 판정을 구독해 둔다.
    container.listen(transmittingRunIdProvider, (_, _) {});
    await container.read(todayRunsProvider.future);
    return container;
  }

  test('운행 중이고 내가 기사인 회차가 있으면 복구 직후 그 회차가 선택되어 송신 대상이 된다', () async {
    final container = await recover(
      runs: [
        managerRunFixture(
          runId: 'run-idle',
          roleInRun: UserRole.driver,
        ),
        managerRunFixture(
          runId: 'run-moving',
          status: RunStatus.moving,
          roleInRun: UserRole.driver,
        ),
      ],
    );

    expect(container.read(selectedRunIdProvider), 'run-moving');
    expect(container.read(transmittingRunIdProvider), 'run-moving');
  });

  test('운행 중인 회차가 여럿이면 출발 시각이 가장 늦은 회차를 고른다', () async {
    final container = await recover(
      runs: [
        managerRunFixture(
          runId: 'run-early',
          status: RunStatus.moving,
          departTime: DateTime(2026, 9, 30, 7),
          roleInRun: UserRole.driver,
        ),
        managerRunFixture(
          runId: 'run-late',
          status: RunStatus.moving,
          departTime: DateTime(2026, 9, 30, 17),
          roleInRun: UserRole.driver,
        ),
      ],
    );

    expect(container.read(selectedRunIdProvider), 'run-late');
  });

  test('운행 중이 아니거나 내가 동승자로 배치된 회차만 있으면 아무것도 고르지 않는다', () async {
    final container = await recover(
      runs: [
        managerRunFixture(
          runId: 'run-confirmed',
          roleInRun: UserRole.driver,
        ),
        managerRunFixture(
          runId: 'run-escort',
          status: RunStatus.moving,
          roleInRun: UserRole.escort,
        ),
      ],
    );

    expect(container.read(selectedRunIdProvider), isNull);
    expect(container.read(transmittingRunIdProvider), isNull);
  });

  test('동승자 계정이면 회차 목록을 보지 않고 아무것도 고르지 않는다', () async {
    final container = await recover(
      role: AccountRole.escort,
      runs: [
        managerRunFixture(
          runId: 'run-moving',
          status: RunStatus.moving,
          roleInRun: UserRole.driver,
        ),
      ],
    );

    expect(container.read(selectedRunIdProvider), isNull);
  });
}
