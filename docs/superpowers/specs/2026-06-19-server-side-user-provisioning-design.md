# Server-Side User Provisioning — Design

**Date:** 2026-06-19
**Status:** Approved (brainstorm complete; ready for implementation planning)
**Supersedes:** PR #69 (`fix/add-user-replaces-session`) and its client-side `createUserCredentialIsolated` workaround.
**Related issue:** `anatechopc/finstack` #2 — "When creating a user, the created user will replace the currently logged in user."

---

## 1. Goal

Replace the client-side, session-replacing user-creation paths with a **server-owned, atomic** path. When a company admin adds a staff member or a borrower, the **Go backend mints the Firebase Auth account (uid), writes `users/{uid}` + the address doc atomically, and emails a branded "set your password" invite**. Every admin-added user — staff and borrower — gets a real Auth account and can log in. The admin's own session is never touched.

This realizes the originally-intended design (Admin SDK creates the auth account first, its uid becomes the `users/{uid}` document id) that was previously abandoned as too time-consuming, and in doing so fixes issue #2 properly rather than working around it.

## 2. Background & motivation

A trace of the current code found **four overlapping user-creation paths** that disagree on fundamentals:

1. `RegistrationBloc._handleSubmitUserRegistrationEvent` → client-side `createUserCredential` (`signInAnonymously` + `linkWithCredential` on the **primary** `FirebaseAuth`), which **replaces the current session** — the root cause of issue #2.
2. `RegistrationBloc._handleSubmitManagedUserRegistrationEvent` → `User.createManagedCustomer` (`id = "no-id"`, **no** Auth account, Firestore-only, cannot log in).
3. `UserBloc.addUser` / `_handleAddUserEvent` → duplicate of (2); **zero callers** (dead code).
4. `UserRepository.createUserAccess` → `POST /users/add` → Go `add_user.go` (Admin SDK) — the "proper" server path, but **commented out**, **never called**, **no hosting rewrite**, and the handler has no auth check / writes no Firestore doc / emails a plaintext password.

PR #69 added `createUserCredentialIsolated` (creates the new user on a throwaway secondary Firebase app so the admin's session survives). That is a valid stopgap but leaves the architecture tangled and still mints other people's accounts client-side. This design retires it.

### Key facts grounding the design (verified in code)

- `UserFirestoreService.add` writes to `users/{data.id}` when `id != NO_ID` (`packages/core/user_repository/lib/src/data/database/user_firestore_service.dart:23`). So minting the uid first and using it as the doc id is exactly what the existing write path supports.
- Addresses live in a **top-level `address` collection** with auto-ids, linked to their owner via `data_id` (`packages/core/address_repository/lib/src/data/database/address_firestore_service.dart:18,53`). Employment details are embedded in the user doc.
- HTTP functions are reachable only when registered in `loooans_cloud_functions.go`, deployed by `.github/scripts/deploy_functions.sh` (gen2 → Cloud Run service `name-<env>`, lowercased/hyphenated), **and** routed by a `apps/loans/firebase.json` hosting rewrite. There is currently **no rewrite for `/api/users/add`** (only `sendEmail`, `request/otp`, `verify/otp`) — so the old path fell through to `index.html`.
- The client base URL is `https://<env.>loooans.com/api` (`packages/core/loooans_helpers/lib/src/string_helpers.dart:47`); rewrites live under `/api/...`.
- A `userCreated` Firestore trigger already fires on `users/{uid}` creation (`deploy_functions.sh:99`). Its behavior for server-created users must be verified during implementation.
- Login is email/password (`AuthenticationRepository.authenticate`); the router gate requires **both** `emailVerified` and `mobileVerified`, else redirects to `/verify` (`apps/loans/lib/app/routing/router.dart:77-87`). Invited users naturally flow through this existing gate + OTP on first sign-in — no special handling needed.
- `UserRole` values: `appAdmin`, `customer`, `admin`, `loanOfficer`, `teller`, `reviewModerator`; `companyManagedRoles = [admin, loanOfficer, teller, reviewModerator]` (`packages/core/user_repository/lib/src/model/user_role.dart`).
- `CompanyManagementType`: `app`, `selfManaged`. `allowAddClients == (managementType == selfManaged)` (`apps/loans/lib/services/authentication_service.dart:93`).

