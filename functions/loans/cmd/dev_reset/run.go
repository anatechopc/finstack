package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
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
	startedFile = "apply-started.txt"
	appliedFile = "applied.txt"
	planKey     = "plan_created_at" // the line of backup.txt that names its plan
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
	// An empty list with no error would classify every user as unregistered.
	// The dev project has hundreds of Auth users, so zero means a wrong or
	// broken listing, not an empty pool.
	if len(s.authUsers) == 0 {
		return s, errors.New("refusing: Firebase Auth returned zero users; every user document would be planned for deletion")
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
		// A key outside the safe characters is never put into a request path.
		// It stays in the snapshot, and checkLine then refuses the plan.
		if !safeSegment.MatchString(id) {
			s.companies[id] = nil
			continue
		}
		if s.companies[id], err = shallowKeys(ctx, t.rtdb, rtdbRoot+"/companies/"+id); err != nil {
			return s, err
		}
	}
	return s, nil
}

func (s snapshot) plan() (classification, []line) {
	c := classify(s.docs, s.authUsers)
	return c, append(c.lines, classifyRTDB(s.rtdbTop, s.companies, c.keptCompanies, c.deletedCompanies)...)
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
		docs = append(docs, newDoc(relPath(snap.Ref.Path), snap.Data(), fields))
	}
	refs, err := col.DocumentRefs(ctx).GetAll()
	return docs, refs, err
}

