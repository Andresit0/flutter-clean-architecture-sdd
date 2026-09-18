# APP_RELEASE — Release procedure (runbook)

Permanent procedure to ship a release (`release/*` → `main` → tag → GitHub Release → back-merge).
Follows the Git Flow in `README.md` → Git Flow and the branch-protection policy in
`.github/REQUIRED_CHECKS.md`.

Central rule: **squash into `main`; tag only after that exact commit passes CI; normal merge
(never squash) back to `develop`.**

## Versioning

- The version lives in a single source of truth: `pubspec.yaml` (`version:`). Android
  (`flutter.versionName`/`flutter.versionCode`) and iOS (`$(FLUTTER_BUILD_NAME)` /
  `$(FLUTTER_BUILD_NUMBER)`) read it from there — do NOT edit platform files.
- SemVer: MAJOR = breaking, MINOR = new compatible functionality, PATCH = compatible fixes.
  Release commit: `chore(release): bump version to X.Y.Z+N`; tag: annotated `vX.Y.Z`.

## Steps

### 1. Preflight (verify, do not assume)

```bash
git switch develop && git pull --ff-only origin develop
git log --oneline main..develop          # release content
gh pr list --state open --base develop   # PRs that could change develop
gh pr list --state open --base main      # PRs that could change main
DEVELOP_SHA="$(git rev-parse origin/develop)"
gh run list --workflow ci.yml --branch develop --commit "$DEVELOP_SHA" \
  --limit 1 --json databaseId,headSha,conclusion
# expected: headSha == DEVELOP_SHA and conclusion == success
gh api repos/<owner>/<repo>/branches/main/protection \
  --jq '{checks:.required_status_checks.contexts,strict:.required_status_checks.strict}'
```

### 2. Freeze moving branches — only if required

If automated PRs (Dependabot) are actively modifying `develop` during the release, temporarily pause
their auto-merge so `develop` does not move mid-flow (a moving base makes the release/back-merge PRs
`BEHIND` under `strict` protection and forces repeated `update-branch` loops). If nothing is moving,
no freeze is needed.

```bash
for PR in $(gh pr list --state open --json number,author \
  --jq '.[] | select(.author.login=="app/dependabot") | .number'); do gh pr merge "$PR" --disable-auto; done
```

### 3. Create the release branch from develop

```bash
git switch -c release/vX.Y.Z develop
git push -u origin release/vX.Y.Z
```

### 4. Release commits (one per concern)

- Bump `version:` in `pubspec.yaml` and `flutter pub get`. `git status` must show ONLY `pubspec.yaml`;
  if `pubspec.lock` changed, revert it (never edit it by hand).
  Commit: `chore(release): bump version to X.Y.Z+N`.
- Update `CHANGELOG.md` (Keep a Changelog): rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and
  leave a fresh empty `## [Unreleased]`. Commit: `docs(changelog): add vX.Y.Z`.

