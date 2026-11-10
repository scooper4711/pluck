#!/usr/bin/env bash
# Builds build/Pluck.app from the Swift package (release configuration).
#
# Usage: scripts/build-app.sh [--install]   (--install moves it to /Applications)
#
# VERSION    version written to the bundle (default 0.0.0)
# UNIVERSAL  set to 1 to build for both Apple silicon and Intel
# TEAM_ID    the team that owns the App Group (default: read from the Developer ID certificate)
# SIGNING_IDENTITY  passed to scripts/sign-app.sh; "-" signs ad hoc, without the App Group
# BUILD_NUMBER  CFBundleVersion, which must increase with every App Store upload (default: VERSION)
# CHANNEL    "appstore" builds the Mac App Store package, build/appstore/Pluck.pkg, from the same sources, compiled
#            with -DAPP_STORE so the updater is left out; needs TEAM_ID and the variables of tabletop-kit's
#            scripts/package-appstore.sh (PACKAGER names another copy; TRIAL=1 checks it without them)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.0.0}"
APP="build/Pluck.app"
EXECUTABLE="Pluck"

SWIFT_FLAGS=()
[[ "${CHANNEL:-}" == "appstore" ]] && SWIFT_FLAGS=(-Xswiftc -DAPP_STORE)

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --product "$EXECUTABLE" --arch arm64 --arch x86_64
    # Asked rather than assumed: newer SwiftPM moved universal builds out of .build/apple, and a copy left
    # there by an older toolchain would otherwise be bundled instead.
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE"
else
    swift build -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --product "$EXECUTABLE"
    BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The About panel shows this file: the notices of the libraries built into the app.
cp Resources/Credits.html "$APP/Contents/Resources/Credits.html"
# Moves the settings an unsandboxed version kept into the sandbox on the first sandboxed launch.
cp Resources/container-migration.plist "$APP/Contents/Resources/container-migration.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
# The entitlements turn on the App Sandbox. A build signed with the team's Developer ID also joins the Tableside
# Toolkit's App Group, where Scrollkeeper shares its library: the team's ID takes the place of TEAM_ID. The team ID
# is read from the signing certificate, or from TEAM_ID in the environment, and never committed. An ad hoc
# signature can't join the group, so its build leaves the group out and asks Scrollkeeper for the list instead.
ENTITLEMENTS="build/Pluck.entitlements"
if [[ "${SIGNING_IDENTITY:-}" != "-" ]]; then
    TEAM_ID="${TEAM_ID:-$(security find-identity -v -p codesigning \
        | sed -n 's/.*"Developer ID Application: .*(\([A-Z0-9]*\))"$/\1/p' | head -n 1)}"
fi
if [[ -n "${TEAM_ID:-}" ]]; then
    sed "s/TEAM_ID/$TEAM_ID/" Resources/Pluck.entitlements > "$ENTITLEMENTS"
else
    cp Resources/Pluck.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$ENTITLEMENTS"
fi
if [[ "${CHANNEL:-}" == "appstore" ]]; then
    # Only the updater saves into Downloads, and the App Store build has none (review asks what each is for).
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.files.downloads.read-write" "$ENTITLEMENTS"
fi
scripts/sign-app.sh "$APP" "$ENTITLEMENTS"
echo "Built $APP ($VERSION)"

if [[ "${CHANNEL:-}" == "appstore" ]]; then
    # The App Store build must not update itself (guideline 2.4.5(vii)).
    if strings "$APP/Contents/MacOS/$EXECUTABLE" | grep -q -E "AppUpdater|api\.github\.com"; then
        echo "The App Store build still contains the updater." >&2
        exit 1
    fi
    # Found beside the package after "swift package resolve", so the script follows the dependency pin.
    "${PACKAGER:-.build/checkouts/tabletop-kit/scripts/package-appstore.sh}" "$APP" "$ENTITLEMENTS" \
        io.github.scooper4711.Pluck
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Pluck.app
    ditto "$APP" /Applications/Pluck.app
    # Leave only the installed copy registered, so Finder and Spotlight launch that one.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$APP" 2>/dev/null || true  # Fails when it was never registered, which is fine.
    rm -rf "$APP"
    echo "Installed to /Applications/Pluck.app"
fi
