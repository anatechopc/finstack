# Chat — Plan 4 (Security rules, index, deploy)

> **For agentic workers:** This plan is a **deploy/config checklist**, not TDD. The repo has **no Firestore/Storage rules test harness** (no `@firebase/rules-unit-testing`, no emulator test suite), and `firestore.rules`/`storage.rules` in the repo are stale stubs — the live rules are **console-managed** per project. So Firestore/Storage rules here are exact text to paste + a manual apply checklist; RTDB rules and the index are real committable edits. Steps use checkbox (`- [ ]`) syntax. An **optional** emulator-test task is included at the end (Task 7) if you want automated rule coverage.

**Goal:** Lock down chat data and enable the inbox query in all environments: Firestore rules for `chat_rooms` + `messages`, Storage rules for `chat/…`, RTDB rules for `typing/…`, the inbox composite index, and the deploy/IAM checklist for the `messageWritten` trigger.

**Environments:** dev + staging share project `loooans-dev-stg` (collections prefixed `dev_` / `stg_`); production is `loooans-prod` (no prefix). All `firebase` commands run from `apps/loans/` (where `firebase.json` lives).

**Spec:** `docs/superpowers/specs/2026-07-01-chat-messaging-design.md` §9.

### Reality found in the repo (why this plan looks the way it does)
- `apps/loans/firestore.rules` = default expired allow-all stub; `apps/loans/storage.rules` = `allow read, write: if false` stub. Neither is the deployment source — **live Firestore/Storage rules are edited in the Firebase console** (MEMORY: "console-managed Firestore rules before prod"). This plan gives the exact rule text and where to paste it, and commits a **reference copy** to the repo so the intended rules are version-controlled.
- `apps/loans/firebase.json` maps `database` → `database.rules.json` and `storage` → `storage.rules`, `firestore.indexes` → `firestore.indexes.json`.
- RTDB rules: `database.rules.json` (dev-stg, with `dev`/`stg` sub-trees) deploy via `firebase deploy --only database`; `database.rules.prod.json` deploys **manually** (`firebase database:rules:set database.rules.prod.json --project loooans-prod`).
- Indexes: `scripts/deploy-indexes.sh` fetches live indexes and filters by prefix; collection ids are env-prefixed. First-query **console auto-link** is the low-friction way to create each env's index.

---

### Task 1: Firestore security rules (console-managed) + repo reference

The rule text below is a **template** — Firestore rules can't parameterize a collection prefix, so paste it with `<PREFIX>` replaced per environment: **`dev_` and `stg_`** (two copies, in the `loooans-dev-stg` project's ruleset) and **empty** (in `loooans-prod`).

**Files:**
- Create: `apps/loans/firestore.rules.chat.reference` (version-controlled reference; NOT auto-deployed)

- [ ] **Step 1: Write the reference rule file**

Create `apps/loans/firestore.rules.chat.reference` with the template (repeat the two `match` blocks per active prefix inside the real console ruleset):
```
// ===== CHAT RULES (paste into each project's ruleset) =====
// Substitute <PREFIX> = "dev_", "stg_" (loooans-dev-stg) or "" (loooans-prod).
// Repeat the two match blocks once per active prefix in that project.

function chatSignedIn() { return request.auth != null; }

function chatUserCompanyId() {
  return get(/databases/$(database)/documents/<PREFIX>users/$(request.auth.uid)).data.company_id;
}

// membership against a room's member_ids (userId, or my company's id if I'm staff)
function chatIsMember(memberIds) {
  return chatSignedIn() && (
    request.auth.uid in memberIds ||
    chatUserCompanyId() in memberIds
  );
}

match /<PREFIX>chat_rooms/{roomId} {
  allow read: if chatIsMember(resource.data.member_ids);

  allow create: if chatSignedIn()
    && request.resource.data.created_by == request.auth.uid
    && chatIsMember(request.resource.data.member_ids);

  // participants may only touch read/handled watermarks (+ updated_at);
  // last_seq / last_message are written by the trigger (Admin SDK bypasses rules).
  allow update: if chatIsMember(resource.data.member_ids)
    && request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['reads', 'team_reads', 'updated_at']);

  match /messages/{messageId} {
    allow read: if chatIsMember(
      get(/databases/$(database)/documents/<PREFIX>chat_rooms/$(roomId)).data.member_ids
    );

    allow create: if chatIsMember(
        get(/databases/$(database)/documents/<PREFIX>chat_rooms/$(roomId)).data.member_ids
      )
      && request.resource.data.sender_id == request.auth.uid
      && (request.resource.data.sender_participant_id == request.auth.uid
          || request.resource.data.sender_participant_id == chatUserCompanyId())
      && !('seq' in request.resource.data);   // seq is trigger-only

    // edit/delete only your own message, only these fields
    allow update: if resource.data.sender_id == request.auth.uid
      && request.resource.data.diff(resource.data).affectedKeys()
          .hasOnly(['text', 'edited_at', 'deleted_at', 'updated_at']);
  }
}
```

