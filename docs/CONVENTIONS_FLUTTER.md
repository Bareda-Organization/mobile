# Flutter 코드 컨벤션

작성 2026-09-10. 적용 대상 — `apps/parent-app` · `apps/manager-app` · `packages/baraeda_ui`.
React 쪽 규칙은 `docs/frontend/CONVENTIONS_REACT.md` 이며 **두 문서는 서로를 대체하지 않음.**

기본은 [Effective Dart](https://dart.dev/effective-dart) 를 그대로 따르고,
이 문서는 **Effective Dart 가 정하지 않는 것**(구조 · 상태 관리 · 네이밍 세부 · 이 프로젝트 규칙)만 규정.

---

## 1. 채택 라이브러리 — 바꾸려면 이 절을 먼저 고침

| 용도 | 채택 | 이유 |
|---|---|---|
| 상태 관리 | **Riverpod** (`flutter_riverpod` · `riverpod_generator`) | 컴파일 시점에 의존이 드러나고 테스트에서 교체가 쉬움. `InheritedWidget` 직접 사용·전역 싱글턴 금지 |
| 라우팅 | **go_router** | 선언형 · 딥링크(푸시 알림에서 특정 회차로 진입)가 필수 |
| HTTP | **dio** | 인터셉터로 토큰 재발급(`§2.6`)·멱등 키(`§1.7`)를 한곳에서 처리 |
| 모델·직렬화 | **freezed** + `json_serializable` | 불변 모델 · 유니온(상태머신)·`copyWith` 자동 생성 |
| 로컬 저장 | **flutter_secure_storage**(토큰) · **drift**(오프라인 큐) | refresh 토큰은 평문 저장 금지. 오프라인 큐(M-06)는 트랜잭션이 필요 |
| 린트 | **very_good_analysis** | 기본 `flutter_lints` 보다 엄격. `analysis_options.yaml` 에 고정 |

---

## 2. 디렉터리 — feature-first · 계층 3단

```
lib/
├── main.dart
├── app/                    앱 진입 · 라우팅 · 테마 조립
│   ├── app.dart
│   ├── router.dart
│   └── di.dart
├── core/                   기능에 속하지 않는 것만
│   ├── network/            dio 설정 · 인터셉터 · 에러 매핑
│   ├── error/              Failure 타입
│   ├── storage/
│   └── constants/
└── features/
    └── <기능>/
        ├── data/           dto · datasource · repository 구현
        ├── domain/         entity · repository 인터페이스 · usecase
        └── presentation/   screen · widget · provider(상태)
```

**기능 하나가 폴더 하나.** 이름은 **`docs/frontend/IMPLEMENTATION_PLAN.md` §3.1·§3.2 의 화면**을 따름
(`auth` · `home` · `live_map` · `route` · `schedule` · `settings` /
`auth` · `home` · `drive_mode` · `roster` · `delay` · `route_map` · `run_end` · `emergency` · `offline_queue`).

⚠ **`docs/FEATURE_SPEC` 의 도메인 이름을 쓰지 않는다** (2026-09-10 정정).
화면 하나가 도메인 경계를 넘나드는 자리가 실재한다 — 매니저 앱의 명단 화면은
승차·하차·승인을 한 화면에서 다룬다. 도메인으로 쪼개면 **화면과 폴더가 1:1 로 안 붙어**
어느 폴더를 열어야 하는지 알 수 없게 된다. 웹(`CONVENTIONS_REACT.md`)은 반대로 도메인 이름을 쓰는데,
그쪽은 화면이 아니라 라우트 단위라 경계가 겹치지 않기 때문이다.

### 지켜야 할 의존 방향

```
presentation → domain ← data
```

- **`presentation` 이 `data` 를 직접 import 하지 않음.** 항상 `domain` 의 인터페이스를 거침
  — 이것이 없으면 화면이 DTO 모양에 묶여 API 가 바뀔 때 화면까지 고쳐야 함
- **기능끼리 서로 import 하지 않음.** 공유가 필요하면 `core/` 로 올리거나 `packages/baraeda_ui` 로 뺌
- `core/` 는 어느 기능도 import 하지 않음 (단방향)

---

## 3. 공용 위젯은 별도 패키지

**`packages/baraeda_ui` 하나에 두고 두 앱이 의존.** 앱 안에 각자 만들면 같은 위젯이 두 벌 생기고
디자인 시스템이 갱신될 때 한쪽만 고쳐짐.

```
packages/baraeda_ui/lib/
├── baraeda_ui.dart          공개 배럴 — 앱은 이것만 import
├── tokens/                  색 · 타입 · 여백 · 모양 · 모션
│   ├── colors.dart
│   ├── typography.dart
│   ├── spacing.dart
│   ├── shape.dart
│   └── motion.dart
├── theme/
│   ├── baraeda_theme.dart   ThemeData 라이트/다크
│   └── theme_extension.dart 토큰을 ThemeExtension 으로 노출
└── widgets/                 core · forms · feedback · navigation · transit
```

### 토큰은 하드코딩하지 않음

`frontend/design-system/tokens/*.css` 의 값을 **Dart 상수로 1:1 이식**하고, 위젯은 그 상수만 참조.

```dart
// ✓ 토큰 참조
Container(color: context.colors.statusBoarded)

// ✗ 값 직접 입력 — 디자인 시스템이 바뀌어도 안 따라옴
Container(color: const Color(0xFF1F5C4D))
```

**상태 색 매핑은 한 곳에서만 정함** — `boarded` 그린 · `moving` 앰버 · `missed` 레드 · `idle` 스톤.
세 제품이 같은 상태에 같은 색을 쓰는 것이 디자인 시스템의 1번 원칙이라, 화면에서 색을 직접 고르지 않음.

### 경계선·터치 크기·대화상자는 공용판으로 (`Ruling 403~405`)

- **조작 요소(입력칸·스위치·보조 버튼·선택 칩)의 경계선은 `borderControl`**(인접 면과 3:1 이상). 카드 외곽선·타임라인 점 같은 장식 구분선만 `borderDefault`
- **`BaraedaButton.sm` 은 보이는 크기 36 · 누르는 영역 48×48**. 이웃과 겹치지 않게 영역이 레이아웃 박스 안에 있다(세로 12 커짐). 더 작은 누르는 영역을 앱에서 새로 만들지 않음
- **확인 대화상자는 `showBaraedaConfirmDialog`, 바닥 시트는 `showBaraedaBottomSheet`.** Material `AlertDialog`·`showModalBottomSheet`·`IconButton` 을 앱에서 직접 쓰지 않음 — 공용판이 본문 스크롤·뒤로가기·낭독 배경 차단·Material 조상을 이미 처리. 앱이 쓰지 않는 공용 위젯은 패키지에 두지 않음(낡으면 결함이 잠복)

### 다크는 매니저 앱의 기본값

매니저 앱은 `ThemeMode.dark` 고정. 학부모 앱은 라이트 기본이며 `ThemeMode.system` 미사용
— 디자인 시스템의 다크는 **야간 하원 화면과 매니저 앱** 용도로만 정의돼 있음.

---

## 4. 네이밍

| 대상 | 규칙 | 예 |
|---|---|---|
| 파일 · 디렉터리 | `snake_case.dart` | `stop_roster_screen.dart` |
| 클래스 · enum · typedef | `UpperCamelCase` | `RunSummaryCard` |
| 변수 · 함수 · 파라미터 | `lowerCamelCase` | `boardedCount` |
| 상수 | `lowerCamelCase` (Dart 관례 — `SCREAMING_CAPS` 미사용) | `const maxDelayMinutes = 60;` |
| 비공개 | `_` 접두 | `_handleBoardTap` |
| 화면 위젯 | `<기능>Screen` | `StopRosterScreen` |
| 조각 위젯 | `<대상><역할>` | `StudentRow` · `DelayPicker` |
| Riverpod provider | `<대상>Provider` | `runRosterProvider` |
| 콜백 파라미터 | `on` 접두 | `onBoardTap` |
| 내부 핸들러 | `_handle` 접두 | `_handleBoardTap` |

**약어를 쓰지 않음** — `btn` · `cnt` · `usr` 금지. React 쪽 컨벤션과 같은 규칙.
**불리언은 `is` · `has` · `can` 접두** — `isBoarded` · `hasUnreadNotification`.

---

## 5. 위젯 작성

- **`StatelessWidget` 을 기본으로 두고**, 상태가 필요하면 Riverpod 의 `ConsumerWidget`.
  `StatefulWidget` 은 애니메이션 컨트롤러·포커스 노드처럼 **위젯 수명에 묶인 것**에만
- **`build` 안에서 함수로 위젯을 쪼개지 않고 별도 위젯 클래스로 뺌**
  — 함수는 리빌드 범위를 좁히지 못해 목록 화면에서 전체가 다시 그려짐
  ```dart
  // ✗ Widget _buildRow() { … }
  // ✓ class _RosterRow extends StatelessWidget { … }
  ```
- **`const` 생성자를 가능한 한 붙임.** 리빌드를 건너뛰는 유일한 수단
- 한 파일에 공개 위젯 하나. 그 파일 안의 비공개 하위 위젯은 `_` 접두로 같은 파일에 둠
- **위젯 하나가 200줄을 넘으면 쪼갬** (`docs/backend/CODE_CONVENTIONS.md §20` 과 같은 기준)
- 목록은 `ListView.builder`. `Column` + `map` 은 항목 수가 고정일 때만

## 6. 상태 · 비동기

- **화면 상태는 `AsyncValue` 로 표현** — 로딩 · 성공 · 실패 세 갈래를 화면이 전부 다루게 강제됨.
  `isLoading` 불리언을 직접 들고 다니지 않음
- **`setState` 로 서버 데이터를 들지 않음.** 서버에서 온 것은 전부 provider
- **에러는 `Failure` 로 변환해서 올림.** 화면이 `DioException` 을 직접 보지 않음
  — `API_SPEC §8 에러 코드 사전`의 코드를 `Failure` 로 매핑하는 곳은 `core/network` 한 군데
- `BuildContext` 를 `await` 너머로 쓰지 않음. 부득이하면 `if (!context.mounted) return;`

## 7. 카피 · 표기 — 디자인 시스템 규칙을 그대로 받음

`frontend/design-system/readme.md` 의 CONTENT FUNDAMENTALS 가 문면 규칙의 정본.

- **이모지 미사용.** 구분자는 중간점 `·` 하나만
- 시각은 24시간제 콜론(`8:37`), 호차는 `3-2호차`
- 아이는 이름 + 이/가(`하준이가`), 어른은 역할 + 이름(`기사 박정호`)
- 버튼 라벨은 동사로 끝냄 — `오늘 운행 보기` · `기사에게 연락`
- 시간·위치를 모호하게 적지 않음 — `곧 도착` ✗ / `약 5분 후 도착` ✓
- **하드코딩한 한글 문자열을 위젯 안에 흩지 않음** — 기능별 `l10n` 또는 상수 파일에 모음

## 8. 테스트

| 대상 | 방식 |
|---|---|
| `domain` usecase | 순수 단위 테스트 |
| `data` repository | `dio` 를 가짜 응답으로 바꿔 테스트 |
| 위젯 | `testWidgets` — **상태 색 매핑과 접근성 라벨**을 검사 대상에 넣음 |
| 화면 흐름 | `integration_test` — `USER_FLOWS` 의 경로 하나가 테스트 하나 |

**통과하는 것을 확인하지 않은 테스트는 산출물로 인정하지 않음** — 구현 전에 실패를 눈으로 봄
(`docs/IMPLEMENTATION_PLAN §4.6` 과 같은 규칙).

## 9. 금지

- `print` — `logger` 사용
- `dynamic` 남용 · `as` 로 강제 캐스팅
- `!`(null 단언) — `??` · `?.` · 조기 반환으로 대체
- 위젯 안에서 `DateTime.now()` 직접 호출 — 시각은 주입받음
  (이 서비스의 중심축이 시간이라 테스트에서 시각을 고정할 수 없으면 검증 불가)
- ⚠ **서버가 준 시각을 `toLocal()` 없이 벽시계로 읽기** — `hour`·`minute` 직접 읽기,
  `DateFormat(...).format(...)` 둘 다 해당. `DateTime.parse` 는 오프셋이 붙은 문자열
  (`…Z` · `…+09:00`)을 **언제나 UTC `DateTime`** 으로 돌려주므로, 그대로 찍으면
  KST 에서 **9시간 이른 시각**이 나온다. 2026-09-21 까지 앱 2종의 표시 12곳이 그 상태였고
  (19:40 출발 → "10:40 출발") 검사는 전부 초록이었다 — 시험 데이터가 로컬 `DateTime` 이라
  변환 여부가 드러나지 않았다. **기댓값을 `DateTime.utc(...).toLocal()` 로 만든 검사**를
  둔다(관계자 웹은 `toLocaleTimeString` 이라 이 함정이 부재)
- 하드코딩된 색·여백·폰트 크기
