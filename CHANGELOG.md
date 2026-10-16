# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-16

### Changed

- New app icon, in the blue glass style shared by Common Stats, Common Keys, and Common Bar.

### Fixed

- The hourly chart in the dropdown labels its axis by the hours it shows (12 AM, 6 AM, 12 PM, 6 PM) instead of ending in "Now", which pointed at the wrong bar for most of the day.

## [0.1.0] - 2026-10-16

### Added

- Menu bar app that fixes a word typed on the wrong keyboard layout when the word ends, by reading the same keys on each enabled layout and keeping the reading that is a real word.
- Support for every ordinary layout macOS ships, dead keys included, read from the layouts' own tables. Korean 2-Set and Vietnamese Telex and VNI are composed in both directions. Japanese and Chinese input methods receive the keys as a destination for the convert shortcut.
- Evidence from the system spell checker, spelling rules no word breaks, the language recognizer for readings in the same script, and what the user taught.
- Undo with ⌘Z right after a fix; the word is then left alone from then on.
- Convert the last word on request with a double-tap of right ⌥ (or ⇧ or ⌃), and switch to the next layout with ⌥⇧Space. Both are configurable.
- Per-app layouts: switching apps restores the layout last used there, or the one usually written in. Apps can be pinned to a layout or paused; terminals and code editors start paused.
- A dropdown with the day's words, fixes by hour and undos, the share of each language, the top apps, and the key most often mixed up.
- Settings for launch at login, shortcuts, per-app layouts, and forgetting what was learned.
- The `WorldKey` library and the `worldkey` command: list input sources, convert text between layouts, detect the intended layout, and evaluate accuracy, with `--json` output.
- Universal (Apple silicon and Intel) release builds of the app and the `worldkey` command.

[Unreleased]: https://github.com/oddurs/common-keys/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/oddurs/common-keys/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/oddurs/common-keys/releases/tag/v0.1.0
