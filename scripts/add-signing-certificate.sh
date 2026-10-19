#!/bin/sh
# On GitHub, puts the Developer ID certificate into a temporary keychain that codesign searches, so that
# scripts/sign-app.sh signs with it. Without the certificate a trial build is signed ad hoc and a release fails.
#
# DEVELOPER_ID_CERTIFICATE           the certificate with its private key, as a base64-encoded .p12 file
# DEVELOPER_ID_CERTIFICATE_PASSWORD  the .p12 file's password
# RELEASING                          "true" when building a release
set -eu

if [ -z "${DEVELOPER_ID_CERTIFICATE:-}" ]; then
    if [ "${RELEASING:-false}" = "true" ]; then
        echo "::error::Signing failed: the DEVELOPER_ID_CERTIFICATE secret is missing."
        exit 1
    fi
    echo "::warning::The DEVELOPER_ID_CERTIFICATE secret is missing, so this trial build is signed ad hoc."
    exit 0
fi

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERTIFICATE="$RUNNER_TEMP/developer-id.p12"

printf '%s' "$DEVELOPER_ID_CERTIFICATE" | base64 --decode > "$CERTIFICATE"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
rm "$CERTIFICATE"
# Lets codesign use the private key without a prompt no one is there to answer.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046  # The existing keychains are one quoted path per line, without spaces.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
