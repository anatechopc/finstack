# Evidence: invariants and weak points, with verify commands

Every excerpt below was read from source on 2026-07-07 (branch
`feature/chat-messaging`). Line numbers drift — each entry includes a grep that
re-locates the anchor by symbol, which is what you should trust.

All commands run from the repo root `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`
(or any checkout root).

---

## I1 — Dates as int64 millis

Flutter converters (`packages/core/loooans_helpers/lib/src/data_helpers/constants.dart`):

```dart
num? handleDateTimeToJson(DateTime? dateTime) {
  return dateTime?.millisecondsSinceEpoch;
}
```

The read side (`_parseDateTime` in the same file) accepts a `num` OR duck-types a
Firestore `Timestamp` via `.toDate()` — the comment in source explains this exists
because pre-fix Go writers stored `time.Time` and those docs are permanently
contaminated. Tolerance on read; never write Timestamps.

Go writers (samples):

```
triggers/notification_helpers.go:36:  nowMillis := time.Now().UTC().UnixMilli()
triggers/message_written_core.go:66:  now := deps.Now().UTC().UnixMilli()
triggers/loan_changes.go:438:         "created_at":   timeNow.UnixMilli(),
api/users/set_password.go:146:        nowMillis := time.Now().UTC().UnixMilli()
```

Verify:

```bash
grep -n "handleDateTimeToJson\|toDate()" packages/core/loooans_helpers/lib/src/data_helpers/constants.dart
grep -rn "UnixMilli" functions/loans --include="*.go" | grep -v _test | grep -v worktrees
```

History: finstack PR #47 (client tolerance), #48 (`verify_otp.go` producer),
#49 (`notification_helpers.go` producer), #81 (`utils.ToInt64` hardening) —
"Chain B" in `finstack-failure-archaeology`.

## I2 — The prefix triple (+ the RTDB difference)

Site 1 — Flutter (`packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart`):

```dart
/// env-based collection prefix: `dev_`, `stg_`, or '' (production).
String get collectionPrefix {
  if (const String.fromEnvironment('ENVIRONMENT') == Environments.staging.name) {
    return 'stg_';
  } else if (const String.fromEnvironment('ENVIRONMENT') == Environments.production.name) {
    return '';
  }
  return 'dev_';   // <-- default when ENVIRONMENT unset: DEV (fails safe)
}
```

Site 2 — Go (`functions/loans/utils/environment_utils.go`):

```go
func GetCollectionPrefix() string {
    env := os.Getenv("ENVIRONMENT")
    collectionPrefix := ""            // <-- default when unset: PROD-shaped ""
    switch env {
    case "development": collectionPrefix = "dev_"
    case "staging":     collectionPrefix = "stg_"
    }
    return collectionPrefix
}
```

The Go default is only safe because `start()` in `loooans_cloud_functions.go`
does `log.Fatal("Runtime environment not defined")` when `ENVIRONMENT` is empty
(line ~62). If you ever bypass `start()`, an unset env silently becomes prod paths.

Site 3 — Deploy script (`.github/scripts/deploy_functions.sh`, lines 39–47 compute
`collectionPrefix`; every trigger deploy bakes it in), e.g.:

```
--trigger-event-filters-path-pattern=document="${collectionPrefix}loans/{uid}"
```

RTDB difference: report paths use bare `dev`/`stg`/`""` roots —
`getPathEnv()` (local duplicate, `triggers/loan_changes.go`, also used by
`loan_schedule_changes.go`) and `utils.GetMinifiedEnv()`. RTDB rules:
`apps/loans/database.rules.json` wraps `dev`/`stg` nodes;
`database.rules.prod.json` is unprefixed (and nothing in `firebase.json`
deploys the prod file — see `finstack-run-deploy-operate`).

Verify:

```bash
grep -n "dev_\|stg_" \
  packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart \
  functions/loans/utils/environment_utils.go \
  .github/scripts/deploy_functions.sh
grep -n "func getPathEnv" functions/loans/triggers/loan_changes.go
```

Known deliberate exception: `job/subscription_job.go:107,111` hardcodes the
prefixes locally (the job is disabled — commented out of `init()`).

## I3 — OTP reason read server-side

