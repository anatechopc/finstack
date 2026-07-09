# Recipe: add a tested Go handler (adapter + core + fakes)

The house discipline for `functions/loans/` (unwritten rule 4: new or touched Go
code ships adapter+core with fakes-based tests). Every path/name below verified
2026-07-07. Read one worked pair first — the best trigger example is
`triggers/message_written_core.go` + `triggers/message_written.go` +
`test/triggers/message_written_core_test.go`; the best HTTP example is
`api/users/request_otp.go` + `test/api/users/request_otp_handler_test.go`.

## Module layout you are working inside

- Root module `com.loooans.app` (`functions/loans/go.mod`, go 1.22.12) with
  `replace` directives to local submodules: `./api`, `./triggers`, `./utils`,
  `./types`, `./job`, `./test/fakes`.
- `test/` (except `test/fakes/`) has no own go.mod — test files compile under
  the ROOT module and import production code as `com.loooans.app/api/users`,
  `com.loooans.app/triggers`, etc.
- `test/fakes/` IS a separate module `com.loooans.app/test/fakes` (own go.mod,
  depends only on `com.loooans.app/types`). Fakes must not import `api/` or
  `triggers/` — keep them dumb recorders over plain types.
- Cross-side shared types (e.g. `types.ChatParticipant`) live in `types/`.

## Step 1 — Define the Deps struct (plain func fields)

In the handler's package (`triggers/` or `api/users/`), either in the handler
file or a sibling `*_core.go`:

```go
// XxxDeps injects every side effect so the core is unit-testable.
type XxxDeps struct {
    ReadThing   func(ctx context.Context, id string) (map[string]any, error)
    WriteThing  func(ctx context.Context, id string, fields map[string]any) error
    Now         func() time.Time // inject time whenever the logic touches it
}
```

Conventions (from `VerifyOtpDeps`, `MessageWrittenDeps`):
- One func field per side effect, named for the capability not the technology
  (`UpdateUser`, not `FirestoreMerge`).
- Values crossing the boundary are plain Go types (`map[string]any`, strings,
  int64 millis) — no Firestore/RTDB client types in core signatures.
- Time is a dep: reuse `triggers.FixedClock(epochMillis)` in trigger tests
  (`message_written_core.go:36`); HTTP cores take `Now func() time.Time` and
  tests pin it.

## Step 2 — Write the Core function (all business logic)

```go
func HandleXxxCore(ctx context.Context, ev XxxEvent, deps XxxDeps) error { ... }
```

- Cores return sentinel errors for caller-distinguishable outcomes — see
  `verify_otp.go`: `ErrOtpNotFound` / `ErrOtpExpired` / `ErrOtpInvalid`, which
  the adapter maps to specific 4xx responses.
- For fan-out logic, follow `HandleReviewCreatedCore`'s two-value contract:
  hard lookup errors returned (→ adapter returns error → Cloud Functions
  retries); per-recipient best-effort failures collected and logged, NOT
  returned (avoids re-notifying recipients that already succeeded).
- Dates written to Firestore/RTDB are **int64 millis** (`.UnixMilli()`), never
  `time.Time` — see `finstack-failure-archaeology` (Timestamp saga, PRs
  finstack#47/#48/#49) and `finstack-architecture-contract`.

## Step 3 — Write the thin adapter

Trigger adapter (pattern of `MessageWritten` in `triggers/message_written.go`):
1. `utils.InitializeLogger("functionName")`.
2. Unmarshal the CloudEvent protobuf (`firestoredata.DocumentEventData`),
   extract ids from the resource path, flatten fields to `map[string]any`.
3. Init Firebase (`utils.InitializeFirebase`), get prefix via
   `utils.GetCollectionPrefix()`.
4. Build real deps in one place — a `buildXxxDeps(app, fs, prefix)` helper
   returning the Deps struct with closures over real clients
   (`message_written.go:117`).
5. Call the core; return its error (or nil).

HTTP adapter (pattern of `VerifyOtp` / `RequestOtpHandler` in `api/users/`):
CORS headers → `utils.ValidateRequestV2()` JWT → parse body → build deps →
call core → map sentinel errors to status codes → JSON response.
If you want the adapter itself testable (recommended for new HTTP functions),
copy `request_otp.go`'s shape: the exported entry point delegates to a
`XxxHandler(validate, depsBuilder, subdomain) http.Handler` whose pieces tests
can stub — see the `handlerHarness` + `httptest` idiom in
`test/api/users/request_otp_handler_test.go`.

## Step 4 — Add fakes to test/fakes/fakes.go

ALL fakes live in the single file `test/fakes/fakes.go` (package `fakes`).
"Registering" a fake = adding its type there. House shape — a struct that
records calls and returns a configurable error:

```go
// ThingWriter fake — records every write; returns Err if set.
type ThingWrite struct{ Id string; Fields map[string]any }
type ThingWriter struct {
    Writes []ThingWrite
    Err    error
}
func (w *ThingWriter) Write(_ context.Context, id string, fields map[string]any) error {
    w.Writes = append(w.Writes, ThingWrite{Id: id, Fields: fields})
    return w.Err
}
```

Reader fakes hold a preconfigured map plus a package-level sentinel
(e.g. `fakes.OtpReader` with `ErrOtpNotFound`). Browse the ~40 existing types
before adding one — many are reusable (`Notifier`, `UserReader`,
`CompanyUsersReader`, `EmailSender`, ...). If your fake needs a shared type,
it may only come from `com.loooans.app/types`.

## Step 5 — Write the test

Location: `test/triggers/xxx_test.go` or `test/api/users/xxx_test.go`,
package `triggers_test` / `users_test`. Shape (from
`message_written_core_test.go`):

```go
func xxxDeps(w *fakes.ThingWriter /* ... */) triggers.XxxDeps {
    return triggers.XxxDeps{
        WriteThing: w.Write,
        Now:        triggers.FixedClock(1_700_000_000_000),
    }
}

func TestXxx_HappyPath(t *testing.T) {
    w := &fakes.ThingWriter{}
    err := triggers.HandleXxxCore(context.Background(), ev, xxxDeps(w))
    if err != nil { t.Fatalf("unexpected err: %v", err) }
    if len(w.Writes) != 1 { t.Fatalf("writes: %v", w.Writes) }
}
```

Plain stdlib `testing` — no testify. Cover: happy path(s), each sentinel/error
branch, error propagation from each dep, and no-op guards.

## Step 6 — Run

```bash
cd /Users/deibeeed/Projects/AnaheimTechnologies/finstack/functions/loans
CGO_ENABLED=0 go test ./...   # macOS (dyld: missing LC_UUID workaround)
go test -v ./...              # what Linux CI runs
go build -v ./...
```

If you added a dependency to a submodule, `go mod tidy` in that submodule dir
(per `functions/loans/CLAUDE.md`).

## Step 7 — Wire up (new functions only)

Register in `loooans_cloud_functions.go` `init()` (`functions.HTTP(...)` /
`functions.CloudEvent(...)`) and add a deploy entry — deploy-script anatomy is
owned by `finstack-run-deploy-operate`; PR/branch discipline by
`finstack-change-control`.

## Backfill backlog (sanctioned hardening)

Monolithic, untested as of 2026-07-07: `triggers/notification_created.go`,
`triggers/loan_changes.go`, `triggers/capital_created.go`,
`triggers/loan_schedule_changes.go`, plus `triggers/notification_helpers.go`.
Converting them to this recipe is welcome — EXCEPT `loan_changes.go`
(the reporting engine, known-buggy): its rework is decision-gated by
`finstack-loan-engine-and-reporting-campaign`. Do not refactor it piecemeal.
