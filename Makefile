.PHONY: build test lint coverage app run install dmg appstore icon ipad-install ipad-simulator ipad-uitests clean

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

# Builds the iPad app and installs it on a connected iPad. IPAD names the iPad.
ipad-install:
	scripts/install-ipad.sh

# Builds the iPad app and starts it in a simulator. IPAD_SIMULATOR names the simulator.
ipad-simulator:
	scripts/run-ipad-simulator.sh

# Runs the iPad UI tests, which screenshot both orientations.
ipad-uitests:
	scripts/run-ipad-uitests.sh

# Redraws Resources/AppIcon.icns and the iPad's icon from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh

clean:
	rm -rf .build build coverage ios/build
