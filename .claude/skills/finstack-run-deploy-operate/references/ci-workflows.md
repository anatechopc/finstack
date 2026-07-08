# CI Workflow Anatomy (verified 2026-07-07)

Seven workflows in `.github/workflows/`. This file is the detail behind the SKILL.md inventory table. Diff-verified: the three app workflows differ only in the lines listed under "What differs"; same for the three functions workflows.

## loans-functions-{development,staging,production}.yml

Identical shape; two jobs.

**Triggers:** `workflow_dispatch` + `push` and `pull_request` on the env branch, path-filtered to `functions/loans/**` and `.github/workflows/loans-functions-*.yml`.

**Job `build`** (runs on PR and push): checkout → `setup-go` with Go `1.22` → `go build -v ./...` → `go test -v ./...`, all with `working-directory: functions/loans`.

**Job `deploy`** (needs `build`; **`if: github.event_name == 'push'`** — PRs never deploy):
1. checkout
2. `google-github-actions/auth@v2` — OIDC workload identity federation (job has `id-token: write`); no SA key secrets anywhere.
3. `setup-go` + `google-github-actions/setup-gcloud@v2` (`version: '>= 390.0.0'`)
4. `../../.github/scripts/deploy_functions.sh -e <env> -p <project>`

**What differs across the three files:**

| | development | staging | production |
|---|---|---|---|
| Branch | `develop` | `release/**` | `master` |
| Deploy args | `-e development -p loooans-dev-stg` | `-e staging -p loooans-dev-stg` | `-e production -p loooans-prod` |
| WIF provider | `projects/565409367468/.../github-actions/providers/github-actions` | same as dev | `projects/444559784514/.../github/providers/github-actions` (note pool name `github`, not `github-actions`) |
| Deploy SA | `github@loooans-dev-stg.iam.gserviceaccount.com` | same as dev | `github@loooans-prod.iam.gserviceaccount.com` |
| setup-go in deploy job | `@v5` | `@v5` | **`@v4`** (drift; harmless, align when next touched) |

## loans-app-{development,staging,production}.yml

Shared skeleton: `concurrency` group per workflow+ref with `cancel-in-progress: true`; `defaults.run.working-directory: apps/loans`.

**Job `get_flutter_version`** (all three): greps `"flutter"` out of `apps/loans/.fvmrc` and exposes it as an output. Every Flutter setup step uses `subosito/flutter-action@v2` with this output → **Flutter upgrades require zero workflow edits**.

