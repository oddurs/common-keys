# Working in this repository

Common Keys is a macOS menu bar app that fixes words typed on the wrong keyboard layout. It runs on **WorldKey**, an engine library that also ships as the `worldkey` CLI. Swift, AppKit plus SwiftUI, no package dependencies.

## The seam

Do all automation through `scripts/task`. CI and the git hooks call nothing else.

```sh
scripts/task fmt        # format in place
scripts/task fmt:check  # swift format lint --strict
scripts/task lint       # fmt:check, then build with warnings as errors
scripts/task test       # swift-testing suite
scripts/task build      # universal build/Common Keys.app and build/worldkey
scripts/task check      # lint + test + build, what CI runs
```

## Workflow

- Never commit to `main`. It moves only when a pull request is merged; the `pre-push` hook and branch protection enforce this.
- One unit of work, one worktree, one branch, one pull request: `scripts/agent start <type>/<slug>`, work in the printed path, `scripts/agent commit`, `scripts/agent pr`, then `scripts/agent done` after the merge.
- Branch types: `feat fix chore docs perf refactor test`.
- `scripts/task check` must be green before a pull request. Never use `--no-verify`.
- A pull request description states the problem, the approach, and where a reviewer should be sceptical.

## Commits

Conventional Commits: `type(scope): subject`, imperative, at most 72 characters, no trailing period. The body says why. Never add assistant or tool attribution: no co-author trailers, no "generated with" footers. The `commit-msg` hook rejects them.

## Code

- `Sources/WorldKey` is the engine, in layers: keys, keyboards (`KeyLayout`, `Composer`, `InputSources`), evidence (`Scorer`, `Orthography`, `Lexicon`, `Memory`), decisions (`Detector`). A layer never reaches up to the one above it. It holds no UI state.
- `Sources/LangSmart` is the app shell (the target keeps the pre-rename name): event tap and injection (`Engine`), status item and dropdown, Settings, hot keys. `Sources/WorldKeyCLI` is a thin wrapper over the library.
- A key press is a key code plus modifiers, never a character. Read layouts with the system translator; don't hard-code character tables.
- Leaving a correct word alone matters more than fixing a wrong one. Any change to scoring or decisions comes with `worldkey eval` numbers before and after, and "correct words changed" must not rise.
- Text typed in a converting input method (Japanese, Chinese) is the user's pick and is never read back or fixed.
- Nothing leaves the Mac; the app makes no network requests. Typing is never logged: only daily counts and what the user taught (words meant in another layout, words to leave alone, mixed-up keys, per-app layouts) are saved, under `~/Library/Application Support/LangSmart/`.
- A bug fix comes with the test that would have caught it. Tests read the layouts and dictionaries installed on the machine; keep them to ones macOS ships.
- For menu changes, `swift build && .build/debug/LangSmart --snapshot out.png` renders the dropdown offscreen in light and dark.
- Old names stay where users' state is keyed to them: the `LangSmart` executable, bundle identifier `com.oddurs.langsmart`, the status item autosave name, the "LangSmart Development" signing identity, and `~/Library/Application Support/LangSmart/`. Renaming any of them loses users' Accessibility grant, settings or learned data.
