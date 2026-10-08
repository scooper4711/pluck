#!/bin/sh
# Runs the tests with coverage, writes coverage/sonar-coverage.xml for SonarCloud, and fails when line or
# region coverage of PluckKit is below the threshold. Swift's coverage tooling does not report branch
# coverage; region coverage is the closest measure.
set -eu

THRESHOLD="${COVERAGE_THRESHOLD:-80}"
cd "$(dirname "$0")/.."

swift test --enable-code-coverage --quiet

BIN_PATH="$(swift build --show-bin-path)"
PROFILE="$BIN_PATH/codecov/default.profdata"
# The test bundle is named after the package, as is the coverage file SwiftPM reports.
PACKAGE="$(basename "$(swift test --show-codecov-path)" .json)"
BINARY="$BIN_PATH/${PACKAGE}PackageTests.xctest/Contents/MacOS/${PACKAGE}PackageTests"

xcrun llvm-cov export -summary-only -instr-profile "$PROFILE" "$BINARY" > "$BIN_PATH/coverage.json"

# SonarCloud's generic coverage format, with paths relative to the repository so that the
# report can be read on another machine than the one that ran the tests.
mkdir -p coverage
xcrun llvm-cov export -format=lcov -instr-profile "$PROFILE" "$BINARY" | awk -v root="$PWD/" '
    BEGIN { print "<coverage version=\"1\">" }
    /^SF:/ {
        file = substr($0, 4)
        if (index(file, root) == 1) file = substr(file, length(root) + 1)
        keep = (file ~ /^Sources\//)
        if (keep) printf "  <file path=\"%s\">\n", file
    }
    /^DA:/ && keep {
        split(substr($0, 4), parts, ",")
        printf "    <lineToCover lineNumber=\"%s\" covered=\"%s\"/>\n", parts[1], (parts[2] > 0 ? "true" : "false")
    }
    /^end_of_record/ { if (keep) print "  </file>"; keep = 0 }
    END { print "</coverage>" }
' > coverage/sonar-coverage.xml

/usr/bin/python3 - "$BIN_PATH/coverage.json" "$THRESHOLD" "${1:-}" <<'PYTHON'
import json
import sys

report_path, threshold, mode = sys.argv[1], float(sys.argv[2]), sys.argv[3]
files = [
    entry for entry in json.load(open(report_path))["data"][0]["files"]
    if "/Sources/PluckKit/" in entry["filename"]
]


def percent(kind):
    covered = sum(entry["summary"][kind]["covered"] for entry in files)
    count = sum(entry["summary"][kind]["count"] for entry in files)
    return 100.0 * covered / count if count else 100.0


if mode == "--files":
    for entry in sorted(files, key=lambda entry: entry["summary"]["regions"]["percent"]):
        name = entry["filename"].split("/Sources/PluckKit/")[1]
        summary = entry["summary"]
        print(f"{summary['lines']['percent']:6.1f}% lines {summary['regions']['percent']:6.1f}% regions  {name}")

lines, regions = percent("lines"), percent("regions")
print(f"PluckKit coverage: {lines:.1f}% lines, {regions:.1f}% regions (threshold {threshold:.0f}%)")
sys.exit(0 if lines >= threshold and regions >= threshold else 1)
PYTHON
