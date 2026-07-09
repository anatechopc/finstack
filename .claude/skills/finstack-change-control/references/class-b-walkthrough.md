# Class B walkthrough — shipping a doc-shape change backend-first

Concrete end-to-end procedure for a change both Go and Flutter parse (new
Firestore field/collection, renamed key, new trigger + UI). Template: the chat
pair, PR finstack#83 (backend, merged 2026-07-03) + finstack#84 (frontend).
All commands verified against this repo on 2026-07-07.

## 0. Decide it really is Class B

It is Class B if any Firestore/RTDB document shape read or written by BOTH
sides changes. It is NOT Class B if the change is purely one side reading data
it already reads (Class A), even if the file lives in a shared-looking place.
When unsure, grep both sides for the JSON key:

```bash
grep -rn "field_name" functions/loans/ --include='*.go' | grep -v _test
grep -rn "field_name" packages/ apps/loans/lib/ --include='*.dart' | grep -v '.g.dart'
```

## 1. Backend PR (1/2, deploy first)

```bash
git checkout develop && git pull
git checkout -b feat/<thing>-backend        # observed names: feat/chat-backend,
                                            # feat/user-provisioning-backend,
                                            # feature/mobile-verification-backend
```

Work checklist (details in the named skills):

- Handler as adapter + core with fakes-based tests — `finstack-testing-and-validation`.
- New function? Register in `functions/loans/loooans_cloud_functions.go`
  `init()` AND add a `gcloud functions deploy` line to
  `.github/scripts/deploy_functions.sh` (hand-maintained list; use the
  environment-prefixed `--trigger-event-filters-path-pattern`).
- **Tolerate the old shape.** The backend deploys while old clients still
  write old-shaped docs; parse missing/legacy fields defensively (see
  `utils.ToInt64` — commit `4e2b36a` — for the fail-closed idiom).
- Dates: `.UnixMilli()`, never `time.Time` (root `MEMORY.md`, Timestamp saga).
- `go build -v ./...` and `go test -v ./...` (macOS: `CGO_ENABLED=0 go test ./...`).
- Update `functions/loans/MEMORY.md` in the same branch.

PR into `develop`, titled like the precedent:

```
feat(<scope>): backend — <summary> (1/2, deploy first)
```

On the PR, CI builds + tests but does NOT deploy (deploy job is
`if: github.event_name == 'push'`).

## 2. Merge backend, confirm the dev deploy

Merge with a merge commit (never squash). The push to `develop` fires
`Loans Functions: Development`. Confirm the deploy run succeeded:

```bash
gh run list --workflow="Loans Functions: Development" --limit 3
# expect: a 'push' event run on develop, conclusion success (~4-5 min).
gh run watch <run-id>   # if it is still in progress
```

Real trace from the chat pair (retrieved live 2026-07-07): PR run on
`feat/chat-backend` (`pull_request`, 47s, build only) followed by the merge
push run on `develop` (`push`, 4m30s, build + deploy).

If the new trigger needs a composite index or a console rule change, do that
now and leave the repo note (Class C section of SKILL.md) — precedent commit
`3d94ccc` (chat) committed the composite index into
`apps/loans/firestore.indexes.json`, RTDB rules into both `database.rules*.json`
files, and the console-managed Firestore/Storage rules as `.reference` files.

## 3. Frontend PR (2/2)

```bash
git checkout develop && git pull            # now contains the backend merge
git checkout -b feat/<thing>-frontend
```

- Entity/model changes in `packages/` + regenerate:
  `fvm flutter pub run build_runner build --delete-conflicting-outputs`
  (or `packages/build_models.sh` for all).
- Write dates through the `handleDateTime*` JSON helpers (already the default
  on `BaseEntity`-style entities).
- `fvm flutter analyze` + `fvm flutter test --test-randomize-ordering-seed random`.
- Update `apps/loans/MEMORY.md` in the same branch.

PR titled `feat(<scope>): frontend — <summary> (2/2)`. Merge only after the
backend deploy from step 2 is confirmed live in the target environment.

## 4. Staging / production

The same two-step order repeats per environment lane: the branch that deploys
the backend must carry the backend change before (or together with, since one
push deploys both functions and app) clients that write the new shape.
As of 2026-07-07 no `release/**` or `master` branch exists yet — the first
staging/prod push is a first-time event; see `finstack-run-deploy-operate`
before attempting it, and name release branches `release/vX.Y.Z` (the app
staging workflow only matches `release/v*`).

## Anti-patterns (all real)

- **Monolithic full-stack PR** — PR finstack#43 (mobile verification) was
  closed unmerged and re-split into #44 (backend) + #45 (frontend).
- **Frontend first** — old clients cannot be un-shipped; a deployed trigger
  that crashes on a new field poisons every write until redeployed.
- **Backend writes `time.Time`** — Timestamp contamination saga
  (PRs finstack#47/#48/#49; full story in `finstack-failure-archaeology`).
- **Forgetting deploy_functions.sh** — the function builds, tests, merges, and
  silently never deploys; the script, not `init()`, is the deploy manifest.
