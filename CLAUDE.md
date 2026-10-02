@README.md

## 작업 규칙

- **모든 문서는 작업 공간(`baraeda/` = `Bareda-Organization/workspace`)의 `../docs/` 에 있다** — 진입점 `../docs/README.md` · 사양 `../docs/planning/` · 앱 구현 계획 `../docs/frontend/IMPLEMENTATION_PLAN.md`. 이 저장소에 문서를 두지 않는다
- **코드 규칙은 `../docs/frontend/mobile/CONVENTIONS_FLUTTER.md`**
- 디자인 토큰의 원본은 web 저장소의 `design-system/`(읽기 전용) — `baraeda_ui` 의 색상값은 그 원본을 손으로 옮긴 것이다. 주석의 `frontend/design-system/…` 은 분리 전 경로다
- 2026-10-02 통합 저장소(`mskim98/School-Bus`)에서 분리했다 — 그 전 경로 `frontend/apps/…` · `frontend/packages/…` 가 이 저장소의 `apps/…` · `packages/…` 다
- 앱 2종은 각각 `--dart-define=API_BASE_URL=…` 로 백엔드 주소를 받는다(`/api/v1` 접미사까지 포함)
