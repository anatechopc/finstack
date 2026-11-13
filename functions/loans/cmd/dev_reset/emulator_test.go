//go:build emulator

// Emulator proof for dev_reset: plan and apply run against the Firestore and
// Realtime Database emulators, and only the planned dev paths disappear.
//
//	cd apps/loans && firebase emulators:start --only database,firestore --project demo-finstack
//	cd functions/loans && FIRESTORE_EMULATOR_HOST=localhost:8081 \
//	  FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' \
//	  go test -tags emulator ./cmd/dev_reset/ -run Emulator -v
//
// The test wipes the emulator's demo-finstack data before seeding. It reaches
// the emulators through the target struct, which only test code can build
// with emulator set; the command line has no such switch.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const emulatorProject = "demo-finstack"

// Auth uids the fake Auth listing returns. There is no Auth emulator in this
// test: the uid list is the one input the seam supplies directly.
var emulatorAuth = map[string]string{"U1": "one@example.com", "U3": "", "ANON": ""}

func emulatorTarget(t *testing.T) target {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" || os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		t.Skip("set FIRESTORE_EMULATOR_HOST and FIREBASE_DATABASE_EMULATOR_HOST='host:port?ns=demo-finstack' to run the emulator proof")
	}
	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: emulatorProject, DatabaseURL: "https://" + emulatorProject + ".firebaseio.com"})
	if err != nil {
		t.Fatal(err)
	}
	fs, err := app.Firestore(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { fs.Close() })
	rtdb, err := app.Database(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return target{
		project: emulatorProject, emulator: true, fs: fs, rtdb: rtdb,
		authUsers: func(context.Context) (map[string]string, error) { return emulatorAuth, nil },
	}
}

// Firestore seed: path -> fields. deleted lists exactly the paths the plan
// must mark delete; every other seeded path must survive apply.
var firestoreSeed = map[string]map[string]any{
	// dev: users. U1 and U3 are in Auth. CL1 and CL2 are not: CL1 belongs to
	// the kept company C1 and stays, CL2 belongs to C2, which no Auth user
	// references, and goes with it.
	"dev_users/U1":             {"id": "U1", "company_id": "C1", "first_name": "kept"},
	"dev_users/U2":             {"id": "U2", "company_id": "C2"},
	"dev_users/U3":             {"id": "U3"},
	"dev_users/CL1":            {"id": "CL1", "company_id": "C1"},
	"dev_users/CL2":            {"id": "CL2", "company_id": "C2"},
	"dev_users/U1/devices/D1":  {"token": "t1"},
	"dev_users/U2/devices/D2":  {"token": "t2"},
	"dev_users/CL1/devices/D3": {"token": "t3"},
	// dev: companies and owner-scoped configuration
	"dev_companies/C1":    {"id": "C1"},
	"dev_companies/C2":    {"id": "C2"},
	"dev_address/A1":      {"data_id": "U1", "data_type": "user"},
	"dev_address/A2":      {"data_id": "C1", "data_type": "provider"},
	"dev_address/A3":      {"data_id": "U2", "data_type": "user"},
	"dev_address/A4":      {"data_id": "C2", "data_type": "provider"},
	"dev_address/A5":      {"line1": "no owner"},
	"dev_address/A6":      {"data_id": "CL1", "data_type": "user"},
	"dev_address/A7":      {"data_id": "CL2", "data_type": "user"},
	"dev_bank_details/B1": {"dataId": "C1"},
	"dev_bank_details/B2": {"dataId": "C2"},
	"dev_settings/S1":     {"user_id": "U1"},
	"dev_settings/S2":     {"user_id": "U2"},
	// dev: loans domain, including a kept user's loan and a kept company's product
	"dev_loans/L1":                   {"user_id": "U1", "company_id": "C1"},
	"dev_loan_schedules/LS1":         {"loan_id": "L1"},
	"dev_payments/P1":                {"loan_id": "L1"},
	"dev_products/PR1":               {"company_id": "C1"},
	"dev_product_views/PV1":          {"company_id": "C1"},
	"dev_notifications/N1":           {"recipient_id": "U1"},
	"dev_chat_rooms/R1":              {"last_seq": 1},
	"dev_chat_rooms/R1/messages/M1":  {"text": "hello"},
	"dev_chat_rooms/R2/messages/M2":  {"text": "room document R2 does not exist"},
	"dev_password_setup_tokens/T1":   {"uid": "U1"},
	"dev_user_loan_views/V1":         {"user_id": "U1"},
	"dev_additional_loan_amounts/X1": {"loan_id": "L1"},
	// dev: a collection the rule table does not know
	"dev_mystery/M1":             {"x": 1},
	"dev_mystery/M1/children/M2": {"x": 2},
	// staging: same ids as dev on purpose
	"stg_users/U1":                  {"id": "U1", "company_id": "C1"},
	"stg_users/U2":                  {"id": "U2", "company_id": "C2"},
	"stg_users/CL2":                 {"id": "CL2", "company_id": "C2"},
	"stg_users/U2/devices/D2":       {"token": "t2"},
	"stg_companies/C2":              {"id": "C2"},
	"stg_loans/L1":                  {"user_id": "U1"},
	"stg_chat_rooms/R1":             {"last_seq": 1},
	"stg_chat_rooms/R1/messages/M1": {"text": "hello"},
	"stg_address/A3":                {"data_id": "U2"},
	// production-shaped, unprefixed
	"users/U2":                  {"id": "U2"},
	"loans/L1":                  {"user_id": "U1"},
	"chat_rooms/R1/messages/M1": {"text": "hello"},
	// dev_ only in the middle of the id
	"stg_dev_loans/L1": {"x": 1},
	"mydev_users/U2":   {"x": 1},
}