## 3. Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Who can add whom | App-managed companies add **team members only**; self-managed companies add **team members + borrowers**. Enforced server-side. |
| D2 | Auth for added users | **Every** admin-added user (staff + borrower) gets a real Firebase Auth account at `users/{uid}` (id == uid) and can log in. |
| D3 | Server/client split | **Thick + atomic**: the server owns the auth mint + Firestore write (authorized, atomic via compensating delete). The **client owns serialization** (assembles entity JSON, uploads photos) so we do *not* re-model `User`/address/employment as Go structs. Server strongly-types only logic-critical fields and writes the rest through as a map. |
| D4 | Invite mechanism | **Set-password invite link**: server creates the account with a throwaway random password, generates a Firebase password-reset link (Admin SDK), and emails a branded "set your password" message via MS Graph. No plaintext passwords. No new Flutter screen (Firebase hosts the set-password page). |
| D5 | Re-invite / forgot password | Build **both** admin "Resend invite" (users list) and login "Forgot password", backed by one unauthenticated `sendPasswordSetupLink` endpoint (always 200, no account-existence leak). |
| D6 | Add UX | **Two distinct entries** — "Add team member" (both company types; role picker over staff roles) and "Add borrower" (self-managed only; role fixed = `customer`) — sharing one form + handler. |
| D7 | Borrower email | **Required** for admin-added borrowers (needed for invite + the email-verification gate). Previously optional for managed customers. |
| D8 | Self-registration | **Unchanged.** A person signing themselves up keeps client-side `createUserCredential` (taking over the session is correct there). Only admin-add paths move server-side. |
| D9 | PR #69 | **Superseded** by the A/B/C series (see §10); `createUserCredentialIsolated` is removed. |

## 4. Who-can-add-what matrix (server-enforced)

| Caller role | Caller company type | May add | Allowed role(s) for the new user | Result |
|---|---|---|---|---|
| `admin` / `appAdmin` | `app` | Team members only | `admin`, `loanOfficer`, `teller`, `reviewModerator` | Auth + login + invite |
| `admin` / `appAdmin` | `selfManaged` | Team members + borrowers | staff roles **or** `customer` | Auth + login + invite |
| any other role | any | nothing | — | 403 |

- The new user's `company_id` is **server-set to the caller's company** (clients cannot add to another company).
- The new user's `user_role` is **server-authoritative** from the request's `role`, after validation (clients cannot escalate).
- `customer` is allowed only when the caller's company is `selfManaged`.
- `appAdmin` may not be created via this endpoint.

## 5. Architecture & data flow

```
ADMIN ADDS USER/BORROWER
Flutter (admin, logged in)
  1. upload photos -> Firebase Storage (client, as today; URLs into the entity)
  2. assemble user + address ENTITY JSON (client reuses toEntity().toJson():
     snake_case keys, int64-millis dates)
        |
        v
POST /api/users/add   (Bearer admin idToken)
  { role, user:{...}, address:{...} }
        |
        v
  Go Cloud Function "addUser" (Admin SDK)
    a. VerifyIDToken -> callerUid
    b. read users/{callerUid} + company doc -> authorize (role x company type)
    c. server-set user.company_id = caller.companyId; user.user_role = role
    d. Auth.CreateUser(email, randomPassword, displayName, emailVerified=false) -> uid
         on "email exists" -> 409
    e. user.id = uid; address.data_id = uid
       Store.WriteUserAndAddress(uid, user, address)   // single Firestore batch
         on failure -> Auth.DeleteUser(uid) (compensating; no orphan) -> 500
    f. Invite.Send(email, displayName)   // BEST-EFFORT; failure -> log, still 200
    g. return { uid, inviteSent }
        |
        v
  Flutter: success -> admin sees the new user in the list
  Invited user: email -> sets password (Firebase-hosted page) -> logs in ->
                existing email+mobile OTP verify gate -> done

RE-INVITE / FORGOT PASSWORD
  admin "Resend invite"  --\
  login "Forgot password" --+--> POST /api/users/password/setup-link { email }
                               -> Admin SDK PasswordResetLink + MS Graph email
                               -> ALWAYS 200 (no account-existence leak)
```

## 6. Backend (Go Cloud Functions)

Both endpoints follow the established **adapter + core** pattern (like `VerifyOtp`/`RequestOtp`/`reviewUpdated`): a thin HTTP adapter does CORS + token verification + JSON unmarshalling, then delegates to a pure `…Core(ctx, …, deps)` whose deps are interfaces backed by fakes in `functions/loans/test/fakes/`.

### 6a. `POST /api/users/add` — `AddUser` (rewrite of the commented-out `add_user.go`)

Fixes the three defects in the current stub: no auth check, plaintext password emailed, no Firestore doc written.

**Request** (Bearer = admin idToken):
```jsonc
{
  "role": "teller",                 // requested UserRole
  "user":    { /* user entity JSON, client-serialized */ },
  "address": { /* address entity JSON, optional */ }
}
```

