---
name: finstack-build-and-env
description: Use when setting up a finstack development machine from scratch, or when a local build fails — e.g. "dyld: missing LC_UUID" during go test, Gradle OOM/daemon death during Android builds, SPM/Xcode cannot resolve pubspec or Package.swift, the wrong Flutter version is picked up, "module com.loooans.app/... not found" in functions/loans, build_runner codegen problems across packages, ADC/credential errors running Go functions locally, or the sms-gateway app failing on missing google-services.json / gateway BuildConfig fields.
---

# finstack — Build & Dev Environment

Recreate a working dev environment for the finstack monorepo from a blank machine, and get past the known local-build traps. Everything below was verified against the repo (and, where marked, executed live) on 2026-07-07.

## When NOT to use this skill

| You want to... | Use instead |
|---|---|
| Run the app / deploy functions / operate CI or the SMS gateway device | `finstack-run-deploy-operate` |
| Understand env prefixes (`dev_`/`stg_`), Firebase projects, flags, secrets | `finstack-config-and-environments` |
| Write or fix tests | `finstack-testing-and-validation` |
| Know what you are allowed to change and how | `finstack-change-control` |
| Debug a runtime failure (not a build failure) | `finstack-debugging-playbook` |

Day-to-day build/test/analyze commands are already in the auto-loaded `CLAUDE.md` files (root "Quick Reference Commands", `apps/loans/CLAUDE.md` "Commands", `functions/loans/CLAUDE.md` "Build & Test"). This skill covers what those do NOT: first-time setup, toolchain versions, module layout, and platform gotchas.

## The three build worlds

| World | Path | Stack | Build entry |
|---|---|---|---|
| Flutter app + shared packages | `apps/loans/`, `packages/core/`, `packages/loans/` | Dart/Flutter 3.44.0 via fvm | `fvm flutter ...`, `packages/*.sh` |
| Cloud Functions | `functions/loans/` | Go multi-module (root `com.loooans.app`) | `go build -v ./...` |
| SMS gateway | `apps/sms-gateway/` | Kotlin / Jetpack Compose, standalone Gradle | `./gradlew assembleDebug` |

`apps/loans/` has platform shells for android, ios, macos, web, windows. Android + web are the actively exercised targets; iOS builds since the 3.44 migration (see iOS section); windows/macos are unexercised scaffolds.

## Toolchain checklist (fresh machine)

Reference dev box on 2026-07-07: macOS 26.2 (Darwin 25), Apple Silicon.

| Tool | Required | Verify | On ref box |
|---|---|---|---|
| fvm | 3.x/4.x | `fvm --version` | 4.0.4 |
| Flutter | **3.44.0 exactly** (pinned in `apps/loans/.fvmrc`) | `cd apps/loans && fvm flutter --version` | 3.44.0 / Dart 3.12.0 |
| Go | 1.22.x (`functions/loans/go.mod` says `go 1.22.12`; CI uses `go-version: '1.22'`) | `go version` | go1.22.12 |
| Java (JDK) | 17 (Android builds + sms-gateway CI) | `java -version` | OpenJDK 17.0.17 (Homebrew) |
| gcloud | recent | `gcloud --version` | 549.0.0 |
| gh | recent | `gh --version` | 2.86.0 |
| firebase-tools | recent (only for index/rules deploys — `finstack-run-deploy-operate`) | `firebase --version` | 14.27.0 |
| Xcode | 26.x (iOS/macOS only) | `xcodebuild -version` | 26.2 |
| CocoaPods | 1.16.x (iOS only; 3 plugins still pod-based) | `pod --version` | 1.16.2 (rbenv) |
| Android SDK | compileSdk 36 + NDK 27.0.12077973 (Android Studio installs on demand) | `sdkmanager --list_installed` | — |

Run the doctor script for a one-shot check of all of this plus the traps below:

```bash
.claude/skills/finstack-build-and-env/scripts/env_doctor.sh
```

