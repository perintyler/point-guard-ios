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

# Say out loud which suite you are getting. The live tests XCTSkip when the
# service is down OR when BARRY_SECRET is unset, and a skip reads identically to
# a pass in the summary line — so the one thing this probe must never do is stay
# quiet about it.
echo "==> Checking point-guard is reachable (127.0.0.1:3868)..."
if curl -sf -m 3 http://127.0.0.1:3868/health >/dev/null; then
  echo "    reachable."
else
  echo "!!  NOT reachable — every live test will SKIP, not fail."
fi

# xcodebuild does not pass this shell's environment to the test process; the
# scheme forwards it (see project.yml). Unset, the authenticated live tests skip.
if [ -n "${BARRY_SECRET:-}" ]; then
  echo "==> BARRY_SECRET is set — authenticated live tests will RUN."
else
  echo "!!  BARRY_SECRET is NOT set — authenticated live tests will SKIP, not fail."
  echo "    export BARRY_SECRET=\"\$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:BARRY_SECRET' \\"
  echo "      ~/Library/LaunchAgents/com.barry.api.plist)\""
fi
export BARRY_SECRET="${BARRY_SECRET:-}"

echo "==> Regenerating Xcode project from project.yml..."
xcodegen generate

echo "==> Running full test suite on simulator: ${SIM_NAME}..."
set +e
# -derivedDataPath pins the output where `barry ios build` also writes. Without
# it xcodebuild uses Xcode's shared DerivedData, and `simctl install` from the
# other path silently installs a STALE app — which cost three rounds of
# screenshots in a sibling bag chasing a feature that was never in the binary
# under test.
xcodebuild -project "${SCHEME}.xcodeproj" -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,name=${SIM_NAME}" \
  -derivedDataPath .build-barry-ios \
  test 2>&1 | tee /tmp/point-guard-iphone-test.log \
  | grep -E "Test Case|Test Suite '(All tests|${SCHEME}Tests\.xctest)'|error:|\*\* TEST"
STATUS=${PIPESTATUS[0]}
set -e

echo ""
SKIPS=$(grep -c 'was skipped' /tmp/point-guard-iphone-test.log || true)
if [ "$STATUS" -eq 0 ]; then
  echo "All tests passed. Skipped: ${SKIPS}"
  if [ "$SKIPS" -gt 0 ]; then
    echo "  A skip is not a pass. grep 'was skipped' /tmp/point-guard-iphone-test.log"
  fi
else
  echo "Tests failed. Full log: /tmp/point-guard-iphone-test.log"
fi
exit "$STATUS"
