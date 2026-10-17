# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Learns from your corrections on this Mac: words you type and keep stop being changed, and how readily it fixes follows how you correct it, within fixed limits.
- Thai, Georgian and Armenian words typed on the wrong keyboard are fixed. Typed on U.S., they are now fixed every time in testing, against 58%, 0% and 51% before.
- Each language's spelling is learned on this Mac from its own dictionary, so names and words no dictionary has can still be told apart from wrong-keyboard noise.

### Fixed

- A slow or stuck system spelling service can no longer stall typing: Common Keys checks each language's spelling data at launch, gives the check half a second, and falls back to plain spell checking past that.
- Words in a language whose spelling completions macOS has dropped, as it sometimes does for Russian, French or German, are fixed again: the plain spell check decides instead of reading every word as misspelled.
- Correctly typed Georgian and Armenian words that also spell an English word on the U.S. layout, like ორ and ուներ, are no longer changed to English.

### Changed

- Internal: the weights that decide when to fix a word are fitted on generated examples instead of set by hand, behind a held-out check that they fix no correct word (no change in results on the checked pairs).
- Internal: the engine's mid-word check is fitted and gated like the end-of-word one, so no start of a correctly typed word is changed (no change in the app, which fixes words as they end).


## [0.2.0] - 2026-10-16

### Added

- A Common Tools section at the end of Settings: Common Stats, Common Keys, and Common Bar, each opened if installed or linked if not, and the app's version.

### Changed

- Settings follows the layout shared by the Common Tools apps: Shortcuts, Exceptions, Learning, General, then Common Tools.
- "Launch at login" is now "Open at login", under General.
- Settings also opens with ⌘, while its window is open, and when Common Keys is opened again while it runs.
- Internal: the scorer weighs named features instead of inline constants, so the weights can be fitted (no change in results).

### Fixed

- Settings › Exceptions lists only apps installed on this Mac, instead of showing bare bundle identifiers for editors and terminals that are paused by default but not present.

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

[Unreleased]: https://github.com/oddurs/common-keys/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/oddurs/common-keys/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/oddurs/common-keys/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/oddurs/common-keys/releases/tag/v0.1.0
