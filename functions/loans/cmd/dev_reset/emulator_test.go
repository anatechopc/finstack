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

func seedEmulators(t *testing.T, tg target, firestoreSeed map[string]map[string]any, rtdbSeed string) {
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
func assertState(t *testing.T, tg target, firestoreSeed map[string]map[string]any, gone map[string]bool, wantTree string) {
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
	seedEmulators(t, tg, firestoreSeed, rtdbSeed)
	assertState(t, tg, firestoreSeed, nil, rtdbSeed)

	// Review finding 2: while dev holds an id the tool does not handle, no plan is written.
	dir := t.TempDir() + "/plan"
	var planOut bytes.Buffer
	unsafe := tg.fs.Collection("dev_loans").Doc("L 2")
	if _, err := unsafe.Set(ctx, map[string]any{"x": 1}); err != nil {
		t.Fatal(err)
	}
	if err := runPlan(ctx, tg, dir, now, &planOut); err == nil || !strings.Contains(err.Error(), "L 2") {
		t.Fatalf("plan with an unsafe document id: want a refusal naming it, got %v", err)
	}
	if _, err := os.Stat(dir + "/" + planFile); err == nil {
		t.Fatal("a plan was written although dev holds an unsafe id")
	}
	if _, err := unsafe.Delete(ctx); err != nil {
		t.Fatal(err)
	}

	// Plan: read-only.
	if err := runPlan(ctx, tg, dir, now, &planOut); err != nil {
		t.Fatalf("plan: %v", err)
	}
	t.Logf("summary.txt:\n%s", planOut.String())
	assertState(t, tg, firestoreSeed, nil, rtdbSeed)
	if err := runPlan(ctx, tg, dir, now, &planOut); err == nil {
		t.Error("a second plan into the same directory was accepted")
	}

	h, lines, err := readPlan(dir, emulatorProject, now)
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
		"user documents kept: 3 (2 registered in Firebase Auth, 1 with no Auth account but in a kept company, 0 kept in doubt), deleted: 2",
		"kept user ids, registered in Firebase Auth: U1, U3",
		"kept user ids, no Auth account, of a kept company: CL1",
		planKey + ": " + h.CreatedAt.Format(time.RFC3339),
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

	// Apply is refused when a user planned for deletion has registered since:
	// the plan's delete lines are classified again from live data.
	registered := tg
	registered.authUsers = func(context.Context) (map[string]string, error) {
		return map[string]string{"U1": "", "U3": "", "ANON": "", "U2": ""}, nil
	}
	applyOut.Reset()
	if err := runApply(ctx, registered, dir, "dev", now, &applyOut); err == nil || !strings.Contains(applyOut.String(), "NOT DELETE ANY MORE dev_users/U2\n") {
		t.Fatalf("apply with U2 now in Auth: want a refusal naming it, got %v\n%s", err, applyOut.String())
	}
	assertState(t, tg, firestoreSeed, nil, rtdbSeed)

	// Review finding 3: a plan in which two kept lines were flipped to delete
	// (an unclassified document and a kept client) is refused as a whole.
	flipped := t.TempDir()
	edited := make([]line, len(lines))
	copy(edited, lines)
	for i, l := range edited {
		if l.Path == "dev_mystery/M1" || l.Path == "dev_users/CL1" {
			edited[i].Decision = del
		}
	}
	writePlan(t, flipped, h, edited)
	writeBackup(t, flipped, "SUCCESSFUL")
	applyOut.Reset()
	err = runApply(ctx, tg, flipped, "dev", now, &applyOut)
	if err == nil || !strings.Contains(applyOut.String(), "NOT DELETE ANY MORE dev_mystery/M1\n") || !strings.Contains(applyOut.String(), "NOT DELETE ANY MORE dev_users/CL1\n") {
		t.Fatalf("apply of a plan with flipped lines: want a refusal naming both, got %v\n%s", err, applyOut.String())
	}
	assertState(t, tg, firestoreSeed, nil, rtdbSeed)

	// Review finding 1, first half: an earlier apply of this plan stopped
	// midway (one document already gone, the started marker written). The same
	// plan may run again and finishes the list.
	hash, err := planHash(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeMarker(dir, startedFile, hash, now, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := tg.fs.Doc("dev_payments/P1").Delete(ctx); err != nil {
		t.Fatal(err)
	}

	// Apply.
	applyOut.Reset()
	if err := runApply(ctx, tg, dir, "dev", now, &applyOut); err != nil {
		t.Fatalf("apply: %v\n%s", err, applyOut.String())
	}
	t.Logf("apply output:\n%s", applyOut.String())
	if !strings.Contains(applyOut.String(), "deleting 20 Firestore documents and 6 Realtime Database nodes") || !strings.Contains(applyOut.String(), "(1 planned paths are already gone)") {
		t.Errorf("apply did not report 20 documents, 6 nodes and 1 path already gone")
	}
	gone := map[string]bool{}
	for _, p := range firestoreDeleted {
		gone[p] = true
	}
	assertState(t, tg, firestoreSeed, gone, rtdbAfter)
	if _, err := os.Stat(dir + "/" + appliedFile); err != nil {
		t.Errorf("no %s after a clean apply: %v", appliedFile, err)
	}

	// Review finding 1, second half: the directory is spent. Fresh data that
	// has the paths of the old plan (a new loan with the old id, the report
	// node the triggers rebuilt) survives a second apply, which is refused.
	if _, err := tg.fs.Doc("dev_loans/L1").Set(ctx, map[string]any{"user_id": "U1", "fresh": true}); err != nil {
		t.Fatal(err)
	}
	if err := tg.rtdb.NewRef("dev/companies/C1/report_summary").Set(ctx, map[string]any{"total": 100}); err != nil {
		t.Fatal(err)
	}
	if err := runApply(ctx, tg, dir, "dev", now, &applyOut); err == nil || !strings.Contains(err.Error(), appliedFile) {
		t.Fatalf("second apply of an applied directory: want a refusal, got %v", err)
	}
	delete(gone, "dev_loans/L1")
	rebuilt := strings.Replace(rtdbAfter, `"C1": {"authentication"`, `"C1": {"report_summary": {"total": 100}, "authentication"`, 1)
	assertState(t, tg, firestoreSeed, gone, rebuilt)
}

// Review finding 4, end to end: the company_id of a user registered in Auth
// is a number. Read as "no company" it would leave C1 unreferenced, and C1,
// its address, its bank details, its client and its Realtime Database node
// would be planned for deletion. They must all stay, and the plan must say why.
func TestEmulator_UnreadableCompanyReference_KeepsTheCompany(t *testing.T) {
	tg := emulatorTarget(t)
	ctx := context.Background()
	seed := map[string]map[string]any{
		"dev_users/U1":        {"id": "U1", "company_id": 123},
		"dev_users/CL1":       {"id": "CL1", "company_id": "C1"},
		"dev_companies/C1":    {"id": "C1"},
		"dev_address/A1":      {"data_id": "C1"},
		"dev_address/A2":      {"data_id": 77},
		"dev_bank_details/B1": {"dataId": "C1"},
		"dev_settings/S1":     {"user_id": nil},
		"dev_loans/L1":        {"company_id": "C1"},
	}
	tree := `{"dev": {"companies": {"C1": {"report_summary": {"total": 1}, "loans": {"L1:product_type": "x"}, "something_else": true}}}}`
	seedEmulators(t, tg, seed, tree)

	dir := t.TempDir() + "/plan"
	var out bytes.Buffer
	if err := runPlan(ctx, tg, dir, time.Now(), &out); err != nil {
		t.Fatalf("plan: %v", err)
	}
	_, lines, err := readPlan(dir, emulatorProject, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	var deletes []string
	for _, l := range lines {
		if l.Decision == del {
			deletes = append(deletes, l.Path)
		}
	}
	// Only the loan and the kept company's report and loans nodes go.
	if got, want := strings.Join(deletes, " "), "dev_loans/L1 dev/companies/C1/loans dev/companies/C1/report_summary"; got != want {
		t.Errorf("planned deletes:\n got %s\nwant %s", got, want)
	}
	for _, want := range []string{"dev_address/A2 (data_id), dev_users/U1 (company_id)", "EVERY company document is kept", "kept company ids: C1"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("summary.txt does not mention %q\n%s", want, out.String())
		}
	}
	assertState(t, tg, seed, nil, tree)
}
