package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"text/tabwriter"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/db"
	"google.golang.org/api/iterator"
)

const (
	planName    = "dev_reset"
	planFile    = "plan.jsonl"
	summaryFile = "summary.txt"
	backupFile  = "backup.txt"
	maxPlanAge  = 2 * time.Hour
)

// target is the Firestore database, Realtime Database and Auth user list the
// tool works on. main always builds it with realTarget, which hard-codes the
// dev project. The emulator test builds its own with emulator set. No flag,
// environment variable or argument selects it.
type target struct {
	project  string
	emulator bool
	fs       *firestore.Client
	rtdb     *db.Client
	// authUsers returns every Firebase Auth uid with its lower-case email.
	authUsers func(context.Context) (map[string]string, error)
}

func (t target) check() error {
	if !t.emulator {
		return checkProject(t.project)
	}
	if !strings.HasPrefix(t.project, "demo-") || os.Getenv("FIRESTORE_EMULATOR_HOST") == "" || os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		return errors.New("an emulator target needs a demo- project and both emulator hosts set")
	}
	return nil
}

// header is the first line of plan.jsonl.
type header struct {
	Plan      string    `json:"plan"`
	Project   string    `json:"project"`
	CreatedAt time.Time `json:"created_at"`
	Lines     int       `json:"lines"`
}

// snapshot is one read of dev: document paths with a few id fields, the Auth
// uid list, and the key shape of dev/ in the Realtime Database.
type snapshot struct {
	docs      []doc
	authUsers map[string]string
	rtdbTop   []string
	companies map[string][]string
}

func read(ctx context.Context, t target) (snapshot, error) {
	var s snapshot
	var err error
	if s.authUsers, err = t.authUsers(ctx); err != nil {
		return s, fmt.Errorf("list Firebase Auth users: %w", err)
	}
	if s.docs, err = walkFirestore(ctx, t.fs); err != nil {
		return s, err
	}
	if s.rtdbTop, err = shallowKeys(ctx, t.rtdb, rtdbRoot); err != nil {
		return s, err
	}
	ids, err := shallowKeys(ctx, t.rtdb, rtdbRoot+"/companies")
	if err != nil {
		return s, err
	}
	s.companies = map[string][]string{}
	for _, id := range ids {
		if s.companies[id], err = shallowKeys(ctx, t.rtdb, rtdbRoot+"/companies/"+id); err != nil {
			return s, err
		}
	}
	return s, nil
}

func (s snapshot) plan() (classification, []line) {
	c := classify(s.docs, s.authUsers)
	return c, append(c.lines, classifyRTDB(s.rtdbTop, s.companies, c.deletedCompanies)...)
}

// shallowKeys returns the child keys of a Realtime Database node without
// downloading its contents.
func shallowKeys(ctx context.Context, rtdb *db.Client, path string) ([]string, error) {
	var v any
	if err := rtdb.NewRef(path).GetShallow(ctx, &v); err != nil {
		return nil, fmt.Errorf("read the shape of %s: %w", path, err)
	}
	m, _ := v.(map[string]any)
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys, nil
}

type walker struct {
	ctx  context.Context
	sem  chan struct{} // bounds concurrent RPCs
	wg   sync.WaitGroup
	mu   sync.Mutex
	docs []doc
	err  error
}

func (w *walker) fail(err error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.err == nil {
		w.err = err
	}
}

// walkFirestore lists every document of every root collection whose id starts
// with dev_, and of every subcollection below them. Other root collections are
// never opened.
func walkFirestore(ctx context.Context, fs *firestore.Client) ([]doc, error) {
	roots, err := fs.Collections(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("list root collections: %w", err)
	}
	w := &walker{ctx: ctx, sem: make(chan struct{}, 24)}
	for _, col := range roots {
		if strings.HasPrefix(col.ID, collectionPrefix) && col.ID != collectionPrefix {
			w.wg.Add(1)
			go w.collection(col, selectFields(strings.TrimPrefix(col.ID, collectionPrefix)))
		}
	}
	w.wg.Wait()
	sort.Slice(w.docs, func(i, j int) bool { return w.docs[i].path < w.docs[j].path })
	return w.docs, w.err
}

