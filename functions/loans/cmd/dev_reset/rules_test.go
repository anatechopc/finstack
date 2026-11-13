package main

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func decisions(lines []line) map[string]string {
	got := map[string]string{}
	for _, l := range lines {
		got[l.Path] = l.Decision
	}
	return got
}

func TestClassify(t *testing.T) {
	auth := map[string]string{"U1": "one@example.com", "U3": "", "U5": "five@example.com", "ANON": ""}
	docs := []doc{
		// users registered in Auth: kept by document id or by id field
		{path: "dev_users/U1", fields: map[string]string{"id": "U1", "company_id": "C1"}},
		{path: "dev_users/U3"},
		{path: "dev_users/legacy", fields: map[string]string{"id": "U5", "company_id": "C5"}},
		// users without an Auth account: kept only with a kept company. C2 is
		// referenced by two of them and by no Auth user, so C2 is not kept.
		{path: "dev_users/CL1", fields: map[string]string{"id": "CL1", "company_id": "C1"}},
		{path: "dev_users/U2", fields: map[string]string{"id": "U2", "company_id": "C2", "email_address": "Five@Example.com"}},
		{path: "dev_users/CL2", fields: map[string]string{"id": "CL2", "company_id": "C2"}},
		{path: "dev_users/LONE", fields: map[string]string{"id": "LONE"}},
		{path: "dev_users/U1/devices/D1"},
		{path: "dev_users/U2/devices/D2"},
		{path: "dev_users/CL1/devices/D5"},
		{path: "dev_users/GONE/devices/D3"}, // parent document does not exist, uid not in Auth
		{path: "dev_users/ANON/devices/D4"}, // parent document does not exist, uid in Auth
		// companies
		{path: "dev_companies/C1"},
		{path: "dev_companies/C2"},
		{path: "dev_companies/C5"},
		// owner-scoped configuration follows its owner
		{path: "dev_address/A1", fields: map[string]string{"data_id": "U1"}},
		{path: "dev_address/A2", fields: map[string]string{"data_id": "C1"}},
		{path: "dev_address/A3", fields: map[string]string{"data_id": "U2"}},
		{path: "dev_address/A4", fields: map[string]string{"data_id": "C2"}},
		{path: "dev_address/A5"},
		{path: "dev_address/A6", fields: map[string]string{"data_id": "CL1"}},
		{path: "dev_address/A7", fields: map[string]string{"data_id": "CL2"}},
		{path: "dev_address/A8", fields: map[string]string{"data_id": "LONE"}},
		{path: "dev_bank_details/B1", fields: map[string]string{"dataId": "C1"}},
		{path: "dev_bank_details/B2", fields: map[string]string{"data_id": "U5"}},
		{path: "dev_bank_details/B3", fields: map[string]string{"dataId": "C2"}},
		{path: "dev_settings/S1", fields: map[string]string{"user_id": "U1"}},
		{path: "dev_settings/S2", fields: map[string]string{"user_id": "U2"}},
		{path: "dev_settings/S3", fields: map[string]string{"user_id": "CL1"}},
		{path: "dev_bills/BL1", fields: map[string]string{"client_id": "C1"}},
		{path: "dev_bills/BL2", fields: map[string]string{"client_id": "C2"}},
		// loans domain: all deleted, whoever owns it
		{path: "dev_loans/L1"},
		{path: "dev_chat_rooms/R1"},
		{path: "dev_chat_rooms/R1/messages/M1"},
		{path: "dev_chat_rooms/R2/messages/M2"},
		// not in the rule table
		{path: "dev_mystery/X1"},
		{path: "dev_mystery/X1/children/X2"},
	}
	want := map[string]string{
		"dev_users/U1": keep, "dev_users/U3": keep, "dev_users/legacy": keep,
		"dev_users/CL1": keep, "dev_users/U2": del, "dev_users/CL2": del, "dev_users/LONE": del,
		"dev_users/U1/devices/D1": keep, "dev_users/U2/devices/D2": del, "dev_users/CL1/devices/D5": keep,
		"dev_users/GONE/devices/D3": del, "dev_users/ANON/devices/D4": keep,
		"dev_companies/C1": keep, "dev_companies/C2": del, "dev_companies/C5": keep,
		"dev_address/A1": keep, "dev_address/A2": keep, "dev_address/A3": del, "dev_address/A4": del, "dev_address/A5": keep,
		"dev_address/A6": keep, "dev_address/A7": del, "dev_address/A8": del,
		"dev_bank_details/B1": keep, "dev_bank_details/B2": keep, "dev_bank_details/B3": del,
		"dev_settings/S1": keep, "dev_settings/S2": del, "dev_settings/S3": keep,
		"dev_bills/BL1": keep, "dev_bills/BL2": del,
		"dev_loans/L1": del, "dev_chat_rooms/R1": del, "dev_chat_rooms/R1/messages/M1": del, "dev_chat_rooms/R2/messages/M2": del,
		"dev_mystery/X1": keep, "dev_mystery/X1/children/X2": keep,
	}

	c := classify(docs, auth)
	got := decisions(c.lines)
	if len(got) != len(want) {
		t.Fatalf("classified %d documents, want %d", len(got), len(want))
	}
	for path, decision := range want {
		if got[path] != decision {
			t.Errorf("%s: got %q, want %q", path, got[path], decision)
		}
	}
	if !c.deletedCompanies["C2"] || len(c.deletedCompanies) != 1 {
		t.Errorf("deleted companies = %v, want only C2", c.deletedCompanies)
	}
	// Only Auth-registered users make a company kept.
	if !c.keptCompanies["C1"] || !c.keptCompanies["C5"] || len(c.keptCompanies) != 2 {
		t.Errorf("kept companies = %v, want C1 and C5", c.keptCompanies)
	}
	ruleOf := map[string]string{}
	for _, l := range c.lines {
		ruleOf[l.Path] = l.Rule
	}
	for path, want := range map[string]string{
		"dev_users/U1": ruleUserInAuth, "dev_users/legacy": ruleUserInAuth, "dev_users/CL1": ruleUserClient,
		"dev_users/CL2": ruleUserDeleted, "dev_users/LONE": ruleUserDeleted, "dev_address/A5": ruleNoOwner,
	} {
		if ruleOf[path] != want {
			t.Errorf("%s: rule %q, want %q", path, ruleOf[path], want)
		}
	}
	if c.emailOverlap != 1 {
		t.Errorf("email overlap = %d, want 1 (U2 carries the email of Auth user U5)", c.emailOverlap)
	}
}