var firestoreDeleted = []string{
	"dev_users/U2", "dev_users/U2/devices/D2", "dev_users/CL2",
	"dev_companies/C2",
	"dev_address/A3", "dev_address/A4", "dev_address/A7", "dev_bank_details/B2", "dev_settings/S2",
	"dev_loans/L1", "dev_loan_schedules/LS1", "dev_payments/P1", "dev_products/PR1", "dev_product_views/PV1",
	"dev_notifications/N1", "dev_chat_rooms/R1", "dev_chat_rooms/R1/messages/M1", "dev_chat_rooms/R2/messages/M2",
	"dev_password_setup_tokens/T1", "dev_user_loan_views/V1", "dev_additional_loan_amounts/X1",
}

const rtdbSeed = `{
  "dev": {
    "companies": {
      "C1": {"report_summary": {"total": 1}, "report_events": {"e1": {"applied": true}}, "report_recomputes": {"r1": 1},
             "loans": {"L1:product_type": "business"}, "authentication": {"force_logout": false}, "something_else": true},
      "C2": {"report_summary": {"total": 2}, "loans": {"L2:product_type": "personal"}},
      "C9": {"report_summary": {"total": 9}, "loans": {"L9:product_type": "personal"}}
    },
    "typing": {"R1": {"U1": 1}}
  },
  "stg": {
    "companies": {"C1": {"report_summary": {"total": 5}, "report_events": {"e1": {"applied": true}}, "loans": {"L1:product_type": "business"}},
                  "C2": {"report_summary": {"total": 6}}},
    "typing": {"R1": {"U1": 1}}
  },
  "companies": {"C1": {"report_summary": {"total": 7}, "loans": {"L1:product_type": "business"}}},
  "otp": {"h1": {"mobile": "x"}}
}`

// What the Realtime Database must hold after apply: C1 (kept company) loses
// its three report nodes and its loans node, C2 (deleted company) goes, C9 (no
// company document, so neither kept nor deleted) loses only its report node,
// everything outside dev/companies is untouched.
const rtdbAfter = `{
  "dev": {
    "companies": {
      "C1": {"authentication": {"force_logout": false}, "something_else": true},
      "C9": {"loans": {"L9:product_type": "personal"}}
    },
    "typing": {"R1": {"U1": 1}}
  },
  "stg": {
    "companies": {"C1": {"report_summary": {"total": 5}, "report_events": {"e1": {"applied": true}}, "loans": {"L1:product_type": "business"}},
                  "C2": {"report_summary": {"total": 6}}},
    "typing": {"R1": {"U1": 1}}
  },
  "companies": {"C1": {"report_summary": {"total": 7}, "loans": {"L1:product_type": "business"}}},
  "otp": {"h1": {"mobile": "x"}}
}`

var rtdbDeleted = []string{
	"dev/companies/C1/loans",
	"dev/companies/C1/report_events", "dev/companies/C1/report_recomputes", "dev/companies/C1/report_summary",
	"dev/companies/C2", "dev/companies/C9/report_summary",
}

