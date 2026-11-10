.PHONY: build test lint coverage app run install dmg appstore icon clean

build:
	swift build

test:
	swift test

lint:
	swiftlint --strict --quiet

# Runs the tests and fails when PluckKit's line or region coverage is below 80%.
coverage:
	scripts/coverage.sh

app:
	scripts/build-app.sh

run: app
	open build/Pluck.app

# Builds the app and moves it to /Applications, replacing an earlier copy.
install:
	scripts/build-app.sh --install

dmg: app
	scripts/make-dmg.sh

# Builds the Mac App Store package, build/appstore/Pluck.pkg (see scripts/build-app.sh for the variables).
appstore:
	swift package resolve
	CHANNEL=appstore scripts/build-app.sh

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh

clean:
	rm -rf .build build coverage