// Every loans-domain collection the owner listed must be delete-all, and the
// account collections must not be.
func TestRuleTable(t *testing.T) {
	for _, name := range []string{"loans", "loan_schedules", "payments", "additional_loan_amounts", "capital", "cash_pool",
		"products", "product_views", "user_loan_views", "reviews", "notifications", "chat_rooms", "password_setup_tokens"} {
		if r, ok := ruleFor(name); !ok || r.kind != deleteAll {
			t.Errorf("%s must be a delete-all collection", name)
		}
	}
	for _, name := range []string{"users", "companies", "address", "bank_details", "settings"} {
		if r, ok := ruleFor(name); !ok || r.kind == deleteAll {
			t.Errorf("%s must not be a delete-all collection", name)
		}
	}
}

func TestClassifyRTDB(t *testing.T) {
	lines := classifyRTDB(
		[]string{"companies", "typing"},
		map[string][]string{
			"C1":     {"authentication", "loans", "report_events", "report_recomputes", "report_summary", "something_else"},
			"C2":     {"loans", "report_summary"},
			"ORPHAN": {"loans", "report_summary"}, // no company document at all: neither kept nor deleted
			"LEAF":   nil,
		},
		map[string]bool{"C1": true},
		map[string]bool{"C2": true},
	)
	want := map[string]string{
		"dev/typing":                          keep,
		"dev/companies/C1/authentication":     keep,
		"dev/companies/C1/something_else":     keep,
		"dev/companies/C1/loans":              del,
		"dev/companies/C1/report_events":      del,
		"dev/companies/C1/report_recomputes":  del,
		"dev/companies/C1/report_summary":     del,
		"dev/companies/C2":                    del,
		"dev/companies/ORPHAN/loans":          keep,
		"dev/companies/ORPHAN/report_summary": del,
		"dev/companies/LEAF":                  keep,
	}
	got := decisions(lines)
	if len(got) != len(want) {
		t.Fatalf("got %d lines, want %d: %v", len(got), len(want), got)
	}
	for path, decision := range want {
		if got[path] != decision {
			t.Errorf("%s: got %q, want %q", path, got[path], decision)
		}
	}
	for _, l := range lines {
		if err := checkLine(l); err != nil {
			t.Errorf("the planner produced a line that apply would refuse: %v", err)
		}
	}
}

