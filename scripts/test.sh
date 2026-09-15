#!/usr/bin/env bash
# Full verification loop for the Point Guard iPhone app: clean build, full
# unit test suite (including live-API integration tests) against a real
# booted simulator, talking to the real locally-running point-guard service.
# No mocks.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${POINT_GUARD_IOS_SIM:-iPhone 16 Pro}"
SCHEME="PointGuard"

export PATH="/opt/homebrew/bin:$PATH"

echo "==> Checking point-guard is reachable (127.0.0.1:3868)..."
if ! curl -sf -m 3 http://127.0.0.1:3868/health >/dev/null; then
  echo "!! point-guard not reachable on :3868 — live API tests will skip, not fail."
fi

echo "==> Regenerating Xcode project from project.yml..."
xcodegen generate

echo "==> Clearing stale DerivedData for this project (avoids stale test-bundle bugs)..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/${SCHEME}-"*

echo "==> Running full test suite on simulator: ${SIM_NAME}..."
set +e
xcodebuild -project "${SCHEME}.xcodeproj" -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,name=${SIM_NAME}" \
  test 2>&1 | tee /tmp/point-guard-iphone-test.log \
  | grep -E "Test Case|Test Suite '(All tests|${SCHEME}Tests\.xctest)'|error:|\*\* TEST"
STATUS=${PIPESTATUS[0]}
set -e

echo ""
if [ "$STATUS" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Tests failed. Full log: /tmp/point-guard-iphone-test.log"
fi
exit "$STATUS"