func canonical(t *testing.T, v any) string {
	t.Helper()
	if s, ok := v.(string); ok {
		var decoded any
		if err := json.Unmarshal([]byte(s), &decoded); err != nil {
			t.Fatal(err)
		}
		v = decoded
	}
	out, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

func seedEmulators(t *testing.T, tg target) {
	t.Helper()
	ctx := context.Background()
	wipe, err := http.NewRequest(http.MethodDelete,
		"http://"+os.Getenv("FIRESTORE_EMULATOR_HOST")+"/emulator/v1/projects/"+emulatorProject+"/databases/(default)/documents", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(wipe)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("wipe the Firestore emulator: %v %v", resp, err)
	}
	resp.Body.Close()
	for path, fields := range firestoreSeed {
		if _, err := tg.fs.Doc(path).Set(ctx, fields); err != nil {
			t.Fatalf("seed %s: %v", path, err)
		}
	}
	var tree any
	if err := json.Unmarshal([]byte(rtdbSeed), &tree); err != nil {
		t.Fatal(err)
	}
	if err := tg.rtdb.NewRef("/").Set(ctx, tree); err != nil {
		t.Fatalf("seed the Realtime Database: %v", err)
	}
}

// assertState reads every seeded document one by one (not through the tool's
// walker) and the whole Realtime Database, and compares with what must exist.
func assertState(t *testing.T, tg target, gone map[string]bool, wantTree string) {
	t.Helper()
	ctx := context.Background()
	for path := range firestoreSeed {
		_, err := tg.fs.Doc(path).Get(ctx)
		switch {
		case gone[path] && status.Code(err) != codes.NotFound:
			t.Errorf("%s should be deleted, Get returned %v", path, err)
		case !gone[path] && err != nil:
			t.Errorf("%s should exist: %v", path, err)
		}
	}
	var tree any
	if err := tg.rtdb.NewRef("/").Get(ctx, &tree); err != nil {
		t.Fatal(err)
	}
	if got, want := canonical(t, tree), canonical(t, wantTree); got != want {
		t.Errorf("Realtime Database tree:\n got %s\nwant %s", got, want)
	}
}

func TestEmulator_PlanThenApply_DeletesExactlyThePlannedDevPaths(t *testing.T) {
	tg := emulatorTarget(t)
	ctx := context.Background()
	now := time.Now()
	seedEmulators(t, tg)
	assertState(t, tg, nil, rtdbSeed)

	// Plan: read-only.
	dir := t.TempDir() + "/plan"
	var planOut bytes.Buffer
	if err := runPlan(ctx, tg, dir, now, &planOut); err != nil {
		t.Fatalf("plan: %v", err)
	}
	t.Logf("summary.txt:\n%s", planOut.String())
	assertState(t, tg, nil, rtdbSeed)
	if err := runPlan(ctx, tg, dir, now, &planOut); err == nil {
		t.Error("a second plan into the same directory was accepted")
	}

	lines, err := readPlan(dir, emulatorProject, now)
	if err != nil {
		t.Fatalf("read the plan back: %v", err)
	}
	wantDelete := map[string]bool{}
	for _, p := range append(append([]string{}, firestoreDeleted...), rtdbDeleted...) {
		wantDelete[p] = true
	}
	planned := map[string]string{}
	for _, l := range lines {
		planned[l.Path] = l.Decision
		if !strings.HasPrefix(l.Path, "dev_") && !strings.HasPrefix(l.Path, "dev/") {
			t.Errorf("the plan lists a path outside dev: %s", l.Path)
		}
		if (l.Decision == del) != wantDelete[l.Path] {
			t.Errorf("%s: planned %q, want delete=%v (%s)", l.Path, l.Decision, wantDelete[l.Path], l.Rule)
		}
	}
	for p := range wantDelete {
		if planned[p] != del {
			t.Errorf("%s is missing from the plan's delete list", p)
		}
	}
	for path := range firestoreSeed {
		if strings.HasPrefix(path, "dev_") && planned[path] == "" {
			t.Errorf("dev document %s is not in the plan", path)
		}
	}
	summary := planOut.String()
	for _, want := range []string{
		"dev_mystery", "UNCLASSIFIED", "kept company ids: C1", "dev/companies/C2 ", "dev/companies/C1/loans ", "children,",
		"user documents kept: 3 (2 registered in Firebase Auth, 1 with no Auth account but in a kept company), deleted: 2",
		"kept user ids, registered in Firebase Auth: U1, U3",
		"kept user ids, no Auth account, of a kept company: CL1",
	} {
		if !strings.Contains(summary, want) {
			t.Errorf("summary.txt does not mention %q", want)
		}
	}
	raw, err := os.ReadFile(dir + "/" + planFile)
	if err != nil {
		t.Fatal(err)
	}
	for _, content := range []string{"hello", "one@example.com", "business", "first_name", "no owner\""} {
		if strings.Contains(summary, content) || bytes.Contains(raw, []byte(content)) {
			t.Errorf("summary.txt or plan.jsonl holds document content %q", content)
		}
	}

	// Apply is refused without a backup, and nothing changes.
	var applyOut bytes.Buffer
	if err := runApply(ctx, tg, dir, "dev", now, &applyOut); err == nil || !strings.Contains(err.Error(), backupFile) {
		t.Fatalf("apply without backup.txt: want a refusal, got %v", err)
	}
	writeBackup(t, dir, "SUCCESSFUL")

	// Apply is refused when a user planned for deletion has registered since.
	registered := tg
	registered.authUsers = func(context.Context) (map[string]string, error) {
		return map[string]string{"U1": "", "U3": "", "ANON": "", "U2": ""}, nil
	}
	if err := runApply(ctx, registered, dir, "dev", now, &applyOut); err == nil || !strings.Contains(err.Error(), "dev_users/U2") {
		t.Fatalf("apply with U2 now in Auth: want a refusal, got %v", err)
	}
	assertState(t, tg, nil, rtdbSeed)

	// Apply.
	if err := runApply(ctx, tg, dir, "dev", now, &applyOut); err != nil {
		t.Fatalf("apply: %v\n%s", err, applyOut.String())
	}
	t.Logf("apply output:\n%s", applyOut.String())
	gone := map[string]bool{}
	for _, p := range firestoreDeleted {
		gone[p] = true
	}
	assertState(t, tg, gone, rtdbAfter)

	// A second apply of the same plan deletes nothing more.
	if err := runApply(ctx, tg, dir, "dev", now, &applyOut); err != nil {
		t.Fatalf("second apply: %v", err)
	}
	assertState(t, tg, gone, rtdbAfter)
}