func TestPathValidation(t *testing.T) {
	accept := []line{
		{Kind: "firestore", Path: "dev_users/U1", Decision: del},
		{Kind: "firestore", Path: "dev_chat_rooms/R1/messages/M1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1", Decision: keep},
		{Kind: "rtdb", Path: "dev/companies/C1", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report_summary", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report_events", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report_recomputes", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/loans", Decision: del},
		{Kind: "rtdb", Path: "dev/typing", Decision: keep},
	}
	for _, l := range accept {
		if err := checkLine(l); err != nil {
			t.Errorf("%s %s %s refused: %v", l.Kind, l.Decision, l.Path, err)
		}
	}

	refuse := []line{
		// staging, production-shaped and look-alike Firestore paths
		{Kind: "firestore", Path: "stg_users/U1", Decision: del},
		{Kind: "firestore", Path: "users/U1", Decision: del},
		{Kind: "firestore", Path: "stg_dev_users/U1", Decision: del}, // dev_ only in the middle
		{Kind: "firestore", Path: "users/dev_U1", Decision: del},
		{Kind: "firestore", Path: "xdev_users/U1", Decision: del},
		{Kind: "firestore", Path: "stg_chat_rooms/R1/dev_messages/M1", Decision: del},
		{Kind: "firestore", Path: "DEV_users/U1", Decision: del},
		{Kind: "firestore", Path: "dev_/U1", Decision: del},
		{Kind: "firestore", Path: "dev_users", Decision: del}, // a collection, not a document
		{Kind: "firestore", Path: "dev_users/U1/devices", Decision: del},
		{Kind: "firestore", Path: "dev_users/", Decision: del},
		{Kind: "firestore", Path: "/dev_users/U1", Decision: del},
		{Kind: "firestore", Path: "dev_users//devices/D1", Decision: del},
		{Kind: "firestore", Path: "dev_users/../stg_users/U1", Decision: del},
		{Kind: "firestore", Path: "projects/loooans-prod/databases/(default)/documents/dev_users/U1", Decision: del},
		{Kind: "firestore", Path: "stg_users/U1", Decision: keep},
		{Kind: "firestore", Path: "", Decision: del},
		// Realtime Database
		{Kind: "rtdb", Path: "stg/companies/C1/report_summary", Decision: del},
		{Kind: "rtdb", Path: "stg/companies/C1", Decision: del},
		{Kind: "rtdb", Path: "companies/C1/report_summary", Decision: del}, // production shape
		{Kind: "rtdb", Path: "devx/companies/C1", Decision: del},
		{Kind: "rtdb", Path: "stg/dev/companies/C1", Decision: del},
		{Kind: "rtdb", Path: "dev", Decision: del},
		{Kind: "rtdb", Path: "dev/", Decision: del},
		{Kind: "rtdb", Path: "dev/companies", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/", Decision: del},
		{Kind: "rtdb", Path: "dev/typing", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/authentication", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/something_else", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/loans/L1:product_type", Decision: del},
		{Kind: "rtdb", Path: "stg/companies/C1/loans", Decision: del},
		{Kind: "rtdb", Path: "companies/C1/loans", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report_summary/data", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/../../stg", Decision: del},
		{Kind: "rtdb", Path: "otp/hash", Decision: del},
		{Kind: "rtdb", Path: "stg/typing", Decision: keep},
		// malformed lines
		{Kind: "storage", Path: "dev_users/U1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1", Decision: "remove"},
		{Kind: "", Path: "dev_users/U1", Decision: del},
	}
	for _, l := range refuse {
		if err := checkLine(l); err == nil {
			t.Errorf("%s %s %q was accepted", l.Kind, l.Decision, l.Path)
		}
	}
}

func TestProjectGuards(t *testing.T) {
	for _, project := range []string{"loooans-prod", "", "loooans-dev-stg2", "demo-finstack"} {
		if checkProject(project) == nil {
			t.Errorf("project %q was accepted", project)
		}
		if (target{project: project}).check() == nil {
			t.Errorf("a non-emulator target for project %q was accepted", project)
		}
	}
	if err := checkProject("loooans-dev-stg"); err != nil {
		t.Errorf("the dev project was refused: %v", err)
	}
	// The emulator seam does not open a way to a real project.
	if (target{project: "loooans-prod", emulator: true}).check() == nil {
		t.Error("an emulator target for a real project was accepted")
	}

	env := func(values map[string]string) func(string) string {
		return func(name string) string { return values[name] }
	}
	if err := checkADCProject("", env(nil)); err != nil {
		t.Errorf("credentials that name no project were refused: %v", err)
	}
	if err := checkADCProject("loooans-dev-stg", env(map[string]string{"GOOGLE_CLOUD_PROJECT": "loooans-dev-stg"})); err != nil {
		t.Errorf("credentials for the dev project were refused: %v", err)
	}
	if checkADCProject("loooans-prod", env(nil)) == nil {
		t.Error("credentials for the production project were accepted")
	}
	if checkADCProject("", env(map[string]string{"GOOGLE_CLOUD_PROJECT": "loooans-prod"})) == nil {
		t.Error("GOOGLE_CLOUD_PROJECT=loooans-prod was accepted")
	}
	if checkADCProject("loooans-dev-stg", env(map[string]string{"GCLOUD_PROJECT": "loooans-prod"})) == nil {
		t.Error("GCLOUD_PROJECT=loooans-prod was accepted")
	}
}

// writePlan writes a plan.jsonl the way runPlan does.
func writePlan(t *testing.T, dir string, h header, lines []line) {
	t.Helper()
	f, err := os.Create(filepath.Join(dir, planFile))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	if err := enc.Encode(h); err != nil {
		t.Fatal(err)
	}
	for _, l := range lines {
		if err := enc.Encode(l); err != nil {
			t.Fatal(err)
		}
	}
}

// planHeader reads the header of the plan in dir.
func planHeader(t *testing.T, dir string) header {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(dir, planFile))
	if err != nil {
		t.Fatal(err)
	}
	var h header
	first, _, _ := strings.Cut(string(raw), "\n")
	if err := json.Unmarshal([]byte(first), &h); err != nil {
		t.Fatal(err)
	}
	return h
}

// writeBackup writes a backup.txt that names the plan in dir, and the Realtime
// Database dump it points to. override replaces or removes ("") single lines.
func writeBackup(t *testing.T, dir, state string, override ...string) {
	t.Helper()
	dump := filepath.Join(dir, "rtdb-dev.json")
	if err := os.WriteFile(dump, []byte(`{"companies":{}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	kv := map[string]string{
		planKey:                  planHeader(t, dir).CreatedAt.UTC().Format(time.RFC3339),
		"firestore_export":       "gs://some-bucket/backups/dev-reset-x",
		"firestore_operation":    "projects/" + projectID + "/databases/(default)/operations/op1",
		"firestore_export_state": state,
		"rtdb_backup":            dump,
	}
	for i := 0; i+1 < len(override); i += 2 {
		kv[override[i]] = override[i+1]
	}
	text := "Backup of dev.\n"
	for k, v := range kv {
		if v != "" {
			text += k + ": " + v + "\n"
		}
	}
	if err := os.WriteFile(filepath.Join(dir, backupFile), []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestReadPlanRefusals(t *testing.T) {
	now := time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)
	good := []line{
		{Kind: "firestore", Path: "dev_loans/L1", Decision: del, Rule: "x"},
		{Kind: "firestore", Path: "dev_users/U1", Decision: keep, Rule: "x"},
		{Kind: "rtdb", Path: "dev/companies/C1/report_summary", Decision: del, Rule: "x"},
	}
	fresh := header{Plan: planName, Project: projectID, CreatedAt: now.Add(-time.Hour), Lines: len(good)}

	cases := []struct {
		name   string
		h      header
		lines  []line
		refuse string // "" means the plan must load
	}{
		{"a fresh, valid plan", fresh, good, ""},
		{"older than two hours", header{planName, projectID, now.Add(-2*time.Hour - time.Second), len(good)}, good, "valid for"},
		{"dated in the future", header{planName, projectID, now.Add(time.Minute), len(good)}, good, "valid for"},
		{"made from production", header{planName, "loooans-prod", now.Add(-time.Hour), len(good)}, good, "loooans-prod"},
		{"no header", header{"", projectID, now.Add(-time.Hour), len(good)}, good, "header"},
		{"truncated", header{planName, projectID, now.Add(-time.Hour), len(good) + 1}, good, "header says"},
		{"a staging document", fresh, []line{good[0], {Kind: "firestore", Path: "stg_loans/L1", Decision: del}, good[2]}, "stg_loans"},
		{"an unprefixed document", fresh, []line{good[0], {Kind: "firestore", Path: "loans/L1", Decision: del}, good[2]}, "loans/L1"},
		{"a staging node", fresh, []line{good[0], good[1], {Kind: "rtdb", Path: "stg/companies/C1/report_summary", Decision: del}}, "stg/companies"},
		{"the same path twice", fresh, []line{good[0], good[0], good[2]}, "repeats"},
	}
	for _, tc := range cases {
		dir := t.TempDir()
		writePlan(t, dir, tc.h, tc.lines)
		_, lines, err := readPlan(dir, projectID, now)
		switch {
		case tc.refuse == "" && (err != nil || len(lines) != len(tc.lines)):
			t.Errorf("%s: got %d lines and error %v", tc.name, len(lines), err)
		case tc.refuse != "" && (err == nil || !strings.Contains(err.Error(), tc.refuse)):
			t.Errorf("%s: want a refusal mentioning %q, got %v", tc.name, tc.refuse, err)
		}
	}
}

// Review finding 5: `rtdb_backup: /` and `firestore_export: gs://` passed.
func TestCheckBackup(t *testing.T) {
	now := time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)
	dir := t.TempDir()
	writePlan(t, dir, header{Plan: planName, Project: projectID, CreatedAt: now, Lines: 0}, nil)
	h := planHeader(t, dir)
	if checkBackup(dir, h) == nil {
		t.Error("a directory without backup.txt was accepted")
	}
	writeBackup(t, dir, "SUCCESSFUL")
	if err := checkBackup(dir, h); err != nil {
		t.Fatalf("a complete backup.txt was refused: %v", err)
	}

	notJSON := filepath.Join(dir, "not-json.txt")
	if err := os.WriteFile(notJSON, []byte("Error: permission denied"), 0o600); err != nil {
		t.Fatal(err)
	}
	empty := filepath.Join(dir, "empty.json")
	if err := os.WriteFile(empty, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	refused := []struct{ name, key, value string }{
		{"an unfinished export", "firestore_export_state", "PROCESSING"},
		{"no export state", "firestore_export_state", ""},
		{"a root directory as the dump", "rtdb_backup", "/"},
		{"a directory as the dump", "rtdb_backup", dir},
		{"a missing dump", "rtdb_backup", filepath.Join(dir, "nope.json")},
		{"no dump line", "rtdb_backup", ""},
		{"an empty dump", "rtdb_backup", empty},
		{"a dump that is not JSON", "rtdb_backup", notJSON},
		{"an export path with no bucket", "firestore_export", "gs://"},
		{"an export path with no object prefix", "firestore_export", "gs://some-bucket"},
		{"an export path with an empty object prefix", "firestore_export", "gs://some-bucket/"},
		{"an export path that is not a bucket", "firestore_export", "/tmp/export"},
		{"no export line", "firestore_export", ""},
		{"an operation with no id", "firestore_operation", "projects/" + projectID + "/"},
		{"an operation of production", "firestore_operation", "projects/loooans-prod/databases/(default)/operations/op1"},
		{"no plan line", planKey, ""},
		{"the time of another plan", planKey, now.Add(-time.Hour).Format(time.RFC3339)},
		{"a directory name instead of the plan time", planKey, filepath.Base(dir)},
	}
	for _, tc := range refused {
		writeBackup(t, dir, "SUCCESSFUL", tc.key, tc.value)
		if checkBackup(dir, h) == nil {
			t.Errorf("%s was accepted", tc.name)
		}
	}
}

// runApply must refuse before it touches any client. The target here has nil
// clients, so reaching Firestore, the Realtime Database or Auth would panic.
func TestApplyRefusesBeforeTouchingAnything(t *testing.T) {
	now := time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)
	ctx := context.Background()
	dev := target{project: projectID}
	lines := []line{{Kind: "firestore", Path: "dev_loans/L1", Decision: del}}
	fresh := header{Plan: planName, Project: projectID, CreatedAt: now.Add(-time.Minute), Lines: 1}

	dir := t.TempDir()
	writePlan(t, dir, fresh, lines)
	writeBackup(t, dir, "SUCCESSFUL")
	for _, confirm := range []string{"", "yes", "DEV", "development", "dev "} {
		if err := runApply(ctx, dev, dir, confirm, now, io.Discard); err == nil || !strings.Contains(err.Error(), "-confirm dev") {
			t.Errorf("-confirm %q: want a refusal, got %v", confirm, err)
		}
	}
	if err := runApply(ctx, target{project: "loooans-prod"}, dir, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), "loooans-prod") {
		t.Errorf("production target: want a refusal, got %v", err)
	}
	if err := runApply(ctx, dev, dir, "dev", now.Add(3*time.Hour), io.Discard); err == nil || !strings.Contains(err.Error(), "valid for") {
		t.Errorf("stale plan: want a refusal, got %v", err)
	}

	noBackup := t.TempDir()
	writePlan(t, noBackup, fresh, lines)
	if err := runApply(ctx, dev, noBackup, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), backupFile) {
		t.Errorf("no backup.txt: want a refusal, got %v", err)
	}

	staging := t.TempDir()
	writePlan(t, staging, fresh, []line{{Kind: "firestore", Path: "stg_loans/L1", Decision: del}})
	writeBackup(t, staging, "SUCCESSFUL")
	if err := runApply(ctx, dev, staging, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), "stg_loans") {
		t.Errorf("staging line: want a refusal, got %v", err)
	}

	// Review finding 5: a backup.txt written for another plan.
	otherPlan := t.TempDir()
	writePlan(t, otherPlan, fresh, lines)
	writeBackup(t, otherPlan, "SUCCESSFUL", planKey, now.Add(-time.Hour).Format(time.RFC3339))
	if err := runApply(ctx, dev, otherPlan, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), planKey) {
		t.Errorf("backup.txt of another plan: want a refusal, got %v", err)
	}

	// Review finding 1: a directory is applied once.
	applied := t.TempDir()
	writePlan(t, applied, fresh, lines)
	writeBackup(t, applied, "SUCCESSFUL")
	if err := os.WriteFile(filepath.Join(applied, appliedFile), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := runApply(ctx, dev, applied, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), appliedFile) {
		t.Errorf("already applied: want a refusal, got %v", err)
	}

	// An apply that did not finish: the same plan may run again, a changed one may not.
	unfinished := t.TempDir()
	writePlan(t, unfinished, fresh, lines)
	writeBackup(t, unfinished, "SUCCESSFUL")
	hash, err := planHash(unfinished)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeMarker(unfinished, startedFile, hash, now, ""); err != nil {
		t.Fatal(err)
	}
	if err := checkMarkers(unfinished, hash); err != nil {
		t.Errorf("rerun of the same plan after an unfinished apply was refused: %v", err)
	}
	writePlan(t, unfinished, fresh, []line{{Kind: "firestore", Path: "dev_users/U1", Decision: del}})
	if err := runApply(ctx, dev, unfinished, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), "did not finish") {
		t.Errorf("changed plan after an unfinished apply: want a refusal, got %v", err)
	}
}

