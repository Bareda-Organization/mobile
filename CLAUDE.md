@README.md

## Work rules

- **All documents are in the workspace's (`baraeda/` = `Bareda-Organization/workspace`) `../docs/`** — entry `../docs/README.md` · specs `../docs/planning/` · app implementation plan `../docs/frontend/IMPLEMENTATION_PLAN.md`. Don't put documents in this repo
- **Code rules: `../docs/frontend/mobile/CONVENTIONS_FLUTTER.md`**
- The design tokens' source is the web repo's `design-system/` (read-only) — the `baraeda_ui` color values are hand-copied from it. `frontend/design-system/…` in comments is the pre-split path
- Split from the monorepo (`mskim98/School-Bus`) on 2026-10-02 — the old paths `frontend/apps/…` · `frontend/packages/…` are this repo's `apps/…` · `packages/…`
- Each of the 2 apps takes the backend URL via `--dart-define=API_BASE_URL=…` (including the `/api/v1` suffix)