**The codegen-cache block** (repeated verbatim in `build_and_preview` and `deploy_to_*` jobs — the core of the triplicate hazard):
1. `flutter pub get` in every `packages/{core,loans}/*/`.
2. `actions/cache@v4` restore of `/tmp/codegen-cache` (key `codegen-${{ github.run_id }}`, restore-keys `codegen-`).
3. Per package with `build_runner` in its pubspec: hash of `pubspec.yaml` + **ALL** package Dart sources (not just its own — a shared-helper change must invalidate dependents' generated code; that cross-package staleness bug is why, see comment in the workflow and finstack PR #61-era fix).
4. Cache hit → untar cached `*.g.dart`; miss → rebuild list.
5. Rebuilds run `dart run build_runner build --delete-conflicting-outputs` with **`xargs -P 4`** (parallel; local `packages/build_models.sh` is sequential).

**Web build:** `flutter build web -t lib/main_<env>.dart --release --dart-define=ENVIRONMENT=<env> --output build/web/<env>`. CI always passes the `ENVIRONMENT` define — mirror this in any manual build.

**Hosting deploy:** `FirebaseExtended/action-hosting-deploy@v0`, `entryPoint: apps/loans`, per-env `projectId`/`target`/SA secret:

| | projectId | target | firebaseServiceAccount secret | channelId |
|---|---|---|---|---|
| dev PR (`build_and_preview`) | loooans-dev-stg | develop | `FIREBASE_SERVICE_ACCOUNT_LOOOANS_DEV_STG` | (none → preview channel) |
| dev push (`deploy_to_development`) | loooans-dev-stg | develop | same | `live` |
| staging (`deploy_to_staging`) | loooans-dev-stg | staging | same | `live` |
| production (`deploy_to_production`) | loooans-prod | production | `FIREBASE_SERVICE_ACCOUNT_LOOOANS_PROD` | `live` |

Note: hosting deploys use these **SA-key secrets** (the action's mechanism), unlike the functions workflows which are keyless WIF.

**Node / Happy-Eyeballs fix** (every hosting deploy step): `actions/setup-node@v4` with Node 24 and `NODE_OPTIONS: --no-network-family-autoselection`. Reason (verified comment in workflow, saga in `finstack-failure-archaeology`): Node 20+ IPv6/IPv4 racing caused "Premature close" on keep-alive connections to googleapis; firebase-tools recovers everywhere except the non-idempotent release POST, which false-400s ("is the current active version"). Do not remove.

**Version-bump jobs** (commit as `github-actions[bot]`, message `chore(version): bump to X` — guarded so bump commits don't re-trigger bumps):

| Workflow | Job | When | Runs |
|---|---|---|---|
| development | `update-version-on-merge` | push to `develop` | `./scripts/bump_version.sh` (dev mode) |
| staging | `update-version-on-release` | push/create on `release/v*` | `./scripts/bump_version.sh staging` |
| production | `update-version-on-master` | push/create on `master` | parses the merge-commit message ("Merge pull request #N from user/branch"); source branch matching `*/release/v*` or `*/hotfix/*` → `./scripts/bump_version.sh production`; otherwise no bump |

**Deploy-job gating:** `deploy_to_*` jobs use `always() && get_flutter_version.result == 'success' && (workflow_dispatch || push-to-env-branch)` — i.e. they run even if the version-bump job skipped itself, and `workflow_dispatch` can force a deploy of the current branch state.

**What differs across the three app workflows** (beyond names): triggers (dev has `pull_request`+`push` on `develop`; staging adds `create` on `release/v*` and drops the PR preview job; production has `push`/`create` on `master`, no PR job), bump mode, build target/define/output dir, hosting project/target/secret. Staging and production have **no** `build_and_preview` job — no PR preview against those branches.

## sms-gateway.yml

**Build + test only. There is deliberately NO deploy job** — the gateway runs on a manually provisioned physical phone (SKILL.md §8).

Triggers: dispatch; push on `develop` / `feat/sms-gateway*`; PR on `develop` / `main` (note: `main` is vestigial — the repo has no `main` branch), path-filtered `apps/sms-gateway/**`.

Steps: JDK 17 (temurin) → `gradle/actions/setup-gradle@v4` → writes **dummy** `google-services.json` files into `app/src/debug/` and `app/src/release/` (so the google-services plugin resolves without real credentials) → `./gradlew testDebugUnitTest` → `./gradlew assembleDebug`. The produced APK is a CI artifact of buildability only — real devices get locally built APKs with real `google-services.json` + `local.properties` credentials.

## Editing rules of thumb

1. Touching a shared step in `loans-app-*.yml` or `loans-functions-*.yml` → edit all three, then diff-pairs to confirm only the known env lines differ.
2. Workflow filename globs are part of the path filters (`loans-app-*.yml`, `loans-functions-*.yml`) — renaming a workflow silently breaks its own retrigger.
3. Deploy gating conditions (`if: github.event_name == 'push'`, the `deploy_to_*` `if:` blocks) are load-bearing; loosening them makes PRs deploy.
4. As of 2026-07-07 `master`/`release/*` don't exist yet — the staging/prod workflows are dormant but will fire on first branch creation (`create:` triggers included). Creating those branches IS a deploy action; treat it as change-controlled (`finstack-change-control`).