> **Known v1 limitations (documented, harden later):** the room `update` rule allows any participant to write the `reads`/`team_reads` maps — it does not (and Firestore rules cannot cheaply) enforce that a client only mutates *its own* sub-entry. Risk is low (watermarks are monotonic-ish and non-sensitive). The message `create` rule blocks a client-set `seq` but does not deep-validate `attachments`.

- [ ] **Step 2: Apply in `loooans-dev-stg`**

In the Firebase console → Firestore → Rules for **loooans-dev-stg**, inside `match /databases/{database}/documents { … }`, paste the chat block **twice** — once with `<PREFIX>` = `dev_`, once with `<PREFIX>` = `stg_`. Publish.

- [ ] **Step 3: Apply in `loooans-prod`**

Same, once, with `<PREFIX>` = `` (empty). Publish. **Do this before the prod functions deploy.**

- [ ] **Step 4: Manual verification (console Rules Playground)**

For each project, in the Rules Playground: simulate an authenticated `get` on `<prefix>chat_rooms/{someRoomId}` as a member uid (allow) and a non-member uid (deny); simulate a message `create` with a matching `sender_id` (allow) and a mismatched one (deny). Record results.

- [ ] **Step 5: Commit the reference**

```bash
git add apps/loans/firestore.rules.chat.reference
git commit -m "docs(chat): version-controlled Firestore chat rules reference"
```

---

### Task 2: Cloud Storage rules (console-managed) + repo reference

**Files:**
- Create: `apps/loans/storage.rules.chat.reference`

- [ ] **Step 1: Write the reference**

Chat attachments upload to `chat/{roomId}/{msgId}/{fileName}` (Plan 3b). v1 gates on authentication (paths embed unguessable room+message ids). Create `apps/loans/storage.rules.chat.reference`:
```
// paste inside match /b/{bucket}/o { … } in each project's Storage ruleset
match /chat/{roomId}/{messageId}/{fileName} {
  allow read, write: if request.auth != null
    && request.resource == null || request.resource.size < 20 * 1024 * 1024; // 20MB cap on writes
}
```
> **v1 decision (spec §9 open item resolved):** authenticated-user gate + a 20 MB size cap, *not* a per-room `firestore.get()` participant check. Reason: dev and staging **share one bucket** (`loooans-dev-stg`) but use different Firestore prefixes (`dev_chat_rooms` vs `stg_chat_rooms`), so a single Storage ruleset can't unambiguously resolve which room doc to `get()` from the path. The unguessable path ids make the authed gate acceptable for v1. **Hardening follow-up (log it):** encode env in the path (`chat/{env}/{roomId}/…`) — a Plan 3b change — then gate with `firestore.get(/databases/(default)/documents/$(env)_chat_rooms/$(roomId)).data.member_ids`.

- [ ] **Step 2: Apply in both projects**

Paste the block into the Storage → Rules ruleset for **loooans-dev-stg** and **loooans-prod** (inside `match /b/{bucket}/o { … }`), above/around the existing rules. Publish each.

- [ ] **Step 3: Commit the reference**

```bash
git add apps/loans/storage.rules.chat.reference
git commit -m "docs(chat): version-controlled Storage chat rules reference"
```

---

### Task 3: RTDB typing rules (committed + deployed)

`TypingService` writes `<prefix>typing/{roomId}/{userId}` (prefix = `dev/`, `stg/`, or none). These files ARE the deployment source.

**Files:**
- Modify: `apps/loans/database.rules.json` (dev-stg)
- Modify: `apps/loans/database.rules.prod.json` (prod)

- [ ] **Step 1: Add typing rules to `database.rules.json`**