**`HandleAddUserCore(ctx, callerUid, req, deps)`** — pure logic:
1. `caller := deps.Users.Get(callerUid)` — reject unless `caller.role ∈ {admin, appAdmin}` → 403.
2. `company := deps.Companies.Get(caller.companyId)` — read `managementType`.
3. Authorize requested role: `customer` requires `selfManaged` (else 403); staff roles allowed for both types; `appAdmin`/other rejected (403).
4. Server-set authoritative fields: `user.company_id = caller.companyId`, `user.user_role = req.role`.
5. `uid := deps.Auth.CreateUser(email, randomPassword, displayName, emailVerified=false)`; on "email exists" → 409.
6. `user.id = uid`; `address.data_id = uid`; `deps.Store.WriteUserAndAddress(uid, user, address)` (single batch). On error → `deps.Auth.DeleteUser(uid)` (compensating) → 500.
7. `inviteSent := deps.Invite.Send(email, displayName)` — best-effort; on error log only (account exists; admin can resend).
8. Return `{ uid, inviteSent }`.

**Deps (interfaces → fakes):** `Users.Get(uid)→(role,companyId)`, `Companies.Get(id)→managementType`, `Auth.CreateUser/DeleteUser`, `Store.WriteUserAndAddress(uid, userMap, addressMap)` (passthrough maps; preserves int64-millis dates), `Invite.Send(email, displayName)`.

Properties: authorization fully server-side; `company_id`/`user_role` server-authoritative; Auth+Firestore atomic via compensating delete; uid **is** the doc id.

### 6b. `POST /api/users/password/setup-link` — `SendPasswordSetupLink` (new)

Backs both admin "Resend invite" and login "Forgot password".
- **Request:** `{ "email": "..." }`. **No idToken** (used pre-login).
- **Core:** `HandleSendPasswordSetupLinkCore(ctx, email, deps)` → `deps.Invite.Send(email, displayName?)`; if email maps to no Auth user → no-op; **always returns 200** (never reveal whether the account exists).
- Needs **basic rate-limiting** (per-email/IP) to prevent email-bombing.

### 6c. Shared invite helper — `Invite.Send(email, displayName)`

```
link := deps.Auth.PasswordResetLink(email)        // Admin SDK; errors if no such user
html := branded "set your password" template (link + note: verify email & mobile on first sign-in)
deps.Email.Send(subject, html, [email])           // existing MS Graph utils.SendEmail
```
No plaintext passwords anywhere. Two short templates: a **welcome/invite** copy (used by `AddUser`) and a **reset** copy (used by `sendPasswordSetupLink`) — same mechanism, different wording.

### 6d. Wiring & deploy

- **`loooans_cloud_functions.go`:** `functions.HTTP("addUser", users.AddUser)` (uncomment/replace) + `functions.HTTP("sendPasswordSetupLink", users.SendPasswordSetupLink)`.
- **`.github/scripts/deploy_functions.sh`:** two HTTP deploys mirroring `sendEmail` (they email → `--set-secrets "$MS_GRAPH_SECRETS"` + `--set-env-vars "$MS_GRAPH_ENV_VARS"`), `--trigger-http --allow-unauthenticated --gen2 --service-account="$serviceAccount"`, entry points `addUser` / `sendPasswordSetupLink`. Bump the "All N functions" counts. Gen2 service ids become `adduser-<env>` / `sendpasswordsetuplink-<env>`.
- **`apps/loans/firebase.json`:** add to each hosting target (`develop`/`staging`/`production`), **above** the `**` catch-all:
  ```jsonc
  { "source": "/api/users/add",
    "run": { "serviceId": "adduser-<env>", "region": "asia-east1" } },
  { "source": "/api/users/password/setup-link",
    "run": { "serviceId": "sendpasswordsetuplink-<env>", "region": "asia-east1" } }
  ```
- **IAM:** the two functions need `secretmanager.secretAccessor` on `ms-graph-client-secret` (same as `requestOtp`/`sendEmail`). Already granted on dev; prod still pending (see memory `gotcha_keyless_sa_iam.md`).

## 7. Frontend (Flutter)

### 7a. Repository / network layer (`packages/core/user_repository`)
- `UserNetworkService.createUser({role, userJson, addressJson, idToken}) → {uid, inviteSent}` — `POST $LOOOANS_BASE_API_URL/users/add`, `Bearer idToken`, body `{role, user, address}` (rework of the unused `createUserAccess`).
- `UserNetworkService.sendPasswordSetupLink({email}) → void` — `POST $LOOOANS_BASE_API_URL/users/password/setup-link`, no auth.
- `UserRepository.createUser(...)` and `UserRepository.sendPasswordSetupLink(email)` wrap them.

### 7b. `RegistrationBloc` — collapse the admin paths into one server-backed handler
One handler `_handleSubmitInvitedUser(role, fields)`: emit loading → upload photos → build `User.createInvited(role, ...)` (uid-less) + optional address → `userRepository.createUser(role, user.toEntity().toJson(), address?.toEntity().toJson(), idToken)` → emit success. **No client-side Auth minting for admin-added users.** Self-registration (`_handleSubmitUserRegistrationEvent` with `createUserCredential`) and provider registration are untouched.

