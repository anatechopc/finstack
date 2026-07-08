# The rules-into-source campaign

Turn the console-managed Firestore/Storage rules into source of truth, wire a
deploy path, gate it under change control, then codify the three DEFERRED
authorization rules. This is the systemic fix behind the recurring "DEFERRED"
theme. **Do not skip the export/diff step — the live rules are the only correct
copy, and the repo files are stale placeholders that would break the app if
deployed blindly.**

## Current reality (verified 2026-07-07)

> Canonical, maintained home for this file-by-file deploy reality is
> `finstack-run-deploy-operate` §7. The table below is a task-local snapshot for
> running this campaign — if it disagrees with §7, §7 wins; reconcile before
> deploying.

| Surface | Repo file | Wired in `firebase.json`? | Live rules location | Trap |
|---|---|---|---|---|
| Firestore | `apps/loans/firestore.rules` | **No** (no `firestore.rules` key) | Console only | File is VGV stub, `allow ... if request.time < timestamp.date(2024,6,22)` (expired) → deploying denies all reads |
| Storage | `apps/loans/storage.rules` | **Yes** | Console only | File is `allow read, write: if false` → deploying breaks chat uploads |
| RTDB (dev/stg) | `apps/loans/database.rules.json` | **Yes** | Source-controlled & real | — |
| RTDB (prod) | `apps/loans/database.rules.prod.json` | **No** | Source-controlled but manual deploy | Nothing auto-deploys it |

Three shipped features with authorization **deferred to console** (intended rules
documented in `apps/loans/MEMORY.md`):

1. **Review responses** — admin/reviewModerator of the review's `provider_id`
   company may write only `response*` fields; borrowers read-only
   (`apps/loans/MEMORY.md:27`).
2. **Borrower payment `pending`->`confirmed` transition** — borrower may create
   `pending`; only teller/admin may move to `confirmed`/`rejected`
   (`apps/loans/MEMORY.md:388`).
3. **Lender bank-details writes** — a company admin may write `bank_details` where
   `dataId == their company` (`apps/loans/MEMORY.md:41`).

Chat rules were shipped as reference stubs (NOT deployed):
`apps/loans/firestore.rules.chat.reference`, `storage.rules.chat.reference` —
these document the intended chat rules and their known v1 limitations.

> Note: `apps/loans/README.md:15` references `docs/security-rules.md`, which does
> **not exist** (verified 2026-07-07) — a dangling doc pointer to fix as part of
> this campaign.

## Step 1 — export the live rules from BOTH projects

Projects: `loooans-dev-stg` (dev + staging) and `loooans-prod` (prod). Run
`scripts/export-live-rules.sh <projectId> <outDir>` for each, or the commands
below. **All read-only.**

### Firestore + Storage (Firebase MCP — easiest)

The firebase MCP tool `firebase_get_security_rules` (present, `readOnlyHint`)
returns the live active ruleset for `firestore`, `storage`, or `rtdb`. Set the
active project first, then call it per service. This is the lowest-friction path
inside a Claude session.

### Firestore + Storage (CLI — `firebase init`)

`firebase init firestore` downloads the existing console rules
("Downloaded the existing Firestore Security Rules from the Firebase console")
before offering to overwrite. Run it in a **scratch dir** (not the repo) pointed
at each project so it cannot clobber the repo files, then copy the downloaded
content out. Same for `firebase init storage`.

### Firestore + Storage (REST fallback)

The rules live in the Firebase Rules API (`firebaserules.googleapis.com/v1`):

1. `GET /v1/projects/<projectId>/releases` → find the release whose `name` starts
   with `projects/<projectId>/releases/cloud.firestore` (or `firebase.storage`);
   read its `rulesetName`.
2. `GET /v1/<rulesetName>` → `source.files[].content` is the live rules text.

(These are the exact endpoints firebase-tools uses internally —
`lib/gcp/rules.js`.)

### RTDB

Live RTDB rules are served at `/.settings/rules.json` on the database instance:

```
https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app/.settings/rules.json
https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app/.settings/rules.json
```

(URLs verified in `functions/loans/utils/initialize_firebase.go`.) `GET` with an
auth token, or use the firebase MCP `firebase_get_security_rules` with `rtdb`.
CLI `database:rules:get`/`:list` exist but are gated behind the `rtdbrules`
experiment (`firebase experiments:enable rtdbrules`), so prefer the MCP tool or
the `.settings/rules.json` endpoint.