Add a `typing` node under **both** `dev` and `stg` (mirroring the existing `dev`/`stg` sub-trees). Inside `"dev": { … }`:
```json
      "typing": {
        "$roomId": {
          ".read": "auth != null",
          "$userId": {
            ".write": "auth != null && auth.uid == $userId"
          }
        }
      }
```
Add the identical block inside `"stg": { … }`.

- [ ] **Step 2: Add typing rules to `database.rules.prod.json`**

At the top level of `"rules": { … }` (sibling of `companies`):
```json
    "typing": {
      "$roomId": {
        ".read": "auth != null",
        "$userId": {
          ".write": "auth != null && auth.uid == $userId"
        }
      }
    }
```

- [ ] **Step 3: Validate JSON**

Run: `cd apps/loans && jq . database.rules.json > /dev/null && jq . database.rules.prod.json > /dev/null && echo OK`
Expected: `OK` (no parse errors).

- [ ] **Step 4: Deploy dev-stg**

Run: `cd apps/loans && firebase deploy --only database --project loooans-dev-stg`
Expected: `Deploy complete!`.

- [ ] **Step 5: Deploy prod (manual, per repo convention)**

Run: `cd apps/loans && firebase database:rules:set database.rules.prod.json --project loooans-prod`
Expected: rules updated. (Do before prod launch.)

- [ ] **Step 6: Commit**

```bash
git add apps/loans/database.rules.json apps/loans/database.rules.prod.json
git commit -m "feat(chat): RTDB typing rules (dev/stg + prod)"
```

---

### Task 4: Inbox composite index

Inbox query = `<prefix>chat_rooms` where `member_ids array-contains-any […]` + `deleted_at == null` + `orderBy updated_at desc` → needs a composite index per env, shaped like the existing `loans` `co_maker_user_ids` CONTAINS index.

- [ ] **Step 1: Primary path — create via the console auto-link (per env)**

Run the app pointed at dev (`fvm flutter run --flavor development …`), open **Messages**. The inbox query fails with a `FAILED_PRECONDITION` error whose log contains a **"create index" URL**. Open it → it pre-fills a `dev_chat_rooms` index with `member_ids (Arrays)`, `deleted_at (Asc)`, `updated_at (Desc)` → Create. Repeat for staging (`stg_chat_rooms`) and, before prod launch, production (`chat_rooms`).

- [ ] **Step 2: Reference entry for the committed index file**

For the prod deploy path (`scripts/deploy-indexes.sh prod`), the `chat_rooms` (unprefixed) index must exist in `firestore.indexes.json`. Add to the `indexes` array:
```json
    {
      "collectionGroup": "chat_rooms",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "member_ids", "arrayConfig": "CONTAINS" },
        { "fieldPath": "deleted_at", "order": "ASCENDING" },
        { "fieldPath": "updated_at", "order": "DESCENDING" }
      ]
    }
```
> Note: `deploy-indexes.sh` *fetches live indexes then filters by prefix* and overwrites `firestore.indexes.json`, so this committed entry is a reference/snapshot for prod. The console auto-link in Step 1 is the reliable creation path per environment; keep both in sync.

- [ ] **Step 3: Validate + commit**

Run: `cd apps/loans && jq . firestore.indexes.json > /dev/null && echo OK`
```bash
git add apps/loans/firestore.indexes.json
git commit -m "chore(chat): add chat_rooms inbox composite index reference"
```

---

### Task 5: `messageWritten` deploy + IAM

The trigger is registered (Plan 2, Task 6) and deploys via the existing functions CI on `develop`. Prod needs the keyless-SA IAM grants (per MEMORY `gotcha_keyless_sa_iam`).

- [ ] **Step 1: Confirm dev/staging deploy picks up the new trigger**

After Plan 2 merges to `develop`, confirm the `loans-functions-development` workflow deployed `messageWritten_development` (GitHub Actions logs, or `gcloud functions list --project loooans-dev-stg --regions asia-east1 | grep messageWritten`). A Firestore trigger needs the firebase-adminsdk SA to have `roles/eventarc.eventReceiver` (already granted on dev-stg per prior functions work — verify).

- [ ] **Step 2: Verify prod IAM before the `master` deploy**

