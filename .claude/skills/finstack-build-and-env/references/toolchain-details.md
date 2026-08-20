# Toolchain details — finstack build & dev environment

Depth companion to `../SKILL.md`. Everything verified against the repo on 2026-07-07 (paths relative to repo root).

## 1. functions/loans — full module / replace graph

Every arrow below is a `replace` directive verified in the named `go.mod`. This graph is load-bearing: remove any edge and `go build ./...` breaks with `module com.loooans.app/... not found`.

| go.mod | module line | replaces |
|---|---|---|
| `functions/loans/go.mod` (root) | `com.loooans.app`, `go 1.22.12` | `api => ./api`, `utils => ./utils`, `types => ./types`, `job => ./job`, `triggers => ./triggers`, `test/fakes => ./test/fakes` |
| `api/go.mod` | `com.loooans.app/api`, `go 1.22` | `types => ../types`, `utils => ../utils` |
| `triggers/go.mod` | **`com.looans.app/triggers`** (two-o typo), `go 1.22` | `utils => ../utils`, `types => ../types` |
| `utils/go.mod` | `com.loooans.app/utils`, `go 1.22` | `types => ../types` |
| `types/go.mod` | `com.loooans.app/types`, `go 1.22` | (leaf) |
| `job/go.mod` | `com.loooans.app/job`, `go 1.22` | `utils => ../utils`, `types => ../types` |
| `test/fakes/go.mod` | `com.loooans.app/test/fakes`, `go 1.22.12` | `types => ../../types` |

Not separate modules (compile as packages of the root module): `cmd/` and `test/` (everything under `test/` except `test/fakes/`).

### The triggers two-o typo, in depth

