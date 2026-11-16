#!/bin/sh
# Prints the app's version, taken from git so the iPad and Mac builds agree.
#
#   scripts/version.sh marketing   the newest release tag without its "v" (1.2.0), or 0.0.0 before the first
#   scripts/version.sh build       the build number: the commit count, which grows with every commit on main
#   scripts/version.sh xcconfig    both, as Xcode build settings (written to ios/Version.xcconfig)
set -eu

cd "$(dirname "$0")/.."

marketing() {
    tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
    echo "${tag#v}"
}

build() {
    # A shallow clone counts only the commits it fetched, which would make a build number go backwards.
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        echo "Reading the build number failed: the clone is shallow; fetch the full history." >&2
        exit 1
    fi
    git rev-list --count HEAD
}

case "${1:-}" in
    marketing) marketing ;;
    build) build ;;
    xcconfig)
        echo "// Written by scripts/version.sh; not committed."
        echo "MARKETING_VERSION = $(marketing)"
        echo "CURRENT_PROJECT_VERSION = $(build)"
        ;;
    *) echo "Usage: scripts/version.sh marketing|build|xcconfig" >&2; exit 2 ;;
esac