### 7c. The add form — role selection + email required
`RegisterScreenFormUsersWidget` stops branching on `isUserCompanyManaged` (managed-vs-auth) and carries an **add mode**:

| Mode | Entry | Role | Company types | Form specifics |
|---|---|---|---|---|
| Team member | "Add team member" (users screen) | picker: `admin`, `loanOfficer`, `teller`, `reviewModerator` | app **and** selfManaged | email **required**; selfie/ID optional |
| Borrower | existing "Add borrower" buttons | fixed `customer` | selfManaged **only** | email **required**; selfie/ID optional |

A single new factory `User.createInvited({required UserRole role, ...})` (uid-less, role-parameterized, email required, photos optional) replaces `createManagedCustomer` for both modes. Borrower entries stay gated on `allowAddClients`; the team-member entry is available to both company types (gated on caller being `admin`). The server re-checks both.

### 7d. Admin "Resend invite"
Per-row action in the users / borrowers list overflow menu → `userRepository.sendPasswordSetupLink(email)` → snackbar "Invite re-sent." Always available (no fragile onboarding-state tracking for v1). Implemented as a `resendInvite(email)` event on the users bloc.

### 7e. Login "Forgot password"
Login screen gains a "Forgot password?" link → minimal email prompt → `userRepository.sendPasswordSetupLink(email)` → neutral confirmation ("If an account exists, we've emailed a link"). Backed by an `AuthenticationBloc` event. The app's first real password-reset surface, usable by everyone.

### 7f. Dead code retired
- `UserBloc.addUser` / `_handleAddUserEvent` (zero callers) — removed.
- `User.createManagedCustomer` — removed (superseded by `createInvited` + server auth).
- `AuthenticationRepository.createUserCredentialIsolated` — removed (superseded by the server path).
- The commented `AddUserScreen` route (`route_utils.dart:66`) — removed if confirmed unreachable.

## 8. Security / rules
- **No new Firestore rules needed.** The server writes `users/{uid}` + `address/…` via the Admin SDK, which bypasses security rules; the client no longer writes these docs directly, and the resend/forgot endpoints don't touch Firestore from the client.
- `sendPasswordSetupLink` is intentionally unauthenticated → needs basic rate-limiting; always 200 (no leak).
- ⚠️ Verify the existing `userCreated` trigger behaves correctly for server-created users (no duplicate notifications / unexpected side effects).

## 9. Testing (per the project's tests-on-every-change rule)
- **Go (`CGO_ENABLED=0 go test ./...`):** core tests with fakes — the full authz matrix (role × company type → allow/403), 409 on duplicate email, compensating-delete on write failure, invite best-effort (email fails → still 200 + uid), and `sendPasswordSetupLink` no-leak.
- **Flutter:** `RegistrationBloc` tests for the server-backed create (mocked repo), widget tests for the role picker / two entries / email-required validation, and the resend-invite + forgot-password triggers.

## 10. PR sequencing (three PRs, deployed in order)

```
PR A — Backend (Go)          deploy functions  creates adduser-/sendpasswordsetuplink- services
       addUser + sendPasswordSetupLink, types, email templates, fakes, tests,
       registration in loooans_cloud_functions.go, deploy_functions.sh
                                  |
                                  v
PR B — Hosting rewrites      deploy hosting    routes /api/users/add + /password/setup-link
       firebase.json (3 targets)               MUST follow PR A (Cloud Run services must exist first)
                                  |
                                  v
PR C — Frontend (Flutter)    build/test web    hits the now-live backend end-to-end
       network+repo, RegistrationBloc rework, two-entry forms + role picker,
       email-required, resend invite, forgot password, retire dead code, tests
```

One spec (this document) covers all three; the implementation plan is phased A → B → C, each phase ending in its own PR. PR #69 is closed/superseded referencing the new series; its `createUserCredentialIsolated` change is removed.

## 11. Out of scope (separate follow-ups)
- Migrating existing `no-id` managed customers to real Auth accounts (their doc ids are random, not uids; can't rename a doc id).
- Self-registration changes (stays client-side).
- An `invitePending`/onboarding-state badge in the users list.
- Production IAM grants on `loooans-prod` (Eventarc + Secret Manager) — needed before the `master` deploy; tracked separately.

## 12. Open risks / notes
- `userCreated` trigger side effects for server-created users (verify in PR A).
- Rate-limiting design for the unauthenticated `sendPasswordSetupLink`.
- Firebase password-reset link expiry (~1h): mitigated entirely by the resend/forgot endpoint — the account is permanent; only the one-time code expires.
- Bonus (not relied upon): completing a password reset on a link sent to the user's email generally marks that email verified, possibly clearing the email half of the verify gate automatically.
