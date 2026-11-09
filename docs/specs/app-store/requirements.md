# Mac App Store build: requirements

Pluck 2.0 is listed on the Mac App Store beside its notarized disk image (tabletop-kit#26). The packaging steps are
tabletop-kit's `scripts/package-appstore.sh` (its `appstore-build` spec).

## R1 The build
- R1.1 `CHANNEL=appstore scripts/build-app.sh` (or `make appstore`) builds `build/appstore/Pluck.pkg` from the same
  sources as the disk image, compiled with `-DAPP_STORE`.
- R1.2 That build has no updater: not the Check for Updates command, the launch check, its setting, nor the code.
  The build script fails if the binary still names `AppUpdater` or GitHub's API; the disk image build keeps the
  updater (guideline 2.4.5(vii)).
- R1.3 Its entitlements leave out the Downloads folder, which only the updater used. The network client entitlement
  stays because the WKWebView preview renders nothing in the sandbox without it.
- R1.4 The build number (`BUILD_NUMBER`) is apart from the version and increases with every upload; the bundle
  declares `ITSAppUsesNonExemptEncryption` as false, a copyright line and the real version.

## R2 Privacy
- R2.1 A privacy manifest ships in the bundle: no tracking, no data collected, and user defaults (CA92.1).
- R2.2 `PRIVACY.md` is the privacy policy, linked from the Help menu.

## R3 Review
- R3.1 `APP-STORE-REVIEW.md` holds the review notes, with a use named for every entitlement.