On `loooans-prod`, the firebase-adminsdk SA needs (per the keyless-SA gotcha): `roles/eventarc.eventReceiver` and `roles/run.invoker` for the Eventarc trigger. Verify/grant:
```bash
SA=$(gcloud iam service-accounts list --project=loooans-prod --filter="email ~ ^firebase-adminsdk-" --format="value(email)" --limit=1)
gcloud projects add-iam-policy-binding loooans-prod --member="serviceAccount:$SA" --role="roles/eventarc.eventReceiver"
```
(messageWritten uses env-vars only — no Secret Manager grant needed, unlike the email functions.)

- [ ] **Step 3: Note in the deploy checklist**

No code change here — this is an ops verification. Record the confirmed grants + the deployed function name in `functions/loans/MEMORY.md`.

---

### Task 6: End-to-end verification + MEMORY

- [ ] **Step 1: Manual smoke (dev)**

With rules + index + trigger live on dev: borrower opens a lender product → "Message lender" → sends text → the message appears; a second account (company staff) receives it, sees unread, opens the room (unread clears), replies → borrower sees "delivered/read" ticks; typing shows; edit/delete works; an image attachment uploads and renders. Confirm no permission-denied errors in the console.

- [ ] **Step 2: Update MEMORY**

Append to `functions/loans/MEMORY.md` and `apps/loans/MEMORY.md`: chat feature shipped (link the spec + plans), the console-managed rules applied per project, the RTDB typing rules deployed, the inbox index created per env, and the two logged hardening follow-ups (Storage participant-check w/ env-in-path; background delivered-ack w/ persisted uid).

```bash
git add functions/loans/MEMORY.md apps/loans/MEMORY.md
git commit -m "docs(chat): record rules/index/deploy completion + follow-ups"
```

---

### Task 7 (OPTIONAL): Firestore rules emulator tests

If you want automated rule coverage (the repo has none today), add a minimal Node harness. This is net-new infra — only do it if the team wants rules under CI.

- [ ] **Step 1: Scaffold** a `apps/loans/firestore-rules-test/` Node package with `@firebase/rules-unit-testing` + `jest`, an `firestore.rules` assembled from the reference (with a fixed prefix, e.g. `dev_`), and `firebase.json` emulator config (Firestore port 8081 already reserved).
- [ ] **Step 2: Write tests** asserting: non-member read denied; member read allowed; message create with wrong `sender_id` denied; client `seq` set denied; edit of another user's message denied; room update touching `last_seq` denied.
- [ ] **Step 3: Run** `firebase emulators:exec --only firestore 'npm test'` and wire it into CI.
- [ ] **Step 4: Commit.**

---

## Self-Review (completed by plan author)

**Spec coverage (§9):**
- Firestore read/create/update rules for rooms + messages (participant/company-staff membership, sender checks, trigger-only fields, edit/delete) → Task 1. ✅
- Storage rule for `chat/…` (env-prefix ambiguity resolved to authed-gate v1 + hardening follow-up) → Task 2. ✅
- RTDB `typing/…` rules, dev/stg + prod, committed + deployed → Task 3. ✅
- Inbox composite index per env → Task 4. ✅
- `messageWritten` deploy + prod IAM (Eventarc) → Task 5. ✅

**Deviations (called out):**
- **Not TDD** — repo has no rules test harness and rules are console-managed; Task 7 offers an optional emulator suite. Verification is the console Rules Playground + a manual dev smoke.
- **v1 rule limitations documented**: room `update` can't cheaply enforce "own reads sub-entry only"; Storage uses an authed gate (unguessable paths) rather than a Firestore participant check. Both have logged hardening follow-ups.
- Firestore/Storage rule text is committed as `*.reference` files (version control) but applied by hand in the console, matching the repo's established practice — it is NOT wired into `firebase.json` (which still points at the stub files the project deploys… i.e. it does not auto-deploy Firestore/Storage rules at all).

**Placeholder scan:** none — exact rule text, exact JSON, exact commands. `<PREFIX>` is an explicit, instructed substitution, not a placeholder.

**Consistency:** field/paths (`member_ids`, `reads`, `team_reads`, `last_seq`, `sender_id`, `sender_participant_id`, `seq`, `text`/`edited_at`/`deleted_at`, `chat/{roomId}/{msgId}`, `typing/{roomId}/{userId}`) match the spec and Plans 1–3b exactly.