`triggers/go.mod` line 1 reads `module com.looans.app/triggers` while every import site uses `com.loooans.app/triggers` (three o's). A directory `replace` resolves by path, not by the module line inside the replaced directory, so the build works. It stops working if:

- the root `replace com.loooans.app/triggers => ./triggers` is removed, or
- any package under `triggers/` imports another `triggers/` package by its full module path (self-import resolves against the declared two-o name).

Deliberate fix procedure (gate via `finstack-change-control`): edit `triggers/go.mod` line 1 to three o's, then `go mod tidy` in `triggers/` and in every module that replaces it (root; `api/` and `job/` do not import triggers as of 2026-07-07), then `CGO_ENABLED=0 go build ./... && CGO_ENABLED=0 go test ./...` from `functions/loans/`.

### cmd/ local runner is stale

`cmd/main.go` is a `package main` copy of the entry point for running `funcframework` locally (`ENVIRONMENT` required, listens on `PORT` or 8080). As of 2026-07-07 its `init()` registers only an old subset: HTTP `requestOtp`, `sendEmail`, `sometest` (with `addUser` commented out, no `verifyOtp`/`setPassword`/`sendPasswordSetupLink`) and only the first 5 triggers (through `notificationCreated` — no review/payment/userChanges/messageWritten). Do not assume local behavior via `cmd/` matches deployed behavior; the real registration list is `loooans_cloud_functions.go` `init()`. Running functions locally/deployed: `finstack-run-deploy-operate`.

## 2. CI toolchain parity

(Workflow anatomy is `finstack-run-deploy-operate`'s home; this is only the build-toolchain intersection.)

- Go workflows (`.github/workflows/loans-functions-*.yml`): `go-version: '1.22'`, Linux runners, plain `go test -v ./...` — the `CGO_ENABLED=0` workaround is macOS-only.
- Flutter app workflows (`loans-app-*.yml`): the Flutter version is auto-extracted from `apps/loans/.fvmrc` — upgrading Flutter requires no workflow edits. CI runs bare `flutter` (its own pinned install), builds **web only** (`flutter build web -t lib/main_<env>.dart`).
- CI parallelizes package codegen with `cut -d'|' -f1 /tmp/rebuild-list.txt | xargs -P 4 ... dart run build_runner build --delete-conflicting-outputs` plus caching; the local `packages/build_models.sh` is a plain sequential loop. Both produce the same generated files.
- sms-gateway CI (`sms-gateway.yml`): JDK 17 + Gradle, build/test only, no deploy.

## 3. iOS / SPM specifics (apps/loans)

State as of the Flutter 3.44 migration (finstack issue #46 / PR #56, completed 2026-05; detail in `apps/loans/MEMORY.md` "iOS migration" + "SPM is enabled"):

- `ios/Podfile`: `platform :ios, '13.0'` (3.44 rejects iOS 12). `IPHONEOS_DEPLOYMENT_TARGET` = 13.0 across all 9 flavor/build-type combinations in `Runner.xcodeproj/project.pbxproj`.
- UIScene lifecycle: `AppDelegate.swift` uses `@main` + `FlutterImplicitEngineDelegate`; `Info.plist` has `UIApplicationSceneManifest`.
- SPM lockfiles tracked in git: `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Treat like lockfiles — commit changes.
- Each flavor xcscheme (`development`, `staging`, `production`) carries a `<PreActions>` step running `$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh prepare`. These are generated per-flavor by `flutter build ios` — a NEW flavor needs one build to populate its scheme.
- `Podfile.lock` is 34 lines: only `flutter_keyboard_visibility`, `flutter_local_notifications`, `printing` (+ the Flutter runtime pod) remain on CocoaPods; everything else (Firebase, AppCheck, ...) is SPM. `pod install` is near-instant.
- SPM cannot be disabled going forward ("Disabling Swift Package Manager will not be allowed in a future version of Flutter") — which is why the no-spaces path rule is permanent.

Known debt (candidates for refile on finstack, none filed as of 2026-07-07):

- 5 plugins still on KGP: `camera_android_camerax`, `device_info_plus`, `firebase_remote_config`, `package_info_plus`, `shared_preferences_android`. Future Flutter releases will fail while KGP is in use — needs plugin upgrades.
- The 3 pod-only iOS plugins above emit future-deprecation warnings until they ship SPM support.
- Wasm builds flag incompatibilities in `image` + `flutter_keyboard_visibility_web` (`dart:html`) — JS web builds unaffected.

## 4. Android specifics (apps/loans)

- Migration shims in `android/gradle.properties`, added by the Flutter migrator — keep them: `android.builtInKotlin=false`, `android.newDsl=false`. Also present: `android.enableJetifier=true` (Jetifier is why dex transforms are memory-hungry → the 4096M rule).
- Release signing (`android/app/build.gradle`): if `ANDROID_KEYSTORE_PATH` env is set, reads `ANDROID_KEYSTORE_{PATH,ALIAS,PRIVATE_KEY_PASSWORD,PASSWORD}` (CI path); otherwise reads `android/key.properties` (`keyAlias`, `keyPassword`, `storeFile`, `storePassword`) — gitignored, obtain out of band. Debug builds use the default debug keystore, no setup.
- Flavors set `manifestPlaceholders.appName`: "Loooans" / "[STG] Loooans" / "[DEV] Loooans"; suffixes `""` / `.stg` / `.dev` on `com.loooans.app`.
- Core library desugaring enabled (`desugar_jdk_libs:2.1.4`); NDK pinned `27.0.12077973`.
- `android/app/google-services.json` is committed (multi-client for the flavors) — no per-dev download needed, unlike sms-gateway.

## 5. fvm mechanics in this monorepo

- The ONLY `.fvmrc` is `apps/loans/.fvmrc` (`{"flutter": "3.44.9"}`). `apps/loans/.fvm/` is gitignored.
- fvm resolves the version by walking up from the CWD looking for a project config. `packages/**` has none, so `fvm flutter` there uses the **global default** (`~/fvm/default` symlink). All four `packages/*.sh` scripts therefore depend on `fvm global 3.44.9` being set. Verified live: with global = 3.44.9, `fvm flutter --version` inside `packages/core/loooans_helpers` resolves 3.44.9. **Keep the global default and `.fvmrc` in step** — when they drifted (global 3.44.9, `.fvmrc` 3.44.0 uninstalled), every `fvm flutter` command in `apps/loans` silently blocked on an interactive "install it now?" prompt while `packages/**` kept working.
- SDK cache lives at `~/fvm/versions/<version>`; `fvm install` inside `apps/loans` reads the pin.
- Stale references you may still see: `ARCHITECTURE.md` and `apps/loans/MEMORY.md` "Key Notes" still say Flutter 3.38.4, and that MEMORY section also points at the pre-monorepo Go backend path. `.fvmrc` + both CLAUDE.md files are the truth (3.44.9).

## 6. sms-gateway specifics (apps/sms-gateway)

- Own Gradle world, independent of the loans app: root `build.gradle.kts` pins AGP 8.7.3, Kotlin 2.1.0 + compose plugin, google-services 4.4.4; wrapper Gradle 8.9; `gradle.properties` jvmargs 2048m (fine here — no Jetifier/dex pressure).
- `app/build.gradle.kts`: namespace/applicationId `com.loooans.smsgateway`, compileSdk/targetSdk 35, minSdk 31, Java/Kotlin 17, Compose enabled, `firebase-bom:34.9.0` (database + auth), compose-bom 2024.12.01.
- BOTH debug and release build types inject `BuildConfig.GATEWAY_EMAIL`/`GATEWAY_PASSWORD` from `local.properties` keys `gateway.email`/`gateway.password` (empty-string default — compiles without them, cannot sign in). `FirebaseConfig.kt` consumes them in `signIn()`.
- Debug: `applicationIdSuffix ".dev"`, app name "SMS Gateway (Dev)"; release: not minified, "Loooans SMS Gateway".
- Tests: `OtpEntryTest.kt` (JVM unit, MockK) via `./gradlew test`; `GatewayScreenTest.kt` (Compose instrumented) via `./gradlew connectedAndroidTest` (needs a device/emulator).
- Housekeeping note: a stray `java_pid7112.hprof` heap dump sits in the directory — untracked by git, safe to delete locally.
- What the gateway does at runtime + device operations: `finstack-run-deploy-operate`; the RTDB `/otp/` queue design: `finstack-architecture-contract` / `loans-domain-reference`.

## Re-verification one-liners

```bash
grep -n "replace" functions/loans/go.mod functions/loans/*/go.mod functions/loans/test/fakes/go.mod
grep -n "functions.HTTP\|functions.CloudEvent" functions/loans/cmd/main.go   # cmd staleness
grep -n "go-version" .github/workflows/loans-functions-*.yml
grep -n "flutter build web" .github/workflows/loans-app-*.yml
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 13.0" apps/loans/ios/Runner.xcodeproj/project.pbxproj
git -C . ls-files apps/loans/ios | grep Package.resolved
grep -n "kotlin-android\|com.android.application" apps/sms-gateway/build.gradle.kts
find . -name .fvmrc -not -path "./.worktrees/*" -not -path "./.claude/*"
```