func relPath(full string) string {
	_, rel, _ := strings.Cut(full, "/documents/")
	return rel
}

func (w *walker) collection(col *firestore.CollectionRef, fields []string) {
	defer w.wg.Done()
	w.sem <- struct{}{}
	docs, refs, err := listCollection(w.ctx, col, fields)
	<-w.sem
	if err != nil {
		w.fail(fmt.Errorf("list %s: %w", relPath(col.Path), err))
		return
	}
	w.mu.Lock()
	w.docs = append(w.docs, docs...)
	w.mu.Unlock()

	for _, ref := range refs {
		w.sem <- struct{}{}
		w.wg.Add(1)
		go func() {
			defer w.wg.Done()
			subs, err := ref.Collections(w.ctx).GetAll()
			<-w.sem
			if err != nil {
				w.fail(fmt.Errorf("list subcollections of %s: %w", relPath(ref.Path), err))
				return
			}
			for _, sub := range subs {
				w.wg.Add(1)
				go w.collection(sub, nil)
			}
		}()
	}
}

// listCollection returns the existing documents (with only the named fields
// loaded) and every document reference. The references include documents that
// do not exist but still have subcollections, so those are walked too.
func listCollection(ctx context.Context, col *firestore.CollectionRef, fields []string) ([]doc, []*firestore.DocumentRef, error) {
	var docs []doc
	it := col.Select(fields...).Documents(ctx)
	defer it.Stop()
	for {
		snap, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, nil, err
		}
		d := doc{path: relPath(snap.Ref.Path)}
		for _, f := range fields {
			if v, ok := snap.Data()[f].(string); ok && v != "" {
				if d.fields == nil {
					d.fields = map[string]string{}
				}
				d.fields[f] = v
			}
		}
		docs = append(docs, d)
	}
	refs, err := col.DocumentRefs(ctx).GetAll()
	return docs, refs, err
}

