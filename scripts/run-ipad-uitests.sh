#!/bin/sh
# Runs the iPad UI tests in a simulator. They screenshot the window in landscape and portrait; the screenshots are
# kept in the test results (ios/build/Logs/Test).
#
# IPAD_SIMULATOR    name of the simulator to use (default: a SIMULATOR_FAMILY device on the newest iOS)
# SIMULATOR_FAMILY  iPad (the default) or iPhone
# ONLY              tests to run, space-separated, such as "LayoutUITests/testInspectorInLandscape"
set -eu

cd "$(dirname "$0")/.."

DEVICE="$(scripts/ipad-simulator-id.sh)"
[ -n "$DEVICE" ] || { echo "Running the UI tests failed: no ${SIMULATOR_FAMILY:-iPad} simulator is installed." >&2; exit 1; }
echo "Running the UI tests on simulator $DEVICE..."

set -- -project ios/Pluck.xcodeproj -scheme Pluck-iPad \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO
for test in ${ONLY:-}; do set -- "$@" -only-testing:"PluckUITests/$test"; done

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
STATUS=0
xcodebuild test "$@" > "$LOG" 2>&1 || STATUS=$?
grep -E " error: |Test Case .*(passed|failed)|\*\* TEST" "$LOG" || tail -n 20 "$LOG"
exit "$STATUS"