// Review finding 6: an empty Auth list with no error planned every user for
// deletion. The target has nil clients: reaching Firestore would panic.
func TestRefusesAnEmptyAuthList(t *testing.T) {
	now := time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)
	ctx := context.Background()
	noUsers := target{project: projectID, authUsers: func(context.Context) (map[string]string, error) { return map[string]string{}, nil }}

	dir := filepath.Join(t.TempDir(), "plan")
	if err := runPlan(ctx, noUsers, dir, now, io.Discard); err == nil || !strings.Contains(err.Error(), "zero users") {
		t.Errorf("plan with an empty Auth list: want a refusal, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, planFile)); err == nil {
		t.Error("a plan was written although Auth returned zero users")
	}

	applyDir := t.TempDir()
	writePlan(t, applyDir, header{Plan: planName, Project: projectID, CreatedAt: now, Lines: 1}, []line{{Kind: "firestore", Path: "dev_users/U1", Decision: del}})
	writeBackup(t, applyDir, "SUCCESSFUL")
	if err := runApply(ctx, noUsers, applyDir, "dev", now, io.Discard); err == nil || !strings.Contains(err.Error(), "zero users") {
		t.Errorf("apply with an empty Auth list: want a refusal, got %v", err)
	}
}

// Review finding 2: `dev/companies/%2Ejson?` passed and deleted all of
// dev/companies. Every segment must match ^[A-Za-z0-9_-]+$.
func TestUnsafeSegmentsAreRefused(t *testing.T) {
	refuse := []line{
		{Kind: "rtdb", Path: "dev/companies/%2Ejson?", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/%2E%2E%2F%2E%2E%2Fstg", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/.json", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1.json", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1?shallow=true", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C 1", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report_summary?x=1", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1/report%5Fsummary", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1#", Decision: del},
		{Kind: "rtdb", Path: "dev/companies/C1.json", Decision: keep},
		{Kind: "rtdb", Path: "dev/%2E%2E/stg", Decision: keep},
		{Kind: "rtdb", Path: "dev/typing/R1", Decision: keep},        // not a shape the planner lists
		{Kind: "rtdb", Path: "dev/companies/C1/a/b", Decision: keep}, // too deep
		{Kind: "firestore", Path: "dev_users/U%2F1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U 1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U.1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1?x", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1:x", Decision: del},
		{Kind: "firestore", Path: "dev_us.ers/U1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1/dev ices/D1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U1/devices/Dé1", Decision: del},
		{Kind: "firestore", Path: "dev_users/U.1", Decision: keep},
	}
	for _, l := range refuse {
		if err := checkLine(l); err == nil {
			t.Errorf("%s %s %q was accepted", l.Kind, l.Decision, l.Path)
		}
	}

	// The planner refuses too: a plan that -apply would refuse is never written.
	c := classify([]doc{{path: "dev_loans/L1"}, {path: "dev_loans/L 2"}, {path: "dev_users/U.1"}}, map[string]string{"U1": ""})
	if refused := checkLines(c.lines); len(refused) != 2 {
		t.Errorf("checkLines refused %d of the planner's lines, want 2: %v", len(refused), refused)
	}
	nodes := classifyRTDB([]string{"companies"}, map[string][]string{"%2Ejson?": nil, "C1": {"report_summary"}}, nil, map[string]bool{"%2Ejson?": true})
	if refused := checkLines(nodes); len(refused) != 1 || !strings.Contains(refused[0], "%2Ejson?") {
		t.Errorf("checkLines on an unsafe company key: %v", refused)
	}
}

// Review finding 4: a wrong-typed company_id counted as absent, so the
// company of an Auth user, its address, bank details, client and Realtime
// Database node were planned for deletion.
func TestUnreadableReferencesKeep(t *testing.T) {
	// newDoc: a string is read, null and a missing field are absent, anything else is unreadable.
	d := newDoc("dev_users/U1", map[string]any{"id": "U1", "company_id": int64(123), "email_address": 5, "data_id": nil},
		[]string{"id", "company_id", "email_address", "data_id", "user_id"})
	if d.fields["id"] != "U1" || len(d.fields) != 1 || strings.Join(d.bad, ",") != "company_id,email_address" || strings.Join(d.badRefs(), ",") != "company_id" {
		t.Fatalf("newDoc: fields %v, bad %v, badRefs %v", d.fields, d.bad, d.badRefs())
	}

	auth := map[string]string{"U1": ""}
	docs := func(u1 doc) []doc {
		return []doc{
			u1,
			{path: "dev_users/CL1", fields: map[string]string{"id": "CL1", "company_id": "C1"}},
			{path: "dev_companies/C1"},
			{path: "dev_companies/C2"},
			{path: "dev_address/A1", fields: map[string]string{"data_id": "C1"}},
			{path: "dev_address/A2", fields: map[string]string{"data_id": "CL1"}},
			{path: "dev_bank_details/B1", fields: map[string]string{"dataId": "C1"}},
			{path: "dev_loans/L1"},
		}
	}
	shape := map[string][]string{"C1": {"loans", "report_summary", "something_else"}}

	// Control: with no company_id at all, nothing references C1 and it goes with what depends on it.
	c := classify(docs(doc{path: "dev_users/U1", fields: map[string]string{"id": "U1"}}), auth)
	got := decisions(append(c.lines, classifyRTDB([]string{"companies"}, shape, c.keptCompanies, c.deletedCompanies)...))
	for _, path := range []string{"dev_companies/C1", "dev_users/CL1", "dev_address/A1", "dev_address/A2", "dev_bank_details/B1", "dev/companies/C1"} {
		if got[path] != del {
			t.Errorf("control, %s: got %q, want delete", path, got[path])
		}
	}

	// The same documents, but the Auth user's company_id is a number.
	c = classify(docs(doc{path: "dev_users/U1", fields: map[string]string{"id": "U1"}, bad: []string{"company_id"}}), auth)
	got = decisions(append(c.lines, classifyRTDB([]string{"companies"}, shape, c.keptCompanies, c.deletedCompanies)...))
	want := map[string]string{
		"dev_users/U1": keep, "dev_users/CL1": keep, "dev_companies/C1": keep, "dev_companies/C2": keep,
		"dev_address/A1": keep, "dev_address/A2": keep, "dev_bank_details/B1": keep, "dev_loans/L1": del,
		"dev/companies/C1/something_else": keep, "dev/companies/C1/report_summary": del, "dev/companies/C1/loans": del,
	}
	if len(got) != len(want) {
		t.Errorf("got %d lines, want %d: %v", len(got), len(want), got)
	}
	for path, decision := range want {
		if got[path] != decision {
			t.Errorf("unreadable company_id, %s: got %q, want %q", path, got[path], decision)
		}
	}
	if !c.companiesInDoubt || strings.Join(c.unreadable, ";") != "dev_users/U1 (company_id)" {
		t.Errorf("companiesInDoubt %v, unreadable %v", c.companiesInDoubt, c.unreadable)
	}

	// A user without an Auth account and an owned document with unreadable
	// references are kept with what they own; they do not make a company kept.
	c = classify([]doc{
		{path: "dev_users/U1", fields: map[string]string{"id": "U1"}},
		{path: "dev_users/X1", bad: []string{"company_id"}},
		{path: "dev_users/X1/devices/D1"},
		{path: "dev_users/X2", bad: []string{"email_address"}}, // not a reference: still deleted
		{path: "dev_address/AX", fields: map[string]string{"data_id": "X1"}},
		{path: "dev_address/AB", bad: []string{"data_id"}},
		{path: "dev_address/AB/history/H1"},
		{path: "dev_bank_details/BB", fields: map[string]string{"data_id": "GONE"}, bad: []string{"dataId"}},
		{path: "dev_companies/C2"},
	}, auth)
	got = decisions(c.lines)
	want = map[string]string{
		"dev_users/U1": keep, "dev_users/X1": keep, "dev_users/X1/devices/D1": keep, "dev_users/X2": del,
		"dev_address/AX": keep, "dev_address/AB": keep, "dev_address/AB/history/H1": keep, "dev_bank_details/BB": keep,
		"dev_companies/C2": del,
	}
	for path, decision := range want {
		if got[path] != decision {
			t.Errorf("unreadable user or owner field, %s: got %q, want %q", path, got[path], decision)
		}
	}
	if c.companiesInDoubt || strings.Join(c.unreadable, ";") != "dev_address/AB (data_id);dev_bank_details/BB (dataId);dev_users/X1 (company_id)" {
		t.Errorf("companiesInDoubt %v, unreadable %v", c.companiesInDoubt, c.unreadable)
	}
}

// Review finding 3: apply checked where a delete may go but not whether the
// rules still say delete. A kept line flipped to delete was deleted.
func TestRecheckRefusesLinesThatNoLongerClassifyAsDelete(t *testing.T) {
	s := snapshot{
		authUsers: map[string]string{"U1": "", "U2": ""},
		docs: []doc{ // sorted by path, as walkFirestore returns them
			{path: "dev_companies/C1"},
			{path: "dev_loans/L1"},
			{path: "dev_mystery/M1"},
			{path: "dev_users/CL1", fields: map[string]string{"company_id": "C1"}},
			{path: "dev_users/U1", fields: map[string]string{"company_id": "C1"}},
			{path: "dev_users/U2"},
		},
		rtdbTop:   []string{"companies", "typing"},
		companies: map[string][]string{"C1": {"loans", "report_summary", "something_else"}},
	}
	planned := []line{
		{Kind: "firestore", Path: "dev_loans/L1", Decision: del},                // still delete
		{Kind: "firestore", Path: "dev_loans/L9", Decision: del},                // already gone
		{Kind: "firestore", Path: "dev_mystery/M1", Decision: del},              // unclassified: a flipped line
		{Kind: "firestore", Path: "dev_users/CL1", Decision: del},               // kept client: a flipped line
		{Kind: "firestore", Path: "dev_users/U2", Decision: del},                // registered in Auth since the plan
		{Kind: "firestore", Path: "dev_users/U1", Decision: keep},               // keep lines are not looked at
		{Kind: "rtdb", Path: "dev/companies/C1/report_summary", Decision: del},  // still delete
		{Kind: "rtdb", Path: "dev/companies/C1/report_events", Decision: del},   // already gone
		{Kind: "rtdb", Path: "dev/companies/C1", Decision: del},                 // whole node of a company that is kept now
		{Kind: "rtdb", Path: "dev/companies/C7", Decision: del},                 // already gone
		{Kind: "rtdb", Path: "dev/companies/C1/something_else", Decision: keep}, // keep lines are not looked at
	}
	todo, gone, stale := recheck(planned, s)
	if got := strings.Join(stale, " "); got != "dev_mystery/M1 dev_users/CL1 dev_users/U2 dev/companies/C1" {
		t.Errorf("stale = %q", got)
	}
	var paths []string
	for _, l := range todo {
		paths = append(paths, l.Path)
	}
	if got := strings.Join(paths, " "); got != "dev_loans/L1 dev/companies/C1/report_summary" {
		t.Errorf("todo = %q", got)
	}
	if gone != 3 {
		t.Errorf("gone = %d, want 3", gone)
	}
}