`functions/loans/api/users/verify_otp.go` (comment at ~L60):

```
// performs the post-verification side-effect dictated by the entry's reason.
// Reasons are read from the persisted entry — never from the request — so a
...
reason, _ := otpData["reason"].(string)
switch reason {
case reasonPayment: ...
case reasonMobileVerification: ...
case reasonEmailVerification: ...
```

Verify: `grep -n "never from the request\|otpData\[\"reason\"\]" functions/loans/api/users/verify_otp.go`

## I4 / I5 — NO_ID and doc self-ID

`packages/core/loooans_helpers/lib/src/data_helpers/constants.dart:3`:
`const NO_ID = 'no-id';`

Canonical `add()` (`packages/loans/loan_repository/lib/src/data/database/loan_firestore_service.dart:19`):

```dart
Future<LoanEntity> add({required LoanEntity data}) async {
  final doc = root.doc();
  final updatedData = data..id = doc.id;
  await doc.set(updatedData.toJson());
  return updatedData;
}
```

Go dependence on the embedded id (`triggers/loan_changes.go:75-79`):

```go
if value, ok := data.GetValue().GetFields()["id"]; ok {
    loanId = value.GetStringValue()
} else {
    return errors.New(fmt.Sprintf("No id for loan: %s", ...))
}
```

Verify: `grep -rn "data..id = doc.id" packages | head` and
`grep -n '"id"' functions/loans/triggers/loan_changes.go | head -3`

## I6 — Denormalization cascades

- `triggers/user_changes.go` — header comment: "cascades a profile-name change to
  the denormalized user_full_name on the user's user_loan_views documents";
  the write is `{"user_full_name": newFullName}` against
  `{prefix}user_loan_views` filtered by user. Also clears the
  mobile-verification bit (`verificationBitMobileNumber = 2`) when
  `mobile_number` changes.
