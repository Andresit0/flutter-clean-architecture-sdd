# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions prior to 1.1.0 predate this changelog and are tracked in the git history.

## [Unreleased]

### Maintenance

- **Toolchain** — migrated the project from Flutter `3.44.0` to `3.47.4`
  (Dart `3.13.3`). The SDK version is now pinned once in `pubspec.yaml`
  (`environment.flutter`) and every CI job resolves it via `flutter-version-file`
  (no hardcoded `flutter-version`); a new architecture gate in
  `test/architecture/workflow_gates_test.dart` prevents drift.
- **Dependencies** — `intl` is now `^0.20.3`, required by the Flutter 3.47.4
  `flutter_localizations` constraint (`0.20.2` no longer resolves). Transitive
  SDK pins moved to `test_api 0.7.12`, `matcher 0.12.20`, `meta 1.19.0` and
  `vector_math 2.4.2`. The codegen toolchain stays on analyzer 12 / freezed
  3.2.6 with Dart language version 3.12 (Dart LV 3.13 rejects the `final`
  parameters its generated code emits); adopting freezed 4 is tracked in #62.
- **Platforms** — applied the Flutter 3.47 migrations: iOS minimum `15.0`,
  macOS minimum `12.0`, and `analysis_options.yaml` excludes the platform
  directories via the official `AnalysisOptionsMigration`.
- **Docs** — corrected the `go_router` version in the README (`^18.0.0`) and
  aligned the dependency-policy documentation with the new SDK pins.

## [1.1.3] - 2026-08-31

### Maintenance & Stabilization

- **Dependencies** — bumped `go_router` from `17.5.0` to `18.0.0` (compatible,
  verified by the full required-check matrix) and the GitHub Actions group
  (4 SHA-pinned actions: `codecov-action`, `upload-pages-artifact`,
  `configure-pages`, `deploy-pages`).
- **i18n** — translated the remaining Spanish content (documentation, test
  descriptions/reasons, and BDD/integration fixtures) to English, normalizing
  the codebase to a single language.
- **Dependency policy** — exact-pinned `intl` to `0.20.2` and documented that
  Dependabot does not honor `ignore` rules inside grouped updates
  (dependabot-core #10122/#13213); a stored `@dependabot ignore` was applied
  on PR #113 to stop broken grouped proposals. This is the first release that
  tags the actual `main` HEAD, correcting the v1.1.2 tag-lineage anomaly.

## [1.1.2] - 2026-08-19

### Fixed

- Certificate pinning is now enforced only in environments that require it
  (`staging`/`production` via `requirePinnedCertificates`). Fixes the web demo
  (release build with the `dev` environment) staying stuck on the loading
  screen because `CertificatePinner` threw a `StateError` for empty pins.
- Startup no longer hangs if session restore fails: boot errors are logged and
  the app proceeds to the login screen.

## [1.1.1] - 2026-08-19

### Added

- Flutter Web demo published to GitHub Pages: `AppEnvironment.useHttps` is now
  configurable via `--dart-define=API_USE_HTTPS=true` (forces HTTPS on a
  non-443 API port, e.g. `https://tudesarrollador.com:5111`).
- `web/404.html` so GoRouter deep links survive a browser refresh on Pages.

### Changed

- `Build Web` CI gate (compile) and automatic web deployment to GitHub Pages
  via `.github/workflows/deploy-web.yml` (Pages Artifact model).

### Docs and Tooling

- README Live Demo section, check-count alignment, repo rename references and
  web demo documentation.

[1.1.3]: https://github.com/Andresit0/flutter-clean-architecture-sdd/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/Andresit0/flutter-clean-architecture-sdd/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/Andresit0/flutter-clean-architecture-sdd/compare/v1.1.0...v1.1.1

## [1.1.0] - 2026-08-19

### Added

- Shared domain models in `lib/shared/models/`: `PatientEntity`, `ClinicalHistoryEntity` (+ 6 sub-entities) and `LabResultEntity` (+ sub-entities and enums).
- `lab_results` feature end-to-end: domain layer, infrastructure layer, presentation layer, router navigation, network endpoint with browser failure mapping, and database store + serializer.
- `fl_chart` wrapped behind the `ITrendChart` seam (trend chart capability).
- `SaveSessionUseCase` extracted from auth with codegen auth providers.
- `SeamNotBoundException` fail-fast seam type for unbound DI seams.
- Reusable state components (loading/empty/error) in the design system.

### Changed

- Online-first repository refactor: `OnlineFirstRepository` template-method base adopted by `clinical_history` and `lab_results` repositories.
- Clinical history card details split into section widgets.
- DIO network stack decomposed into error mapper, request and retry executors.
- Database abstracted behind the `IDatabaseHandle` facade (sembast-free).
- `AppEnvironment` refactored to a static-free sealed class.
- `lab_results` DTOs migrated to freezed and adapted to `OnlineFirstRepository`.
- `appNavigatorProvider` seam now throws `SeamNotBoundException` when unbound.
- Dependencies upgraded: `fl_chart`, `flutter_secure_storage` 11.0.0, `go_router` 17.5.0, `build_runner` 2.15.1.

### Docs and Tooling

- Documentation updates, AI tooling alignment (shared wire contracts, Rule 29) and CI/governance hardening (enterprise merge gates, dependabot policy).

[1.1.0]: https://github.com/Andresit0/flutter-clean-architecture-sdd/compare/v1.0.0...v1.1.0
