@README.md

## 작업 규칙

- **사양은 backend 저장소 `docs/` 가 단일 기준이다** — 진입점 `../backend/docs/README.md`. 앱 구현 계획은 `../backend/docs/frontend/IMPLEMENTATION_PLAN.md`. 이 저장소에 사양을 복사하지 않는다
- **코드 규칙은 `docs/CONVENTIONS_FLUTTER.md`**
- 디자인 토큰의 원본은 web 저장소의 `design-system/`(읽기 전용) — `baraeda_ui` 의 색상값은 그 원본을 손으로 옮긴 것이다. 주석의 `frontend/design-system/…` 은 분리 전 경로다
- 2026-10-02 통합 저장소(`mskim98/School-Bus`)에서 분리했다 — 그 전 경로 `frontend/apps/…` · `frontend/packages/…` 가 이 저장소의 `apps/…` · `packages/…` 다
- 앱 2종은 각각 `--dart-define=API_BASE_URL=…` 로 백엔드 주소를 받는다(`/api/v1` 접미사까지 포함)
