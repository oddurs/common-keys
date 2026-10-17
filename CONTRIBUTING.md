# Contributing

Thanks for helping. Common Keys stays small on purpose, so open an issue before starting anything large.

## Setup

```sh
scripts/setup          # wire the git hooks, once
scripts/dev-cert       # optional, once: a stable signing identity, so permissions survive rebuilds
scripts/agent doctor   # check tools and repository state
```

You need macOS 14.4 or later and Swift 6 or later. The Command Line Tools are enough; Xcode is not required.

## Workflow

Every change goes through a pull request, and pull requests merge themselves. `main` only moves forward when a pull request is merged; branch protection and the `pre-push` hook both enforce this.

Each change gets its own worktree, branch, and pull request:

```sh
scripts/agent start fix/short-description   # creates ../.worktrees/common-keys/fix/short-description
cd ../.worktrees/common-keys/fix/short-description
# ... make the change ...
scripts/task run                             # build it and open it
scripts/agent ship "fix(scope): say what changed" "Why it changed." --body-file pr.md
```

`ship` commits, runs the full check, opens the pull request with auto-merge, and waits. The pull request squash-merges itself once the `required` check passes. While it waits, `ship` rebases onto `main` whenever `main` moves and checks again. If a check fails or the rebase conflicts, it stops and says so: fix it, then run `scripts/agent ship` again. `commit`, `pr`, and `done` still work one step at a time.

The pull request takes its title from the branch's first commit, and that title becomes the squash commit on `main`, so make the first commit the one that names the change. The body states the problem, the approach, and where a reviewer should be sceptical.

Branch names are `<type>/<slug>`, where type is one of `feat fix chore docs perf refactor test`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`. Write the subject in the imperative, keep it to 72 characters, and leave off the trailing period. The body explains why; the diff already shows what. The `commit-msg` hook checks this.

Don't add tool or assistant attribution lines (co-author trailers, "generated with" footers). The hook rejects them.

## Checks

```sh
scripts/task check        # lint + test + build, the same thing CI runs
scripts/task test <name>  # just the tests whose name matches
```

A branch must pass this before it becomes a pull request. A bug fix comes with the test that would have caught it.

<!-- standard:begin checks -->
A change to how words are scored or decided needs `worldkey eval` numbers from before and after, so a reviewer can see what it costs in correct words changed.
<!-- standard:end checks -->

## Releases

```sh
scripts/release 1.2.0
```

Add user-facing changes under `## [Unreleased]` in `CHANGELOG.md` as you make them. `scripts/release` moves them under the new version with today's date, bumps the version in `Resources/Info.plist`, merges that through a pull request, tags the merge, and waits until the download is live. The release notes are that CHANGELOG section. Don't tag by hand.

## The standard

Common Keys follows the Common Tools app standard, kept in [oddurs/common-tools](https://github.com/oddurs/common-tools/tree/main/standard). The repository files, scripts, and settings are the same in every app. Only the parts between `standard:begin` and `standard:end` markers belong to this app. Change shared files there and apply them to every app, rather than editing one copy.

## Review

This is a solo-maintained project, so branch protection requires zero approvals, and pull requests merge themselves once the `required` check is green. Branches don't have to be up to date with `main` to merge; `ship` keeps them current instead.
