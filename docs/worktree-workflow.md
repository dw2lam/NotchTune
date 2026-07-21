# Worktree Workflow

This repository should use Git worktrees as the default shape for development.

## Goals

- keep `main` stable enough to integrate and verify
- give each agent or human one isolated checkout
- reduce accidental interference across unrelated slices
- keep merge and rollback boundaries obvious

## Roles

### 1. Integration worktree

- Path: `/Users/wangruobing/Personal/open-island`
- Branch: `main`
- Purpose: fetch, mirror `main` after PR merges, and verify

Rules:

- Do not start feature work here.
- Do not edit, commit, or push directly on `main`.
- Only use this worktree to inspect the overall state, fetch, update local `main` with `git pull --ff-only`, and run final verification after PRs merge.

### 2. Topic worktrees

- Path pattern: `/Users/wangruobing/Personal/open-island-<topic>`
- Branch pattern: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `investigate/<topic>`
- Purpose: isolated implementation for one slice

Rules:

- One worktree owns one branch.
- One branch should represent one coherent slice.
- If two agents are working in parallel, they must use different worktrees and different branches.
- If two slices would touch many of the same files, do not run them in parallel unless one slice clearly owns the shared files.

## Standard Lifecycle

### Create a new topic worktree

From the integration worktree:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/open-island-<topic> -b <branch-name> origin/main
```

Example:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/open-island-island-polish -b feat/island-polish origin/main
```

## Work inside the topic worktree

Inside the topic worktree:

```bash
git status -sb
```

Then follow the normal repository workflow:

1. read the relevant files
2. make one coherent change
3. verify the change
4. commit before stopping

If the branch needs new `main` changes during development:

```bash
git fetch origin
git rebase origin/main
```

If rebase is risky for that slice, merge `origin/main` into the topic branch explicitly instead.

## Integrate back into `main`

First make sure the topic worktree is committed and verified.

Push the feature branch and open a PR targeting `main`.

- Open a normal ready-for-review PR by default.
- Open a draft PR only when the user explicitly asks for draft mode, or when the branch is intentionally WIP or has known verification gaps.
- If a PR is opened as draft, state why in the PR body or final summary.

After the PR merges, return to the integration worktree:

```bash
git switch main
git fetch origin
git pull --ff-only origin main
```

## Push policy

- Push topic branches when you want backup, review, or collaboration.
- Do not push `main` directly. Merge through PRs, then update the integration worktree with `git pull --ff-only`.
- Tooling defaults do not override this policy; for example, a publish helper that defaults to draft PRs must still follow the repository default above.

## Cleanup

After the topic branch is merged:

```bash
git worktree remove /Users/wangruobing/Personal/open-island-<topic>
git branch -d <branch-name>
```

If the branch was pushed upstream:

```bash
git push origin --delete <branch-name>
```

## Recommended Conventions

- Keep topic names short and concrete: `codex-hooks-noise`, `island-geometry`, `claude-usage`.
- Prefer sibling directories under `/Users/wangruobing/Personal/` so all worktrees stay easy to discover.
- Do not leave long-lived unmerged worktrees drifting far away from `origin/main`.
- If a worktree becomes exploratory rather than shippable, rename the branch into `investigate/<topic>` or close it.
- When assigning work to multiple agents, split by file ownership or subsystem, not by vague goal.

## Suggested Workstream Layout

Good parallel split:

- `feat/island-visual-polish`: `Sources/NotchTuneApp/Views/*`
- `fix/codex-hook-installer`: `Sources/NotchTuneCore/CodexHookInstaller.swift`
- `investigate/jump-accuracy`: terminal jump diagnostics and docs

Bad split:

- two agents both editing `AppModel.swift`
- one branch mixing hook installer work, island UI changes, and docs cleanup
- direct feature edits on the shared `main` worktree
