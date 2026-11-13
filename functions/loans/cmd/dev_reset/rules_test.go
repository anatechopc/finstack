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

func writeBackup(t *testing.T, dir, state string) {
	t.Helper()
	dump := filepath.Join(dir, "rtdb-dev.json")
	if err := os.WriteFile(dump, []byte(`{"companies":{}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	text := "firestore_export: gs://bucket/backups/dev-reset-x\n" +
		"firestore_operation: projects/" + projectID + "/databases/(default)/operations/op1\n" +
		"firestore_export_state: " + state + "\n" +
		"rtdb_backup: " + dump + "\n"
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
		lines, err := readPlan(dir, projectID, now)
		switch {
		case tc.refuse == "" && (err != nil || len(lines) != len(tc.lines)):
			t.Errorf("%s: got %d lines and error %v", tc.name, len(lines), err)
		case tc.refuse != "" && (err == nil || !strings.Contains(err.Error(), tc.refuse)):
			t.Errorf("%s: want a refusal mentioning %q, got %v", tc.name, tc.refuse, err)
		}
	}
}

func TestCheckBackup(t *testing.T) {
	dir := t.TempDir()
	if checkBackup(dir) == nil {
		t.Error("a directory without backup.txt was accepted")
	}
	writeBackup(t, dir, "PROCESSING")
	if checkBackup(dir) == nil {
		t.Error("an unfinished export was accepted")
	}
	writeBackup(t, dir, "SUCCESSFUL")
	if err := checkBackup(dir); err != nil {
		t.Errorf("a complete backup.txt was refused: %v", err)
	}
	if err := os.Truncate(filepath.Join(dir, "rtdb-dev.json"), 0); err != nil {
		t.Fatal(err)
	}
	if checkBackup(dir) == nil {
		t.Error("an empty Realtime Database backup was accepted")
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
}
