# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-11-21

### Added
- Close the PDF on the iPad
- Run the iPad app on the iPhone too
- Add the iPad app's window, toolbar and image grid
- Add tap selection and bookmarked recent documents

### Fixed
- Drop "unofficial" from the About tagline
- Send Scrollkeeper the download request on the iPad
- Show Paizo's notices in About Pluck

### Changed
- Copy through a Pasteboard protocol
- Update tabletop-kit to 1.11.4
- Time out CI jobs instead of waiting 6 hours
- Pin the GitHub actions to commit hashes
- Run the tests on the self-hosted Mac mini
- Require tabletop-kit 1.5.0
- Specify closing a PDF on the iPad
- Ask Scrollkeeper on the iPad to download the title
- Run the app and its UI tests on an iPhone simulator
- Specify the iPhone layout
- Require tabletop-kit 1.4.1
- Require tabletop-kit 1.4.0
- Drop the AI disclosure rule from CONTRIBUTING
- Describe the iPad app in the README
- Cover the iPad app with UI tests
- Build, install and draw an icon for the iPad app
- Add the iPad app's Xcode project
- Move the app into a PluckUI target
- Build PluckKit for the iPad as well
- Specify the iPad app
- Number every build by the commits on main
- Number every build by the commits on main
- Use tabletop-kit 1.3.0
- Specify Paizo's notices in About Pluck
- Use the shared Scrollkeeper bridge from tabletop-kit
- Specify the shared Scrollkeeper bridge

[2.1.0]: https://github.com/scooper4711/pluck/releases/tag/v2.1.0

## [2.0.0] - 2026-11-13

### Added
- Use tabletop-kit's shared empty window
- Build Pluck for the Mac App Store without its updater
- Sign Pluck into the toolkit's App Group
- Read Scrollkeeper's library from the App Group

### Fixed
- Make the updater check fail when the updater is present
- Build with no extra flags under the CI shell
- Capitalize the bundle ID like the other toolkit apps
- Keep the last letter of outlined or shadowed text

### Changed
- use the exact Community Use notice wording
- Say what deleting the app leaves on a Mac
- Say where the review notes live and drop a wrong comment
- Use tabletop-kit 0.17.0
- Use tabletop-kit 0.16.0
- Give the form field fixture a resource dictionary
- Specify reading Scrollkeeper's shared library
- Welcome signed commits without requiring them
- Add a contributing guide

[2.0.0]: https://github.com/scooper4711/pluck/releases/tag/v2.0.0

## [1.1.1] - 2026-10-20

### Added
- Preview selected images with Space
- Open titles from Scrollkeeper
- Run Pluck in the App Sandbox

### Fixed
- Bundle the universal binary from where SwiftPM built it

### Changed
- Specify Open from Scrollkeeper and Space preview
- Specify the App Sandbox
- Allow trial release builds run by hand
- Build into build/ like the other toolkit apps

[1.1.1]: https://github.com/scooper4711/pluck/releases/tag/v1.1.1

## [1.1.0] - 2026-10-15

### Added
- Show libwebp's notice in the About panel

### Fixed
- Read coverage from every test bundle

### Changed
- Say the toolkit is Mac apps, two also on the iPad
- Specify libwebp's notice in the About panel
- Rename the suite the Tableside Toolkit
- List every Society Toolkit app
- Give Pluck's stat blocks their own paragraph
- Remove the statement about the use of AI
- Open the README with the problem Pluck solves
- Call the combat tracker Turnkeeper
- Call the combat tracker Turnkeeper
- Add a screenshot with public-domain sample art
- Add the Society Toolkit section to the README

[1.1.0]: https://github.com/scooper4711/pluck/releases/tag/v1.1.0

## [1.0.0] - 2026-10-09

### Added
- Initial release

[1.0.0]: https://github.com/scooper4711/pluck/releases/tag/v1.0.0