**NEVER clone the repo into a path containing spaces.** Flutter 3.44 auto-enables Swift Package Manager, which URL-encodes the project path (`%20`) and then fails to find `pubspec.yaml`. This is why the repo lives at `.../AnaheimTechnologies/finstack`, not `.../Anaheim Technologies/...` (finstack PR #56; story in `finstack-failure-archaeology`).

## Flutter side — bootstrap order

```bash
# 1. Install the pinned Flutter (reads apps/loans/.fvmrc -> 3.44.0)
cd apps/loans && fvm install

# 2. TRAP: only apps/loans has a .fvmrc. The packages/*.sh scripts run
#    `fvm flutter` from packages/<group>/<pkg>/ where there is NO project
#    config, so fvm falls back to the GLOBAL default. Set it:
fvm global 3.44.0
# verify: readlink ~/fvm/default   -> .../fvm/versions/3.44.0

# 3. Fetch deps + generate all model code (run from packages/)
cd ../../packages
./get_dependencies.sh      # fvm flutter pub get, every package
./build_models.sh          # build_runner codegen, every package

# 4. App deps
cd ../apps/loans && fvm flutter pub get
```

Then run/analyze/test per `apps/loans/CLAUDE.md`. Notes:

- **Always `fvm flutter`, never bare `flutter`** (CLAUDE.md rule; bare `flutter` may be a different SDK entirely).
- The four `packages/*.sh` scripts (`get_dependencies`, `build_models`, `clean_package`, `update_dependencies`) are plain sequential bash loops over `core/*/` then `loans/*/` — no parallelism, expect `build_models.sh` to take a while. (CI parallelizes the same codegen with `xargs -P 4` and caching — see `finstack-run-deploy-operate`.)
- Single-package codegen and `gen-l10n` commands: see `apps/loans/CLAUDE.md`. `apps/loans/l10n.yaml` already sets `arb-dir: lib/l10n/arb`.
- `update_dependencies.sh` runs `pub upgrade --major-versions` in every package — that is a change, not setup. Don't run it while bootstrapping.
- Never edit `*.g.dart` / `firebase_options*.dart` (generated; CLAUDE.md rule).
- Expect 2 pre-existing package test failures (`address_repository`, `bank_details_repository`) — not your breakage; see `finstack-testing-and-validation`.
- Firebase config files are committed (`apps/loans/lib/firebase_options*.dart`, `android/app/google-services.json`) — no per-developer Firebase setup is needed to build.

## Go side — functions/loans module layout

Root module `com.loooans.app` (go 1.22.12) + sub-modules, each with its own `go.mod`, wired by `replace` directives in the root `go.mod`:

| Dir | Module | Note |
|---|---|---|
| `api/` | `com.loooans.app/api` | HTTP handlers |
| `triggers/` | **`com.looans.app/triggers`** | ⚠ declares TWO-o `looans` — see below |
| `utils/` | `com.loooans.app/utils` | has its own `replace` to `../types` |
| `types/` | `com.loooans.app/types` | leaf |
| `job/` | `com.loooans.app/job` | disabled scheduled jobs |
| `test/fakes/` | `com.loooans.app/test/fakes` | in-memory fakes for tests |
| `cmd/` | (root module) | local `funcframework` runner — STALE: registers only an old subset of functions (no `verifyOtp`/`setPassword`/chat triggers) |
| `test/` (excl. fakes) | (root module) | adapter+core tests live here |

**The triggers typo (do not "fix" casually):** `triggers/go.mod` declares `module com.looans.app/triggers` (two o's) while everything imports the three-o path. It builds ONLY because the root `replace com.loooans.app/triggers => ./triggers` maps the import to the directory regardless of the inner module line. Consequences: never remove or "clean up" the replace directives, and a nested package inside `triggers/` that self-imports by full path would break. Correcting the typo is a legitimate but deliberate change (rename module line + `go mod tidy` everywhere) — gate it via `finstack-change-control`.

```bash
cd functions/loans
go build -v ./...            # verified green 2026-07-07

# macOS: plain `go test` DIES on macOS 26.x:
#   dyld[...]: missing LC_UUID load command in .../utils.test
#   signal: abort trap
# (reproduced live 2026-07-07). Always disable cgo locally:
CGO_ENABLED=0 go test ./...  # verified green 2026-07-07
```

CI (Linux) runs plain `go test -v ./...` — the workaround is macOS-only. More rules (register in `init()`, `go mod tidy` per sub-module, never add sub-module deps to root `go.mod`) are in `functions/loans/CLAUDE.md`. Test authoring pattern (adapter+core with fakes): `finstack-testing-and-validation`.

## Local credentials for the Go Admin SDK (ADC)

Functions use keyless Application Default Credentials — there is no service-account key in the repo, deliberately (an embedded key was exposed and disabled by Google, finstack #60; **never re-embed one** — see `finstack-security-hardening`). For local runs:

```bash
gcloud auth application-default login
```

**ADC-drift trap:** the gcloud CLI account and the ADC account are stored separately and CAN diverge — `gcloud` commands work while the Admin SDK gets permission errors (or vice versa). When you hit `Unauthenticated`/permission errors locally, check both:

```bash
gcloud auth list                                        # CLI account
gcloud auth application-default print-access-token >/dev/null && echo ADC-OK
```

Re-run `gcloud auth application-default login` with the right account if they differ. Runtime also requires `ENVIRONMENT` to be set (`development`/`staging`/`production`) — running functions locally is covered in `finstack-run-deploy-operate`.

## Android — apps/loans

Toolchain floor after the Flutter 3.44 upgrade (finstack PR #56, commit `b0953b7`). Downgrading any of these breaks the build:

| Axis | Value | Where |
|---|---|---|
| AGP | 8.11.1 | `android/settings.gradle` |
| Kotlin | 2.2.20 | `android/settings.gradle` + `kotlin-stdlib-jdk7` in `app/build.gradle` |
| Gradle wrapper | 8.14.3 | `android/gradle/wrapper/gradle-wrapper.properties` |
| compileSdk / targetSdk | 36 (minSdk 29) | `android/app/build.gradle` |
| Java / jvmTarget | 17 | `android/app/build.gradle` |
| NDK | 27.0.12077973 | `android/app/build.gradle` |
| **`org.gradle.jvmargs`** | **`-Xmx4096M` — REQUIRED** | `android/gradle.properties` |

- **Do not lower jvmargs.** 2048M OOMs (Jetifier/dex transforms) at this toolchain; 4096M is the working value (root `MEMORY.md` + `apps/loans/MEMORY.md`).
- Keep the Flutter-migrator shims `android.builtInKotlin=false` and `android.newDsl=false` in `gradle.properties`.
- Flavors: `production` (no suffix), `staging` (`.stg`), `development` (`.dev`) — applicationId `com.loooans.app`.
- Debug builds need no signing setup. Release builds need either `ANDROID_KEYSTORE_*` env vars or `android/key.properties` (not committed).
- Version build numbers are **seconds** since epoch (`scripts/bump_version.sh`, `date +%s`). Never switch to millis — 13-digit values overflow Android's Int `versionCode` (story: `finstack-failure-archaeology`).

## iOS / macOS — apps/loans (state as of 2026-07-07)

The 3.44 iOS migration is DONE (see `apps/loans/MEMORY.md` "iOS migration"): platform iOS 13.0, UIScene lifecycle, SPM enabled. Verified on disk: `ios/Podfile` pins `platform :ios, '13.0'`; `Podfile.lock` is tracked and tiny (34 lines) because SPM now owns most dependencies; CocoaPods 1.16.2 is installed on the ref box. Caveat: no iOS build was executed during skill authoring — toolchain presence and repo state verified, build itself UNVERIFIED here.

- 3 plugins still on CocoaPods (`flutter_keyboard_visibility`, `flutter_local_notifications`, `printing`) — `pod install` is near-instant.
- SPM lockfiles (`Package.resolved` under `Runner.xcodeproj`/`Runner.xcworkspace`) are tracked — commit changes to them like a lockfile.
- Adding a new flavor? Run `fvm flutter build ios --flavor <name>` once — the per-flavor xcscheme `PreActions` (SPM prepare step) is generated by a build.
- Known debt, no finstack issue filed as of 2026-07-07 (refile candidates — `finstack-roadmap-and-frontier`): 5 plugins still on KGP (camera_android_camerax, device_info_plus, firebase_remote_config, package_info_plus, shared_preferences_android — future Flutter will hard-fail on KGP) and the 3 pod-only plugins above emit SPM deprecation warnings.

## sms-gateway — apps/sms-gateway

Standalone Gradle project (NOT under fvm/Flutter). Own toolchain: AGP 8.7.3, Kotlin 2.1.0, Gradle wrapper 8.9, JDK 17, compileSdk/targetSdk 35, minSdk 31.

Setup (both files are gitignored — obtain out of band):

1. `app/google-services.json` — download from Firebase console (`loooans-dev-stg` for dev, `loooans-prod` for prod device).
2. Root `local.properties` — add the gateway service account credentials:
   ```properties
   gateway.email=<gateway user email>
   gateway.password=<gateway user password>
   ```
   These are injected as `BuildConfig.GATEWAY_EMAIL` / `BuildConfig.GATEWAY_PASSWORD` via `buildConfigField` (`app/build.gradle.kts`) and consumed by `FirebaseConfig.kt` sign-in. ⚠ The README's step 2 ("Update FirebaseConfig.kt with the password") is stale — do NOT hardcode credentials in source; use `local.properties`.
3. Build: `./gradlew assembleDebug` (debug flavor gets applicationIdSuffix `.dev`, app name "SMS Gateway (Dev)").

Empty `gateway.*` properties still compile (default `""`) but the app cannot sign in at runtime. Installing/operating the physical gateway device: `finstack-run-deploy-operate`.

## Known traps — consolidated

| Symptom | Cause | Fix |
|---|---|---|
| `dyld: missing LC_UUID ... signal: abort trap` in `go test` | macOS 26.x + cgo test binaries | `CGO_ENABLED=0 go test ./...` |
| Wrong Dart/Flutter errors in `packages/` scripts | No `.fvmrc` outside `apps/loans`; fvm fell back to a different global default | `fvm global 3.44.0` |
| Gradle daemon OOM / dies during dex | `org.gradle.jvmargs` below 4096M | restore `-Xmx4096M` in `apps/loans/android/gradle.properties` |
| Xcode/SPM can't find `pubspec.yaml` / `Package.swift`, `%20` in paths | repo cloned under a path with spaces | move repo to a space-free path |
| `versionCode ... For input string` on Android build | build number > Int max (millis) | keep `bump_version.sh` on `date +%s` seconds |
| `module com.loooans.app/... not found` in functions/loans | replace directives removed/bypassed, or triggers two-o typo exposed | restore root `go.mod` replaces; treat typo fix as a gated change |
| Admin SDK `Unauthenticated` locally while gcloud works | ADC account drifted from CLI account | `gcloud auth application-default login` as the right account |
| 2 package tests always fail | pre-existing (`address_repository`, `bank_details_repository`) | ignore / see `finstack-testing-and-validation` |
| sms-gateway builds but never signs in | empty `gateway.email`/`gateway.password` in `local.properties` | fill them; README step 2 is stale |

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on the reference dev box (macOS 26.2). Executed live that day: `go build -v ./...` (green), `CGO_ENABLED=0 go test ./...` (green), plain `go test` (reproduced LC_UUID abort), `fvm flutter --version` from a package dir (resolved 3.44.0 via global default). NOT executed: full app builds (Android/iOS/web), `build_models.sh` end-to-end, sms-gateway assembleDebug.

Re-verify before trusting drifted facts:

```bash
cat apps/loans/.fvmrc                                            # Flutter pin
grep '^go ' functions/loans/go.mod                               # Go version
head -1 functions/loans/triggers/go.mod                          # typo still present?
grep jvmargs apps/loans/android/gradle.properties                # 4096M
grep -E "com.android.application|kotlin.android" apps/loans/android/settings.gradle
grep distributionUrl apps/loans/android/gradle/wrapper/gradle-wrapper.properties
grep -E "compileSdk|minSdk|targetSdk|ndkVersion" apps/loans/android/app/build.gradle
head -1 apps/loans/ios/Podfile && wc -l apps/loans/ios/Podfile.lock
grep -n "buildConfigField" apps/sms-gateway/app/build.gradle.kts
.claude/skills/finstack-build-and-env/scripts/env_doctor.sh      # everything at once
```

Deeper detail (full replace graph, CI toolchain parity, iOS/SPM specifics): `references/toolchain-details.md`.
