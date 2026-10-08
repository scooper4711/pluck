.PHONY: build test lint coverage app run install dmg icon clean

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
	open dist/Pluck.app

# Builds the app and moves it to /Applications, replacing an earlier copy.
install:
	scripts/build-app.sh --install

dmg: app
	scripts/make-dmg.sh

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh

clean:
	rm -rf .build dist coverage
