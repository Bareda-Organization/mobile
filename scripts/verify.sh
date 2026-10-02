#!/bin/bash
# 병합·push 전 한 명령 검증 — CI(.github/workflows/ci.yml)와 같은 검사를 4개 패키지에 돈다.
#
# 실서버 계약 시험(@Tags(['real_backend']) — 백엔드가 떠 있어야 한다)은 뺀다. 각 패키지 dart_test.yaml 에
# 태그 선언이 있어야 걸러진다.
# 연결 끊김 문구 대조 시험은 web 저장소의 파일을 읽는다 — 형제 clone(../web) 또는 WEB_REPO_DIR.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_DIRS=(packages/baraeda_core packages/baraeda_ui apps/manager-app apps/parent-app)

for dir in "${FLUTTER_DIRS[@]}"; do
  echo "== $dir"
  (
    cd "$dir"
    flutter pub get
    if grep -q build_runner pubspec.yaml; then
      dart run build_runner build --delete-conflicting-outputs
    fi
    flutter analyze
    flutter test --exclude-tags real_backend
  )
done
echo "verify 통과: mobile"