## Step 2 — diff live vs repo, decide the source of truth

For each surface, diff the exported live rules against the repo file:

- **Firestore:** live vs `apps/loans/firestore.rules` (expect large diff — repo is
  the expired stub). The live rules are the truth; capture them.
- **Storage:** live vs `apps/loans/storage.rules` (expect the live version to allow
  chat uploads; repo is deny-all). Live is truth.
- **RTDB:** live vs `database.rules.json` / `database.rules.prod.json` (should be
  close — these are real; reconcile any drift, e.g. console hotfixes).

Confirm the three deferred rules and the chat rules are present in the live
Firestore/Storage exports; note anything the live rules have that the intended
specs in `MEMORY.md` do not (console hotfixes never written down).

## Step 3 — commit the live rules as source of truth

Replace the stale repo files with the reconciled live rules:

- `apps/loans/firestore.rules` — the real Firestore ruleset (incl. the 90-day
  mobile-number lock, chat rules, per-company/role rules, and the three deferred
  rules once codified in Step 6).
- `apps/loans/storage.rules` — the real Storage ruleset (chat upload rules).

Because Firestore rules cannot parameterize a collection prefix, the same match
blocks must be pasted **once per active prefix per project** (`dev_`, `stg_` in
`loooans-dev-stg`; unprefixed in `loooans-prod`) — this constraint is spelled out
in `firestore.rules.chat.reference`. Keep that structure.

## Step 4 — wire a deploy path

- Add a `firestore.rules` key to `firebase.json` (currently only
  `firestore.indexes` is present). Storage is already wired.
- Prod RTDB: `firebase.json` supports one `database.rules` reference, so the prod
  file needs a separate deploy. **Note:** `README.md:219` documents
  `firebase database:rules:set database.rules.prod.json` — that subcommand does
  **not exist** in the installed CLI (14.27.0 has `database:rules:get/list/stage/
  canary/release`, no `:set`). Use a supported path instead: temporarily point
  `firebase.json` `database.rules` at the prod file for a
  `firebase deploy --only database --project loooans-prod`, or `PUT` the file to
  the prod `/.settings/rules.json` endpoint. Fix the README as part of this
  campaign.

  > ⚠ **If you take the temporary-swap path, revert it in the SAME step and NEVER
  > commit it.** `firebase.json` has a single `database.rules` key, and that key is
  > also what the dev/staging RTDB deploy reads. If the swap (prod file) leaks into
  > a commit or is left in place, the next `firebase deploy --only database` against
  > `loooans-dev-stg` ships the **prod** ruleset to dev/staging — the
  > dev/staging-pointed-at-prod separation that unwritten rule #5 forbids
  > (`finstack-change-control`), and the exact hazard `finstack-run-deploy-operate`
  > §7 flags for the `database.rules` row. Prefer the `PUT` to
  > `/.settings/rules.json`, which never touches `firebase.json`.

Deploy *mechanics* (how `firebase deploy` / `deploy-indexes.sh` run today, where
output lands) are the primary home of `finstack-run-deploy-operate` — implement
the actual pipeline change there and reference it here.

## Step 5 — gate under change control

Any rules deploy is a production-affecting change. It must go through the normal
branch->env->deploy flow and PR review (primary home:
`finstack-change-control`), and — per **unwritten rule #3** — any interim console
change made while building this path must be recorded in the repo. Never
hand-edit prod rules and leave the repo behind.

## Step 6 — codify the three deferred rules

Once `firestore.rules` is source of truth and deployable, write the three deferred
authorization rules into it (specs in `apps/loans/MEMORY.md` as above), test them
against the Firestore emulator (rules unit tests were the intent of the refiled
loooans#134 — see `finstack-roadmap-and-frontier` / `finstack-testing-and-validation`),
and deploy through the gated path. Delete the `.chat.reference` stubs once their
content is folded into the real files.

## Done-when

- [ ] Live Firestore + Storage rules exported from **both** projects and committed.
- [ ] `firebase.json` wires `firestore.rules`; prod RTDB deploy path is real and
      documented (README corrected).
- [ ] Deploy path goes through change control; no un-noted console edits remain.
- [ ] The three deferred rules + chat rules are in-source and emulator-tested.
- [ ] `apps/loans/MEMORY.md` + root `MEMORY.md` updated; dangling
      `docs/security-rules.md` reference resolved.