// newDoc keeps only the named fields of a document's data: a string value as
// it is, null or a missing field as absent, anything else as unreadable.
func newDoc(path string, data map[string]any, fields []string) doc {
	d := doc{path: path}
	for _, f := range fields {
		switch v := data[f].(type) {
		case nil:
		case string:
			if v != "" {
				if d.fields == nil {
					d.fields = map[string]string{}
				}
				d.fields[f] = v
			}
		default:
			d.bad = append(d.bad, f)
		}
	}
	return d
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
	// A plan that -apply would refuse is not written at all.
	if refused := checkLines(lines); len(refused) > 0 {
		return fmt.Errorf("refusing to plan: dev holds %d paths this tool does not handle; rename or remove them by hand first:\n  %s",
			len(refused), strings.Join(refused[:min(len(refused), 20)], "\n  "))
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	f, err := os.OpenFile(planPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	// Whole seconds, so that the time can be copied into backup.txt by hand.
	h := header{Plan: planName, Project: t.project, CreatedAt: now.UTC().Truncate(time.Second), Lines: len(lines)}
	buf := bufio.NewWriter(f)
	enc := json.NewEncoder(buf)
	if err := enc.Encode(h); err != nil {
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

	summary := summarize("dev reset PLAN. Nothing has been deleted.", t.project, h.CreatedAt, s, c, lines) +
		fmt.Sprintf("\nBACKUP.TXT must name this plan with the line\n  %s: %s\n", planKey, h.CreatedAt.Format(time.RFC3339))
	if err := os.WriteFile(filepath.Join(dir, summaryFile), []byte(summary), 0o600); err != nil {
		return err
	}
	_, err = fmt.Fprint(out, summary)
	return err
}

// readPlan loads plan.jsonl and re-validates all of it: the header, the age,
// and every line. One bad line refuses the whole plan.
func readPlan(dir, project string, now time.Time) (header, []line, error) {
	var h header
	f, err := os.Open(filepath.Join(dir, planFile))
	if err != nil {
		return h, nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)

	if !sc.Scan() || json.Unmarshal(sc.Bytes(), &h) != nil || h.Plan != planName {
		return h, nil, fmt.Errorf("%s does not start with a %s header", planFile, planName)
	}
	if h.Project != project {
		return h, nil, fmt.Errorf("refusing: the plan was made from project %q, the target is %q", h.Project, project)
	}
	if age := now.Sub(h.CreatedAt); age < 0 || age > maxPlanAge {
		return h, nil, fmt.Errorf("refusing: the plan was made at %s; a plan is valid for %s, make a new one", h.CreatedAt.Format(time.RFC3339), maxPlanAge)
	}

	var lines []line
	seen := map[string]bool{}
	for n := 2; sc.Scan(); n++ {
		var l line
		if err := json.Unmarshal(sc.Bytes(), &l); err != nil {
			return h, nil, fmt.Errorf("%s line %d: %w", planFile, n, err)
		}
		if err := checkLine(l); err != nil {
			return h, nil, fmt.Errorf("refusing: %s line %d: %w", planFile, n, err)
		}
		if seen[l.Kind+" "+l.Path] {
			return h, nil, fmt.Errorf("refusing: %s line %d repeats %s", planFile, n, l.Path)
		}
		seen[l.Kind+" "+l.Path] = true
		lines = append(lines, l)
	}
	if err := sc.Err(); err != nil {
		return h, nil, err
	}
	if len(lines) != h.Lines {
		return h, nil, fmt.Errorf("refusing: %s has %d lines, its header says %d", planFile, len(lines), h.Lines)
	}
	return h, lines, nil
}

var (
	exportPath    = regexp.MustCompile(`^gs://[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]/[^/\s][^\s]*$`)
	operationName = regexp.MustCompile(`^projects/` + regexp.QuoteMeta(projectID) + `/databases/[^/\s]+/operations/[^/\s]+$`)
)

// checkBackup refuses unless backup.txt names this plan (by the creation time
// in its header), a finished Firestore export of the dev project with a bucket
// and an object prefix, and a Realtime Database backup that is a non-empty
// file of valid JSON.
func checkBackup(dir string, h header) error {
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
	created := h.CreatedAt.UTC().Format(time.RFC3339)
	switch {
	case kv[planKey] != created:
		return fmt.Errorf("refusing: %s does not name this plan; it needs the line %s: %s", backupFile, planKey, created)
	case !exportPath.MatchString(kv["firestore_export"]):
		return fmt.Errorf("refusing: %s needs firestore_export: gs://<bucket>/<object prefix>", backupFile)
	case !operationName.MatchString(kv["firestore_operation"]):
		return fmt.Errorf("refusing: %s needs firestore_operation: projects/%s/databases/<db>/operations/<id>", backupFile, projectID)
	case kv["firestore_export_state"] != "SUCCESSFUL":
		return fmt.Errorf("refusing: %s does not say firestore_export_state: SUCCESSFUL", backupFile)
	}
	st, err := os.Stat(kv["rtdb_backup"])
	if err != nil || !st.Mode().IsRegular() || st.Size() == 0 {
		return fmt.Errorf("refusing: the rtdb_backup named in %s is not an existing, non-empty file", backupFile)
	}
	dump, err := os.ReadFile(kv["rtdb_backup"])
	if err != nil || !json.Valid(dump) {
		return fmt.Errorf("refusing: the rtdb_backup named in %s is not valid JSON", backupFile)
	}
	return nil
}

// planHash identifies the plan a marker file belongs to.
func planHash(dir string) (string, error) {
	raw, err := os.ReadFile(filepath.Join(dir, planFile))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", sha256.Sum256(raw)), nil
}

// checkMarkers makes a plan directory single-use for -apply as well. A
// directory with applied.txt is refused. A directory where an apply started
// and did not finish may be applied again, but only with the plan that was
// started: deleting the rest of the same list is safe, a changed list is not.
func checkMarkers(dir, hash string) error {
	if _, err := os.Stat(filepath.Join(dir, appliedFile)); err == nil {
		return fmt.Errorf("refusing: %s exists, this plan was already applied; make a new plan in a new directory", filepath.Join(dir, appliedFile))
	}
	started, err := os.ReadFile(filepath.Join(dir, startedFile))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !strings.Contains(string(started), "plan_sha256: "+hash+"\n") {
		return fmt.Errorf("refusing: an earlier apply in this directory did not finish and %s has changed since; make a new plan in a new directory", planFile)
	}
	return nil
}

func writeMarker(dir, name, hash string, now time.Time, note string) error {
	text := fmt.Sprintf("plan_sha256: %s\nat: %s\n%s", hash, now.UTC().Format(time.RFC3339), note)
	return os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600)
}

// exists reports whether the thing a plan line names is in the snapshot.
func (s snapshot) exists(l line) bool {
	if l.Kind == "firestore" {
		_, found := slices.BinarySearchFunc(s.docs, l.Path, func(d doc, path string) int { return strings.Compare(d.path, path) })
		return found
	}
	segs := strings.Split(l.Path, "/")
	switch len(segs) {
	case 2:
		return slices.Contains(s.rtdbTop, segs[1])
	case 3:
		_, found := s.companies[segs[2]]
		return found
	}
	return slices.Contains(s.companies[segs[2]], segs[3])
}

// recheck compares the plan's delete lines with a classification of dev as it
// is now. It returns the lines to delete (still present, still delete), how
// many are already gone, and the lines that are present but no longer classify
// as delete. One stale line refuses the whole apply.
func recheck(planned []line, s snapshot) (todo []line, gone int, stale []string) {
	_, live := s.plan()
	decision := map[string]string{}
	for _, l := range live {
		decision[l.Kind+" "+l.Path] = l.Decision
	}
	for _, l := range planned {
		switch {
		case l.Decision != del:
		case decision[l.Kind+" "+l.Path] == del:
			todo = append(todo, l)
		case !s.exists(l):
			gone++
		default:
			stale = append(stale, l.Path)
		}
	}
	return todo, gone, stale
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
	hash, err := planHash(dir)
	if err != nil {
		return err
	}
	if err := checkMarkers(dir, hash); err != nil {
		return err
	}
	h, lines, err := readPlan(dir, t.project, now)
	if err != nil {
		return err
	}
	if err := checkBackup(dir, h); err != nil {
		return err
	}
	// The plan says where deleting is allowed; the rules say what may be
	// deleted. Classify dev again as it is now (Auth included) and refuse the
	// whole apply when a delete line is present but no longer classifies as
	// delete: a hand-edited line, a user who registered since, a new reference.
	before, err := read(ctx, t)
	if err != nil {
		return err
	}
	todo, gone, stale := recheck(lines, before)
	if len(stale) > 0 {
		for _, p := range stale {
			fmt.Fprintf(out, "NOT DELETE ANY MORE %s\n", p)
		}
		return fmt.Errorf("refusing: %d paths are marked delete in the plan but do not classify as delete now (first: %s); nothing was deleted, make a new plan", len(stale), stale[0])
	}
	var docPaths, nodePaths []string
	for _, l := range todo {
		if l.Kind == "rtdb" {
			nodePaths = append(nodePaths, l.Path)
		} else {
			docPaths = append(docPaths, l.Path)
		}
	}
	// From here on the directory is spent: applied.txt after a clean run,
	// otherwise this marker, which lets only the same plan be applied again.
	if err := writeMarker(dir, startedFile, hash, now, ""); err != nil {
		return err
	}

	fmt.Fprintf(out, "deleting %d Firestore documents and %d Realtime Database nodes in %s (%d planned paths are already gone)\n",
		len(docPaths), len(nodePaths), t.project, gone)
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
	for _, l := range todo {
		if s.exists(l) {
			left++
			fmt.Fprintf(out, "STILL PRESENT %s\n", l.Path)
		}
	}
	fmt.Fprint(out, summarize("dev reset APPLIED. What remains in dev:", t.project, now, s, c, remaining))
	if failed > 0 || left > 0 {
		return fmt.Errorf("%d deletes failed and %d planned paths are still present; the same plan can be applied again while it is valid", failed, left)
	}
	return writeMarker(dir, appliedFile, hash, now,
		fmt.Sprintf("deleted: %d Firestore documents, %d Realtime Database nodes\n", len(docPaths), len(nodePaths)))
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
	var authUserDocs, clientUserDocs, doubtUserDocs, keptCompanyDocs, nodesDeleted, nodesKept []string
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
		if l.Rule == ruleNoOwner {
			noOwner[p]++
		}
		if len(segs) != 2 {
			continue
		}
		switch {
		case segs[0] == collectionPrefix+"users" && l.Rule == ruleUserInAuth:
			authUserDocs = append(authUserDocs, segs[1])
		case segs[0] == collectionPrefix+"users" && l.Rule == ruleUserInDoubt:
			doubtUserDocs = append(doubtUserDocs, segs[1])
		case segs[0] == collectionPrefix+"users" && l.Decision == keep:
			clientUserDocs = append(clientUserDocs, segs[1])
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
	fmt.Fprintf(&b, "  documents whose reference or owner field is present but not a string (kept in doubt, with what depends on them): %s\n", list(c.unreadable))
	if c.companiesInDoubt {
		b.WriteString("  WARNING: the company_id of a user registered in Firebase Auth is not a string, so EVERY company document is kept, with what depends on it\n")
	}
	fmt.Fprintf(&b, "\n  user documents kept: %d (%d registered in Firebase Auth, %d with no Auth account but in a kept company, %d kept in doubt), deleted: %d\n",
		len(authUserDocs)+len(clientUserDocs)+len(doubtUserDocs), len(authUserDocs), len(clientUserDocs), len(doubtUserDocs), deletedUsers)
	fmt.Fprintf(&b, "  Auth users with no %susers document: %d\n", collectionPrefix, len(s.authUsers)-len(authUserDocs))
	fmt.Fprintf(&b, "  deleted user documents whose email address belongs to a registered Auth user under another uid: %d\n", c.emailOverlap)
	fmt.Fprintf(&b, "  kept user ids, registered in Firebase Auth: %s\n", list(authUserDocs))
	fmt.Fprintf(&b, "  kept user ids, no Auth account, of a kept company: %s\n", list(clientUserDocs))
	fmt.Fprintf(&b, "  kept user ids, kept in doubt: %s\n", list(doubtUserDocs))
	fmt.Fprintf(&b, "\n  company documents kept: %d, deleted: %d (a company is kept when a user registered in Firebase Auth references it)\n", len(keptCompanyDocs), deletedCompanyDocs)
	fmt.Fprintf(&b, "  kept company ids: %s\n", list(keptCompanyDocs))
	fmt.Fprintf(&b, "  company ids that Auth-registered users reference but that have no company document: %s\n", list(danglingCompanies))

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
