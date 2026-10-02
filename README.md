# 바래다 (BARAEDA) — 모바일 앱

학원 통학버스 관리 플랫폼의 Flutter 앱 2종과 공용 패키지입니다. 앱은 스토어에 **각각 따로** 올라갑니다(번들 ID 는 각 앱의 `ios/`·`android/`).

| 경로 | 무엇 |
|---|---|
| `apps/manager-app` | 매니저 앱 — 로그인 역할로 **기사 · 동승자** 화면이 갈린다 |
| `apps/parent-app` | 학부모 앱 — 로그인 역할로 **학부모 · 학생** 화면이 갈린다 |
| `packages/baraeda_core` | 공용 — 네트워크(API 클라이언트) · 인증 · WebSocket · 푸시·알림 · 저장소 · 시각 |
| `packages/baraeda_ui` | 공용 — 테마 · 디자인 토큰 · 위젯 |

두 앱은 공용 패키지를 `path: ../../packages/...` 로 참조하므로 **한 저장소에 함께 둡니다.**

## 명령

```bash
scripts/verify.sh     # CI 와 같은 검사 — 4개 패키지 analyze + test(실서버 계약 시험 제외)
```

## 관련 저장소

같은 조직(`Bareda-Organization`)의 `backend`(Spring Boot) · `web`(관계자 웹 · Vercel) · `workspace`(모든 문서 `docs/` 와 Claude 설정). `workspace` 를 받은 폴더(`baraeda/`) 안에 나머지 셋을 clone 합니다.