// runPlan reads dev and writes plan.jsonl and summary.txt. It writes nothing
// to Firestore, the Realtime Database or Auth.
func runPlan(ctx context.Context, t target, dir string, now time.Time, out io.Writer) error {
	if err := t.check(); err != nil {
		return err
	}
	planPath := filepath.Join(dir, planFile)
	if _, err := os.Stat(planPath); err == nil {
		return fmt.Errorf("%s exists: a plan directory is used once, so that a plan and its backup stay paired; pick a new directory", planPath)
	}
	s, err := read(ctx, t)
	if err != nil {
		return err
	}
	c, lines := s.plan()

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	f, err := os.OpenFile(planPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	buf := bufio.NewWriter(f)
	enc := json.NewEncoder(buf)
	if err := enc.Encode(header{Plan: planName, Project: t.project, CreatedAt: now.UTC(), Lines: len(lines)}); err != nil {
		return err
	}
	for _, l := range lines {
		if err := enc.Encode(l); err != nil {
			return err
		}
	}
	if err := errors.Join(buf.Flush(), f.Close()); err != nil {
		return err
	}

	summary := summarize("dev reset PLAN. Nothing has been deleted.", t.project, now, s, c, lines)
	if err := os.WriteFile(filepath.Join(dir, summaryFile), []byte(summary), 0o600); err != nil {
		return err
	}
	_, err = fmt.Fprint(out, summary)
	return err
}

// readPlan loads plan.jsonl and re-validates all of it: the header, the age,
// and every line. One bad line refuses the whole plan.
func readPlan(dir, project string, now time.Time) ([]line, error) {
	f, err := os.Open(filepath.Join(dir, planFile))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)

	var h header
	if !sc.Scan() || json.Unmarshal(sc.Bytes(), &h) != nil || h.Plan != planName {
		return nil, fmt.Errorf("%s does not start with a %s header", planFile, planName)
	}
	if h.Project != project {
		return nil, fmt.Errorf("refusing: the plan was made from project %q, the target is %q", h.Project, project)
	}
	if age := now.Sub(h.CreatedAt); age < 0 || age > maxPlanAge {
		return nil, fmt.Errorf("refusing: the plan was made at %s; a plan is valid for %s, make a new one", h.CreatedAt.Format(time.RFC3339), maxPlanAge)
	}

	var lines []line
	seen := map[string]bool{}
	for n := 2; sc.Scan(); n++ {
		var l line
		if err := json.Unmarshal(sc.Bytes(), &l); err != nil {
			return nil, fmt.Errorf("%s line %d: %w", planFile, n, err)
		}
		if err := checkLine(l); err != nil {
			return nil, fmt.Errorf("refusing: %s line %d: %w", planFile, n, err)
		}
		if seen[l.Kind+" "+l.Path] {
			return nil, fmt.Errorf("refusing: %s line %d repeats %s", planFile, n, l.Path)
		}
		seen[l.Kind+" "+l.Path] = true
		lines = append(lines, l)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(lines) != h.Lines {
		return nil, fmt.Errorf("refusing: %s has %d lines, its header says %d", planFile, len(lines), h.Lines)
	}
	return lines, nil
}

// checkBackup refuses unless backup.txt names a finished Firestore export of
// the dev project and an existing, non-empty Realtime Database backup file.
func checkBackup(dir string) error {
	raw, err := os.ReadFile(filepath.Join(dir, backupFile))
	if err != nil {
		return fmt.Errorf("refusing: no %s next to the plan, take the backups first: %w", backupFile, err)
	}
	kv := map[string]string{}
	for _, l := range strings.Split(string(raw), "\n") {
		if k, v, ok := strings.Cut(l, ":"); ok {
			kv[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	switch {
	case !strings.HasPrefix(kv["firestore_export"], "gs://"):
		return fmt.Errorf("refusing: %s has no firestore_export: gs://... line", backupFile)
	case !strings.HasPrefix(kv["firestore_operation"], "projects/"+projectID+"/"):
		return fmt.Errorf("refusing: %s has no firestore_operation of project %s", backupFile, projectID)
	case kv["firestore_export_state"] != "SUCCESSFUL":
		return fmt.Errorf("refusing: %s does not say firestore_export_state: SUCCESSFUL", backupFile)
	}
	if st, err := os.Stat(kv["rtdb_backup"]); err != nil || st.Size() == 0 {
		return fmt.Errorf("refusing: the rtdb_backup file named in %s is missing or empty", backupFile)
	}
	return nil
}

// runApply deletes exactly the paths marked delete in the plan, then reads dev
// again and prints what remains.
func runApply(ctx context.Context, t target, dir, confirm string, now time.Time, out io.Writer) error {
	if confirm != "dev" {
		return errors.New("refusing to delete: add the literal argument -confirm dev")
	}
	if err := t.check(); err != nil {
		return err
	}
	lines, err := readPlan(dir, t.project, now)
	if err != nil {
		return err
	}
	if err := checkBackup(dir); err != nil {
		return err
	}
	// The owner's constraint, checked against Auth as it is now, not as it was
	// when the plan was made.
	authUsers, err := t.authUsers(ctx)
	if err != nil {
		return fmt.Errorf("list Firebase Auth users: %w", err)
	}
	var docPaths, nodePaths []string
	planned := map[string]bool{}
	for _, l := range lines {
		if l.Decision != del {
			continue
		}
		planned[l.Kind+" "+l.Path] = true
		if l.Kind == "rtdb" {
			nodePaths = append(nodePaths, l.Path)
			continue
		}
		segs := strings.Split(l.Path, "/")
		if _, registered := authUsers[segs[1]]; registered && segs[0] == collectionPrefix+"users" {
			return fmt.Errorf("refusing: %s is marked delete but its uid is in Firebase Auth now; make a new plan", l.Path)
		}
		docPaths = append(docPaths, l.Path)
	}

	fmt.Fprintf(out, "deleting %d Firestore documents and %d Realtime Database nodes in %s\n", len(docPaths), len(nodePaths), t.project)
	failed := 0
	bw := t.fs.BulkWriter(ctx)
	jobs := make([]*firestore.BulkWriterJob, len(docPaths))
	for i, p := range docPaths {
		if jobs[i], err = bw.Delete(t.fs.Doc(p)); err != nil {
			failed++
			fmt.Fprintf(out, "FAILED %s: %v\n", p, err)
		}
	}
	bw.End()
	for i, job := range jobs {
		if job == nil {
			continue
		}
		if _, err := job.Results(); err != nil {
			failed++
			fmt.Fprintf(out, "FAILED %s: %v\n", docPaths[i], err)
		}
	}
	for _, p := range nodePaths {
		if err := t.rtdb.NewRef(p).Delete(ctx); err != nil {
			failed++
			fmt.Fprintf(out, "FAILED %s: %v\n", p, err)
		}
	}

	s, err := read(ctx, t)
	if err != nil {
		return fmt.Errorf("the deletes ran (%d failed) but reading what remains failed: %w", failed, err)
	}
	c, remaining := s.plan()
	left := 0
	for _, l := range remaining {
		if planned[l.Kind+" "+l.Path] {
			left++
			fmt.Fprintf(out, "STILL PRESENT %s\n", l.Path)
		}
	}
	fmt.Fprint(out, summarize("dev reset APPLIED. What remains in dev:", t.project, now, s, c, remaining))
	if failed > 0 || left > 0 {
		return fmt.Errorf("%d deletes failed and %d planned paths are still present", failed, left)
	}
	return nil
}

type tally struct{ total, keep, del int }

// collectionPattern turns dev_users/U1/devices/D1 into dev_users/*/devices.
func collectionPattern(path string) string {
	segs := strings.Split(path, "/")
	for i := 1; i < len(segs)-1; i += 2 {
		segs[i] = "*"
	}
	return strings.Join(segs[:len(segs)-1], "/")
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func list(items []string) string {
	if len(items) == 0 {
		return "none"
	}
	return strings.Join(items, ", ")
}

// summarize renders summary.txt: paths, ids and counts only, never contents.
func summarize(title, project string, at time.Time, s snapshot, c classification, lines []line) string {
	tallies := map[string]*tally{}
	exportIDs := map[string]bool{}
	noOwner := map[string]int{}
	var keptUserDocs, keptCompanyDocs, nodesDeleted, nodesKept []string
	deletedUsers, deletedCompanyDocs := 0, 0
	for _, l := range lines {
		if l.Kind == "rtdb" {
			if l.Decision == del {
				nodesDeleted = append(nodesDeleted, l.Path+"   ("+l.Rule+")")
			} else {
				nodesKept = append(nodesKept, l.Path)
			}
			continue
		}
		segs := strings.Split(l.Path, "/")
		for i := 0; i < len(segs); i += 2 {
			exportIDs[segs[i]] = true
		}
		p := collectionPattern(l.Path)
		if tallies[p] == nil {
			tallies[p] = &tally{}
		}
		tallies[p].total++
		if l.Decision == keep {
			tallies[p].keep++
		} else {
			tallies[p].del++
		}
		if strings.HasPrefix(l.Rule, "owned: no owner field") {
			noOwner[p]++
		}
		if len(segs) != 2 {
			continue
		}
		switch {
		case segs[0] == collectionPrefix+"users" && l.Decision == keep:
			keptUserDocs = append(keptUserDocs, segs[1])
		case segs[0] == collectionPrefix+"users":
			deletedUsers++
		case segs[0] == collectionPrefix+"companies" && l.Decision == keep:
			keptCompanyDocs = append(keptCompanyDocs, segs[1])
		case segs[0] == collectionPrefix+"companies":
			deletedCompanyDocs++
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, "%s\nproject %s, Firestore prefix %s, Realtime Database root %s/, read at %s\nThis file holds paths, ids and counts only.\n\n",
		title, project, collectionPrefix, rtdbRoot, at.UTC().Format(time.RFC3339))

	fmt.Fprintf(&b, "FIREBASE AUTH (one pool, shared by dev and staging; never modified)\n  users: %d\n\n", len(s.authUsers))

	b.WriteString("FIRESTORE\n")
	tw := tabwriter.NewWriter(&b, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "  collection\ttotal\tkeep\tdelete\trule")
	var sum tally
	var unclassified []string
	live := map[string]bool{}
	for _, p := range sortedKeys(tallies) {
		t := tallies[p]
		sum.total, sum.keep, sum.del = sum.total+t.total, sum.keep+t.keep, sum.del+t.del
		why := "follows its top-level document"
		if !strings.Contains(p, "/") {
			live[strings.TrimPrefix(p, collectionPrefix)] = true
			if r, ok := ruleFor(strings.TrimPrefix(p, collectionPrefix)); ok {
				why = r.why
			} else {
				why = "UNCLASSIFIED: the code never mentions it, kept in full"
				unclassified = append(unclassified, p)
			}
		}
		fmt.Fprintf(tw, "  %s\t%d\t%d\t%d\t%s\n", p, t.total, t.keep, t.del, why)
	}
	fmt.Fprintf(tw, "  TOTAL\t%d\t%d\t%d\t\n", sum.total, sum.keep, sum.del)
	tw.Flush()

	var absent []string
	for _, r := range rules {
		if !live[r.collection] {
			absent = append(absent, collectionPrefix+r.collection)
		}
	}
	var danglingCompanies []string
	for _, id := range sortedKeys(c.keptCompanies) {
		if !slices.Contains(keptCompanyDocs, id) {
			danglingCompanies = append(danglingCompanies, id)
		}
	}
	fmt.Fprintf(&b, "\n  unclassified live collections (the code never mentions them; kept in full): %s\n", list(unclassified))
	fmt.Fprintf(&b, "  collections in the rule table with no live documents: %s\n", list(absent))
	for _, p := range sortedKeys(noOwner) {
		fmt.Fprintf(&b, "  %s: %d documents carry no owner field and are kept in doubt\n", p, noOwner[p])
	}
	fmt.Fprintf(&b, "\n  user documents kept: %d, deleted: %d\n", len(keptUserDocs), deletedUsers)
	fmt.Fprintf(&b, "  Auth users with no %susers document: %d\n", collectionPrefix, len(s.authUsers)-len(keptUserDocs))
	fmt.Fprintf(&b, "  deleted user documents whose email address belongs to a registered Auth user under another uid: %d\n", c.emailOverlap)
	fmt.Fprintf(&b, "  kept user ids: %s\n", list(keptUserDocs))
	fmt.Fprintf(&b, "\n  company documents kept: %d, deleted: %d\n", len(keptCompanyDocs), deletedCompanyDocs)
	fmt.Fprintf(&b, "  kept company ids: %s\n", list(keptCompanyDocs))
	fmt.Fprintf(&b, "  company ids that kept users reference but that have no company document: %s\n", list(danglingCompanies))

	fmt.Fprintf(&b, "\nREALTIME DATABASE (%s/)\n  nodes to delete: %d\n", rtdbRoot, len(nodesDeleted))
	for _, p := range nodesDeleted {
		fmt.Fprintf(&b, "    %s\n", p)
	}
	fmt.Fprintf(&b, "  nodes kept: %d\n", len(nodesKept))
	for _, p := range nodesKept {
		fmt.Fprintf(&b, "    %s\n", p)
	}

	fmt.Fprintf(&b, "\nCOLLECTION IDS FOR THE MANAGED EXPORT (root and subcollection ids)\n  %s\n", strings.Join(sortedKeys(exportIDs), ","))
	return b.String()
}
