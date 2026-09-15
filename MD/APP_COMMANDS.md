### Required commands (in order after any change)

> All commands must be run from the project root

```bash
# 1. Install / sync dependencies
flutter pub get

# 2. Regenerate localization code (run whenever .arb files change)
flutter gen-l10n

# 3. Regenerate Riverpod code (run whenever @riverpod files change)
dart run build_runner build --delete-conflicting-outputs

# 4. Check formatting (CI "Enforce Dart formatting" runs the same scope — analyze does NOT catch it)
dart format --output=none --set-exit-if-changed lib test integration_test

# 5. Analyze
flutter analyze

# 6. Unit / widget tests (goldens excluded for a fast local loop; CI Test job uses the same flag)
flutter test --exclude-tags golden

# 6b. Golden tests (tagged @Tags(['golden']) — declared in dart_test.yaml, no "A tag was used" warning)
# CI runs them on Linux with `flutter test --tags golden`. Regenerate fixtures with --update-goldens.
flutter test --tags golden
flutter test --tags golden --update-goldens

# 7. Run on macOS
flutter run -d mac --dart-define-from-file=.env

# 8. Build the web demo (GitHub Pages). Mirrors ci.yml `build-web` and deploy-web.yml.
flutter build web --release --base-href /flutter-clean-architecture-sdd/ \
  --dart-define=ENVIRONMENT=dev \
  --dart-define=API_HOST=tudesarrollador.com \
  --dart-define=API_USE_HTTPS=true
```

### Dependency upgrade procedure

Use this sequence for any dependency bump (dependabot or manual PR):

```bash
# 1. Edit pubspec.yaml constraint(s) (never the lock by hand)
# 2. Regenerate the lock — this fixes spurious SDK-pinned bumps (intl/test):
flutter pub get
# 3. If codegen toolchain changed (freezed/json_serializable/@riverpod):
dart run build_runner build --delete-conflicting-outputs
# 4. Regenerate localization if .arb changed:
flutter gen-l10n
# 5. Full battery (see below): format, analyze, tests, goldens, integration, builds
```

Caveats:

- **SDK pin.** The Flutter version lives once in `pubspec.yaml`
  (`environment.flutter: 3.47.4`); CI resolves it via `flutter-version-file`.
- **Never force-bump SDK-pinned packages.** Flutter 3.47.4 requires `intl`
  (`^0.20.3`, forced by `flutter_localizations`) and pins `test_api` (0.7.12),
  `matcher` (0.12.20), `meta` (1.19.0), `vector_math` (2.4.2). If
  `flutter pub get` fails on `intl`/`test`, revert those constraints — do not
  resolve by hand.
- **Codegen toolchain.** Stays on analyzer 12 / freezed 3.2.6 with Dart
  language version 3.12 (`environment.sdk: ^3.12.0`): Dart LV 3.13 rejects the
  `final` parameters its generated code emits. Adopting freezed 4 (analyzer 13)
  is deferred until a language-version bump (issue #62).
- **Android platform**: if a plugin requires a higher SDK than the Flutter
  default, set `compileSdk`/`minSdk` explicitly in
  `android/app/build.gradle.kts` (e.g. `flutter_secure_storage 11` →
  `compileSdk 37`).
- Dependabot reads `.github/dependabot.yml` from the **default branch (`main`)**;
  its ignore rules (intl/test/freezed) are active since release v1.1.0 (issue #63 resolved).
- **Dependabot does NOT honor `ignore` rules inside grouped/multi-dependency
  updates** (dependabot-core #10122/#13213). The manifest constraints plus CI
  are the real guard: grouped PRs that rewrite `intl`/`test` fail
  `flutter pub get` and can never merge. When that happens, close the PR and
  reopen the valid dep as a manual PR.
- Regenerated `.g.dart`/`.freezed.dart` files must be committed with their
  source (Rule 29).

### Integration tests (need a connected device/emulator)

```bash
flutter test integration_test/[feature_name]_integration_test.dart -d <device-id> --dart-define-from-file=.env
```

Integration tests use fake repositories (`_FakeAuthRepository`, `_FakeTokenStore`, `_FakeLabResultsRepository` and failure-variant repositories like `_FakeNetworkErrorRepository`, `_FakeOfflineWithCachedDataRepository`) — no live HTTP calls needed. lab_results integration tests (`integration_test/lab_results_integration_test.dart`) inject the fake repository via Riverpod overrides in `app.main(overrides: [...])`.

---

### Environment variables

All variables are passed via `--dart-define` (or `--dart-define-from-file=.env`) at run/build time. Never hardcode them in code — use `String.fromEnvironment` with a safe default.

| Variable | Default | Purpose |
|---|---|---|
| `ENVIRONMENT` | `dev` | Selects `AppEnvironment` variant: `dev` / `staging` / `production` |
| `API_HOST` | `localhost` | Overrides the API host (used by `DevEnvironment`). Android emulator: `10.0.2.2` |
| `API_USE_HTTPS` | `false` | Force HTTPS for the API base URI even on a non-443 port (e.g. the web demo at `https://tudesarrollador.com:5111`). Used by `AppEnvironment.useHttps` → `AppUris` and `connectivity_providers` |
| `PINNED_CERT_1`, `PINNED_CERT_2` | — (unset) | SHA-256 hashes for certificate pinning. Enforced (`requirePinnedCertificates`) only in `staging`/`production`; `dev` (and the web demo) do NOT enforce pinning. |
