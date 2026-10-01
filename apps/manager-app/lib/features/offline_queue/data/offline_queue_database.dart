import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'offline_queue_database.g.dart';

/// 오프라인 상태에서 쌓인 승하차 처리 요청 큐 (M-06, API_SPEC §1.7 멱등성).
///
/// 각 행은 재접속 시 그대로 재전송할 요청 하나 — 본문에 실을 `client_key`
/// 를 요청 생성 시점에 미리 발급해 둬서, 큐 재생과 즉시 전송이 서버 입장에서
/// 같은 멱등 키를 쓰게 한다.
class PendingRequests extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 호출할 엔드포인트 경로.
  TextColumn get endpoint => text()();

  /// HTTP 메서드 — §1.7 대상 두 종류가 `PATCH`(승하차 처리)·`POST`(비상
  /// 발신)로 서로 달라 재생 시 필요하다(스키마 v2 에서 추가, 기존
  /// 컬럼과 달리 처음부터 있었어야 했던 값). 기본값은 `ALTER TABLE ADD
  /// COLUMN` 이 기존 행에 값을 채우는 데 쓰인다 — 새 행은 호출부가 항상
  /// 명시한다.
  TextColumn get method => text().withDefault(const Constant('PATCH'))();

  /// 요청 본문 (JSON 직렬화된 문자열).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 서버가 5xx 로 응답해 재생에 실패한 횟수(스키마 v4) — 통신 두절은 세지
  /// 않는다(행이 아니라 망의 문제). 상한(`OfflineQueueRepositoryImpl.maxAttempts`)에
  /// 닿은 행이 **영구 실패 행**이다 — 재생에서 빠지고 큐 화면에는 남는다. 기본값은
  /// `ALTER TABLE ADD COLUMN` 이 기존 행에 0 을 채우는 데 쓰인다.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [PendingRequests])
class OfflineQueueDatabase extends _$OfflineQueueDatabase {
  OfflineQueueDatabase() : super(_openConnection());

  /// 시험 전용 — 파일 대신 주입받은 실행기(보통 `NativeDatabase.memory()`)를
  /// 쓴다. `path_provider` 플랫폼 채널이 없는 단위 시험 환경에서 필요하다.
  @visibleForTesting
  OfflineQueueDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 에는 `method` 가 없었다 — 컬럼 기본값(`PATCH`, 그 시점 유일한
        // 대상인 §4.6 승하차 처리)이 기존 행을 그대로 채운다.
        await m.addColumn(pendingRequests, pendingRequests.method);
      }
      if (from < 3) {
        // v2 의 `client_key` 컬럼은 쓰기만 되고 어디서도 읽히지 않았다 —
        // 실제 멱등성은 `payload` 안에 직렬화된 `client_key` 값으로
        // 지켜진다(FE-R2 목표 11). 남겨 둔 채로는 "멱등이 여기서
        // 지켜진다" 는 잘못된 신호를 주므로 컬럼째 제거한다.
        await m.dropColumn(pendingRequests, 'client_key');
      }
      if (from < 4) {
        // 행별 시도 횟수 — 큐 머리의 한 행이 5xx 를 되풀이해도 뒤를 영구히 막지 않게 한다(R46-FIXRT S-9).
        await m.addColumn(pendingRequests, pendingRequests.attempts);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'offline_queue.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