### 5. Local validation

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --exclude-tags golden
flutter test --tags golden
```

### 6. PR to `main`

Title `release: vX.Y.Z`. The body becomes the commit body on `main` (`squash_merge_commit_title:
PR_TITLE`, `squash_merge_commit_message: PR_BODY`). The `Branch Source Gate` passes because the head
matches `release/*`.

```bash
gh pr create --base main --head release/vX.Y.Z --title "release: vX.Y.Z" \
  --label dependencies --body-file <release-notes>
RELEASE_PR="<PR_NUMBER>"     # from the created PR
```

Wait for the **8 required checks**:

1. Analyze
2. Test
3. Test Goldens
4. Build iOS
5. Build Android
6. Build Web
7. Gitleaks
8. Branch Source Gate

`Integration` is conditional (gated by the repository variable `RUN_DEVICE_INTEGRATION`) and is **not**
a required check.

### 7. Squash merge

`main` requires 2 approvals + code-owner review; on a personal account GitHub blocks self-approval.
Operational gate = required checks green + an explicit human merge. If a temporary bypass is needed,
lower required approvals to 0, merge, RESTORE, and record it in the PR thread.

```bash
gh api -X PATCH repos/<owner>/<repo>/branches/main/protection/required_pull_request_reviews \
  -F required_approving_review_count=0 -F require_code_owner_reviews=false
gh pr merge "$RELEASE_PR" --squash --delete-branch
gh api -X PATCH repos/<owner>/<repo>/branches/main/protection/required_pull_request_reviews \
  -F required_approving_review_count=2 -F require_code_owner_reviews=true -F dismiss_stale_reviews=true
```

### 8. Verify `main` and prove local == remote

```bash
git switch main
git pull --ff-only origin main
git show HEAD:pubspec.yaml | grep '^version:'                         # X.Y.Z+N
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" \
  && echo "OK: local main == origin/main" \
  || { echo "ERROR: local main != origin/main"; exit 1; }
```

### 9. CI gate bound to the EXACT commit (before tagging)

```bash
MAIN_SHA="$(git rev-parse HEAD)"
RUN_ID="$(gh run list --workflow ci.yml --branch main --commit "$MAIN_SHA" \
  --limit 1 --json databaseId,headSha \
  --jq '.[0] | select(.headSha=="'"$MAIN_SHA"'") | .databaseId // empty')"
test -n "$RUN_ID" || { echo "ERROR: no ci.yml run for $MAIN_SHA yet"; exit 1; }
gh run watch "$RUN_ID" --exit-status \
  || { echo "ERROR: CI failed for $MAIN_SHA — STOP, no tag"; exit 1; }
```

### 10. Annotated tag from `main`

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
test "$(git rev-parse main)" = "$(git rev-parse vX.Y.Z^{commit})" \
  && echo "OK: vX.Y.Z == main" \
  || { echo "ERROR: vX.Y.Z != main"; exit 1; }
```

### 11. GitHub Release (before the back-merge)

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <release-notes> --target main
```

### 12. Back-merge `main` → `develop` — NORMAL MERGE (never squash)

Create a fresh branch from `origin/develop`, merge `origin/main` (in the normal case only the release
version/changelog changes appear; review any additional differences before merging), and open a PR to
`develop`.

```bash
git switch develop && git pull --ff-only origin develop
git switch -c chore/back-merge-vX.Y.Z
git merge origin/main
git push -u origin chore/back-merge-vX.Y.Z
gh pr create --base develop --head chore/back-merge-vX.Y.Z \
  --title "chore(release): back-merge vX.Y.Z"
BACKMERGE_PR="<PR_NUMBER>"   # from the created PR

# Check the PR merge state.
gh pr view "$BACKMERGE_PR" --json mergeStateStatus

# If mergeStateStatus == BEHIND (develop moved while the PR was open and `strict` requires up-to-date):
gh pr update-branch "$BACKMERGE_PR"
# Otherwise skip update-branch.

# Then merge normally (never squash):
gh pr merge "$BACKMERGE_PR" --merge --delete-branch
```

`gh pr update-branch "$BACKMERGE_PR"` is **conditional, not mandatory**: run it only when `develop`
moved while the PR was open and `strict` protection reports the PR as `BEHIND`. If `develop` did not
move, skip it.

If conflicts occur, resolve them according to the intended post-release state; do not blindly use
`--theirs`/`--ours`.

### 13. Verify `develop` (version + ancestry invariant)

```bash
git switch develop && git pull --ff-only origin develop
git show origin/develop:pubspec.yaml | grep '^version:'               # X.Y.Z+N
git merge-base --is-ancestor origin/main origin/develop \
  && echo "OK: main is contained in develop" \
  || { echo "ERROR: main is NOT contained in develop"; exit 1; }
```

### 14. Verify the deployment

Pushing `main` triggers `.github/workflows/deploy-web.yml` (GitHub Pages). Verify the run is bound to
the release commit (not merely that a recent run exists) and, when possible, the demo
(login → Clinical History → Lab Results → Chart).

```bash
MAIN_SHA="$(git rev-parse origin/main)"
gh run list --workflow deploy-web.yml --branch main --commit "$MAIN_SHA" \
  --limit 1 --json databaseId,headSha,conclusion
# expected: headSha == MAIN_SHA and conclusion == success
```

### 15. Restore automation state

If step 2 froze Dependabot, restore its auto-merge.

```bash
for PR in $(gh pr list --state open --json number,author \
  --jq '.[] | select(.author.login=="app/dependabot") | .number'); do gh pr merge "$PR" --auto --squash; done
```

Unfreeze `develop` after the back-merge is merged.

## Operational invariants

- **Entry to production:** `release/* | hotfix/*` ──SQUASH──▶ `main`
- **Production identity:** `CI(main SHA) == SUCCESS` ──▶ `tag(main SHA)`
- **Return to development:** `main` ──NORMAL MERGE (never squash)──▶ `develop`

## State invariants

- **Production:** `SHA(tag) == SHA(main)`.
- **Synchronization:** `SHA(main) ∈ history(develop)` (`git merge-base --is-ancestor origin/main origin/develop`).

## Troubleshooting / history: ancestry repair

Only applicable when **`git merge-base --is-ancestor origin/main origin/develop` returns non-zero**
(i.e. `main` is not contained in `develop`). This happens when previous back-merges were
**squash-merged** instead of using `--merge`. Do **not** use this as part of the normal flow; have it
explicitly reviewed.

```bash
git fetch origin
git merge -s ours origin/main -m "chore(release): sync release/vX.Y.Z with main"
git push
```

`-s ours` preserves the current branch's tree/content while creating a merge commit whose history
records `origin/main` as an integrated parent (it does **not** take `main`'s tree). **Never use
`-X ours`** — it is a different conflict-resolution strategy and, from an old merge base, can corrupt
lines.

## Rollback

If the release breaks on `main`: a revert is not enough (the tag is immutable) — ship a `hotfix/*`
branch from `main`, bump the PATCH version, and follow the same gate.
See `docs/release-rollback-runbook.md`.