- `triggers/payment_created.go` — header comments (~L42-48): submission_id
  de-dup ("only the FIRST payment of that submission notifies") and loan
  resolution ("payment docs carry loan_schedule_id (not loan_id). The core uses
  fields[\"loan_id\"] when present (backward-compat) and otherwise resolves" via
  the schedule).

Verify:

```bash
grep -n "user_full_name" functions/loans/triggers/user_changes.go
grep -n "submission_id\|loan_schedule_id" functions/loans/triggers/payment_created.go | head
```

## I7 — Chat seq transaction

`triggers/message_written.go` (`AllocateSeq` dep wiring, ~L141):

```go
err := fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
    ...
    last, _ := utils.ToInt64(snap.Data()["last_seq"])
    ...
    if err := tx.Set(roomRef, map[string]any{"last_seq": next}, firestore.MergeAll); err != nil {
```

Direct push (bypasses notifications collection): `sendChatPush` (~L172) reads
`{prefix}users/{uid}/devices` tokens and `SendEachForMulticast`s. WHY: chat
design spec `docs/superpowers/specs/2026-07-01-chat-messaging-design.md`,
decision table row 13 ("Direct FCM data-push … No persistent notification-list
entries") and §"No persistent notification-list document (chat would spam it);
unread is the durable signal."

Verify: `grep -n "RunTransaction\|last_seq\|sendChatPush" functions/loans/triggers/message_written.go`

## Weak points — excerpts

### loan_changes.go non-transactional RMW (`applyToNodeValue`, ~L462)

```go
func applyToNodeValue(ctx context.Context, dbClient db.Client, pathToNodeValue string, applyValue float64) error {
    ref := dbClient.NewRef(pathToNodeValue)
    var value float64
    err := ref.Get(ctx, &value)          // READ
    ...
    setErr := ref.Set(ctx, value+applyValue)   // MODIFY-WRITE, no txn
```

Two concurrent trigger executions both Get the same value → one increment lost.
(The RTDB Go SDK has `ref.Transaction`; not used.) Also note the second error
path wraps the wrong variable (`err` instead of `setErr`).

### Swallowed errors

Every status branch does `dataErrors = applyToNodeValue(...)` repeatedly
(reassignment, not accumulation) — e.g. L108-120 for `approved`. Only the last
call's error survives to be returned.

### `completed` branch double-count + TODO

`additional_charges` is ADDED to `totalLoanAmount` at ~L190 and SUBTRACTED at
~L206 in the same branch (nets to zero — one of the two is a copy-paste error);
the branch is marked `// TODO(deibeeed) complete this for report` at ~L171.

### Prod collection bug: `pathEnv+"_loan_schedules"`

L141 (`bad_debt`) and L180 (`completed`):

```go
loanSchedules, collectionErr := firestoreClient.Collection(pathEnv+"_loan_schedules").Where("loan_id", "==", loanId)...
```

`getPathEnv()` returns `dev`/`stg`/`""` → dev/stg get `dev_loan_schedules` /
`stg_loan_schedules` (correct), production gets literal collection
`_loan_schedules` (leading underscore — no such collection). Code-verified;
runtime impact in prod is [inference]: the query returns empty, so
bad-debt/completed figures are computed from zero schedules. Fix belongs to
`finstack-loan-engine-and-reporting-campaign` (use `utils.GetCollectionPrefix()`).

### `%$w` format typos

L144 and L183: `fmt.Errorf("cannot get loan schedules for loanId %s: %$w", ...)` —
`%$w` is not a verb; prints literally, error not wrapped.

### go vet (run inside `functions/loans/triggers/`)

```
$ CGO_ENABLED=0 go vet ./...
./loan_changes.go:317:87: call of createLoanStatusNotifications copies lock value: ... DocumentEventData contains ... sync.Mutex
./loan_changes.go:334:7: createLoanStatusNotifications passes lock by value: ...
```

(Note the vet header prints `# com.looans.app/triggers` — the two-o module typo.)

### Non-atomic multi-payment writes (Flutter)

- `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` ~L1173
  and ~L1223: `// TODO(payments): atomic multi-schedule confirm — a failure
  partway through a "pay in full" submission leaves earlier schedules
  confirmed.` (and `...reverted.`), each above a per-payment `await` loop.
- `apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart` ~L69:
  `// TODO(payments): make the pay-in-full writes atomic (WriteBatch)` —
  mitigation today is counting successes and showing "contact support" on
  partial failure.

Verify: `grep -rn "TODO(payments)" apps/loans/lib/features`

### triggers/go.mod typo

```
$ head -1 functions/loans/triggers/go.mod
module com.looans.app/triggers        # two o's
$ grep -n "triggers" functions/loans/go.mod
73:replace com.loooans.app/triggers => ./triggers   # three o's — the replace wins
```

## DI reality snapshot (2026-07-07)

`apps/loans/lib/app/di/repository_providers.dart` — 20 providers: User,
Authentication, Storage, ProductView, Product, Loan, LoanSchedule, UserLoanView,
Company, Address, Review, Capital, Reports, Notification, ChatRoom,
TypingService, Payment, Settings, CashPool, and
`RepositoryProvider<BaseRepository<BankDetails>>` (interface-typed).

`bloc_providers.dart` — 16 BLoCs: User, Registration, Authentication, Product,
Loans, Payment, LoanSettlement, AdditionalLoan, Reports, Reviews, Company,
Capital, CashPool, PaymentCenter, BankDetails, Conversations.

Singleton residue — BLoC files binding `.instance` with NO `.withDependencies`
seam (7, verified 2026-07-07):

```
lib/features/loans/bloc/loans_bloc.dart          (AuthenticationService.instance, :31)
lib/features/loans/bloc/payment_bloc.dart        (+ SettingsService.instance, :28-29)
lib/features/capital/bloc/capital_bloc.dart
lib/features/products/bloc/product_bloc.dart
lib/features/payment_center/bloc/payment_center_bloc.dart
lib/features/companies/bloc/company_bloc.dart
lib/features/reports/bloc/reports_bloc.dart
```

BLoCs WITH a `.withDependencies(...)` seam (singleton only as production default
in the delegating ctor — compliant): registration, payment_submission,
bank_details, chat, conversations, user, authentication, reviews.

Reproduce the split:

```bash
cd apps/loans
for f in $(grep -rln "AuthenticationService.instance\|SettingsService.instance" lib/features --include="*_bloc.dart"); do
  grep -q "withDependencies" "$f" || echo "NO-SEAM: $f"
done
```
