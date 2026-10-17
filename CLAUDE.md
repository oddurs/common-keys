# Working in this repository

<!-- standard:begin about -->
Common Keys is a macOS menu bar app that fixes words typed on the wrong keyboard layout. It runs on **WorldKey**, an engine library that also ships as the `worldkey` CLI. Swift, AppKit plus SwiftUI, no package dependencies.
<!-- standard:end about -->

## The seam

Do all automation through `scripts/task`. CI and the git hooks call nothing else.

```sh
scripts/task fmt          # format in place
scripts/task fmt:check    # swift format lint --strict
scripts/task lint         # fmt:check, then a debug build with warnings as errors
scripts/task test [name]  # the Swift Testing suites; a name filters them
scripts/task build        # universal "build/Common Keys.app", signed (see scripts/dev-cert)
scripts/task package      # dist/CommonKeys.zip and checksums, as a release publishes them
scripts/task run          # build, quit the running copy, open the new one
scripts/task check        # lint + test + build: what CI runs
```

## Workflow

- Never commit to `main`. It only moves forward when a pull request is merged; the `pre-push` hook and branch protection both enforce this.
- One unit of work gets one worktree, one branch, and one pull request: `scripts/agent start <type>/<slug>`, then work in the printed path and finish with `scripts/agent ship "<type>(scope): subject" "<why>" --body-file <pr.md>`, where the body states the problem, the approach, and where a reviewer should be sceptical. It commits, checks, opens the pull request with auto-merge, keeps it rebased while CI runs, and cleans up after the merge. If it stops on a failed check or a conflict, fix the cause and run it again.
- Branch types: `feat fix chore docs perf refactor test`. The branch's first commit names the pull request and the squash commit on `main`.
- Never use `--no-verify`.
- User-facing changes go under `## [Unreleased]` in `CHANGELOG.md` in the same pull request. The site shows each release's section as "What's new".
- Release with `scripts/release <version>`. Never tag by hand.
- This repository follows the Common Tools app standard (`standard/` in oddurs/common-tools). Change shared files there and apply them to every app; only the regions between `standard:begin` and `standard:end` belong to this app.

## Commits

Conventional Commits: `type(scope): subject`. Write the subject in the imperative, at most 72 characters, with no trailing period. The body says why. Never add assistant or tool attribution: no co-author trailers, no "generated with" footers. The `commit-msg` hook rejects them.

## Code

<!-- standard:begin code -->
- `Sources/WorldKey` is the engine, in layers: keys, keyboards (`KeyLayout`, `Composer`, `InputSources`), evidence (`Scorer`, `Orthography`, `Lexicon`, `Memory`), decisions (`Detector`). A layer never reaches up to the one above it. It holds no UI state.
- `Sources/LangSmart` is the app shell (the target keeps the pre-rename name): event tap and injection (`Engine`), status item and dropdown, Settings, hot keys. `Sources/WorldKeyCLI` is a thin wrapper over the library.
- A key press is a key code plus modifiers, never a character. Read layouts with the system translator; don't hard-code character tables.
- Leaving a correct word alone matters more than fixing a wrong one. Any change to scoring or decisions comes with `worldkey eval` numbers before and after, and "correct words changed" must not rise.
- Text typed in a converting input method (Japanese, Chinese) is the user's pick and is never read back or fixed.
- Nothing leaves the Mac; the app makes no network requests. Typing is never logged: only daily counts and what the user taught (words meant in another layout, words to leave alone, mixed-up keys, per-app layouts) are saved, under `~/Library/Application Support/LangSmart/`.
- A bug fix comes with the test that would have caught it. Tests read the layouts and dictionaries installed on the machine; keep them to ones macOS ships.
- For menu changes, `swift build && .build/debug/LangSmart --snapshot out.png` renders the dropdown offscreen in light and dark.
- Old names stay where users' state is keyed to them: the `LangSmart` executable, bundle identifier `com.oddurs.langsmart`, the status item autosave name, the "LangSmart Development" signing identity, and `~/Library/Application Support/LangSmart/`. Renaming any of them loses users' Accessibility grant, settings or learned data.
<!-- standard:end code -->
