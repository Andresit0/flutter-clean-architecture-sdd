---
description: |
  Single-PR pipeline: gather ALL current changes → full-disclosure dossier (files, diff, secret
  scan, commit plan, PR title/body) → MANDATORY confirmation → atomic commits on ONE branch →
  validate (analyze, format, tests) → publish exactly ONE pull request. Use when every change
  belongs to a single reviewable unit; use `super-pull-request` when the changes must be split
  into stacked PRs.
---

# Super One Pull-Request — Single-PR Pipeline

Create **ONE** pull request containing **ALL** current changes. Never split, never stack.

This command MUST present the user with the complete information that will be uploaded in the PR
(files, diff, secret scan, commits, title, body) BEFORE committing or pushing, and MUST show a
**table of the commits** the PR will contain.

Non-negotiables:

- Exactly one PR. Never create stacked PRs (that is `super-pull-request`).
- Never commit secrets; STOP and ask if any are found.
- Conventional Commits; the PR title becomes the squash commit on the base branch.
- Never force push, never amend, never use `--no-verify`.
- Confirm before committing, pushing, or publishing.
- All artifacts (commits, PR title, PR body) in English.

---

## Step 0 — Load skills

- `.opencode/skills/app-changes/SKILL.md` (changes table)
- `.opencode/skills/app-agent-fix-analyzer-issues/SKILL.md` (repair)
- `.opencode/skills/app-agent-fix-tests/SKILL.md` (repair)

---

## Step 1 — Detect base branch

```bash
git branch -a | grep -i develop
```

If `develop` exists (local or `origin/develop`) → `$BASE=develop`.
If it does NOT exist → **STOP** and ask the user which branch should be used as base.

---

## Step 2 — Gather all changes

```bash
git status --short
git diff $BASE..HEAD --stat
git diff $BASE..HEAD
git log --oneline -10
```

---

## Step 3 — Safety check (secrets)

Scan the changes for:

```txt
.env
.env.*
token
credential
secret
private
*.pem
*.key
```

If found → **STOP.** Ask whether to exclude / convert to example / intentionally include.
Never commit secrets automatically.

---

## Step 4 — Plan the commits (ONE PR)

Group **all** changes into atomic semantic commits using Conventional Commits
(`feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`).
Do not mix unrelated concerns. Every commit belongs to the SAME single PR.

Output the commits table:

| # | Files | Commit message |
|---|-------|----------------|
| 1 | pubspec.yaml, pubspec.lock | `build(deps): ...` |
| 2 | .github/workflows/ci.yml | `ci(workflows): ...` |
| ... | ... | ... |

Also output a summary: total commits, changed files, `+/-` lines, estimated review time.

---

## Step 5 — Present the FULL PR dossier (MANDATORY — everything that will be uploaded)

Output one consolidated report. The user must see **exactly** what will be uploaded before anything
is committed or pushed.

```
### PR — `<type>(<scope>): <subject>`
Base: $BASE   ←   Head: <branch>

### Files (what will be uploaded)
| Path | Status (A/M/D/R) | +adds / -dels |

### Commits (what the PR will contain)
| # | Commit message | Files |

### Diff
<full diff ($BASE..HEAD); if too large, a clear summary plus the raw diff on request>

### Secret scan
clean | <findings>

### Proposed PR body
<## Summary / ## Why / ## Changes / ## Testing>

### PR metadata
title: <type(scope): subject>   labels: <label>   base: $BASE
```

---

## Step 6 — CONFIRMATION REQUIRED

**STOP.** Wait for explicit approval.

Accepted: `yes`, `approve`, `execute`, `publish`.

If the user modifies anything → return to Step 4 (commit plan) / Step 5 (dossier).

---

## Step 7 — Create ONE branch and apply commits

If currently on the base branch, create a type-prefixed branch (never commit directly to
`develop`/`main`; direct pushes are blocked by branch protection).

```bash
git checkout -b <type>/<short-kebab-name>
```

For each planned commit, stage ONLY its files (never `git add -A`):

```bash
git add <file1> <file2> ...
git diff --cached --stat      # verify nothing unintended is staged
git commit -m "<semantic message>"
```

For renames/deletes:

```bash
git add <new_path> && git rm <old_path>
git commit -m "<type>(<scope>): <description>"
```

Rules:

- Include add/modify/delete/rename.
- Do not revert changes; do not amend; do not force push; do not use `--no-verify`.
- One `git commit` per planned message.

---

## Step 8 — Validate

```bash
flutter pub get
dart run build_runner build          # if annotated code (@freezed/@riverpod/@JsonSerializable) changed
flutter gen-l10n                     # ONLY if a .arb file changed (generated localizations are committed)
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

> `build_runner` errors MUST NOT be hidden (never append `|| true`).
> The format check is the exact command used by the CI `Analyze` job; `flutter analyze` does NOT
> detect formatting. Run it AFTER `build_runner`/`gen-l10n`.

Expected: 0 analyzer issues, 0 test failures, 0 files need formatting.

### Repair loop (max 5 iterations)

| Failure type | Repair agent | Action |
|---|---|---|
| Analyzer issues | `app-agent-fix-analyzer-issues` | Fix file-by-file |
| Test failures | `app-agent-fix-tests` | Fix each failing test |
| Build runner errors | Manual | Fix generated-code mismatches |
| Formatting | Manual | `dart format <files>` → commit `style(scope): apply dart format` |

Commit only the files the repair changed. If still failing after 5 iterations → **STOP**, escalate.

---

## Step 9 — Publish ONE PR (always ask first)

**STOP.** Present the validated summary and ask:
"All changes validated on a single branch. Push and create the PR?"

If the user says anything other than an affirmative → STOP; the branch stays local.

```bash
git push -u origin <branch>
gh pr create \
  --base $BASE \
  --head <branch> \
  --title "<type>(<scope>): <subject>" \
  --label "<label>" \
  --body-file <body>
```

PR title rules (mandatory — the repository squash-merges with `squash_merge_commit_title: PR_TITLE`,
so the title becomes the commit on the base branch):

- Conventional Commits: `<type>(<scope>): <subject>`.
- English, imperative mood, ≤ 72 characters.
- No `PR {N}:` prefix and no stack numbering.

Label map:

| PR type | Label |
|---------|-------|
| `feat` | `enhancement` |
| `fix` | `bug` |
| `docs` | `documentation` |
| `build` | `dependencies` |
| `ci` | `github_actions` |
| other | none |

Exactly **one** PR. If the changes genuinely require splitting, STOP and use `super-pull-request`
instead.

---

## Step 10 — Return the result

```
| PR | Branch → Base | URL | Status |
|----|---------------|-----|--------|
| 1  | <branch> → $BASE | https://... | Open |
```

| Commit | Files | Message |
|--------|-------|---------|
| <short-sha> | <files> | <semantic message> |

---

## Edge Cases

| Situation | Handling |
|-----------|----------|
| No changes vs `$BASE` | STOP — nothing to PR. |
| On `develop`/`main` with uncommitted changes | Create a branch first; direct push is blocked. |
| Only docs/MD changes | Single PR; skip build_runner/test steps that do not apply. |
| Generated files (`.g.dart`/`.freezed.dart`/l10n) | Include with their source files (Rule 29). Never separate. |
| PR title > 72 chars | Truncate the subject; move detail into the body. |
| Base branch protection requires up-to-date (`strict`) | `gh pr update-branch <PR>` before merging. |
| Conflicts while creating the branch | STOP; ask the user to resolve manually. |
| Secrets detected | STOP and ask; never commit. |
