package main

import (
	"fmt"
	"regexp"
	"slices"
	"sort"
	"strings"
)

// The one environment this tool can reach. These are constants on purpose: no
// flag, environment variable or argument changes them. (Feature code must use
// utils.GetCollectionPrefix; here following ENVIRONMENT would be the hazard,
// because a typo would point a delete tool at staging or production paths.)
const (
	projectID        = "loooans-dev-stg"
	collectionPrefix = "dev_"
	rtdbRoot         = "dev"
	databaseURL      = "https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app"
)

const (
	keep = "keep"
	del  = "delete"
)

type ruleKind int

const (
	// keepUsers keeps a user document whose id is a Firebase Auth uid, and a
	// user document without an Auth account whose company_id names a kept company.
	keepUsers ruleKind = iota
	// keepReferenced keeps a company that an Auth-registered user's company_id
	// names. A user without an Auth account never makes a company kept.
	keepReferenced
	// keepOwned keeps a document whose owner field names a kept user or company.
	keepOwned
	// deleteAll deletes every document of the collection.
	deleteAll
)

type rule struct {
	collection string // collection id without the dev_ prefix
	kind       ruleKind
	owners     []string // keepOwned only: fields holding the owning user or company id
	why        string
}

// rules is the whole policy, derived from packages/*/*/lib and functions/loans.
// A live dev_ collection that is NOT in this table is kept in full and reported
// as unclassified. Subcollection documents follow their top-level document.
var rules = []rule{
	{"users", keepUsers, nil, "keep when the document id is a Firebase Auth uid (the owner's constraint), or when company_id names a kept company (its clients without a sign-in account); delete the rest"},
	{"companies", keepReferenced, nil, "keep when the company_id of a user registered in Firebase Auth names it; delete the rest"},

	{"address", keepOwned, []string{"data_id"}, "address of a user or company: keep when data_id is a kept user or kept company"},
	{"bank_details", keepOwned, []string{"dataId", "data_id"}, "payout account of a user or company: keep when dataId is a kept user or kept company"},
	{"settings", keepOwned, []string{"user_id"}, "per-user app settings and feature flags: keep when user_id is a kept user"},
	{"bills", keepOwned, []string{"client_id"}, "subscription bill of a company (subscription job): keep when client_id is a kept company"},

	{"loans", deleteAll, nil, "loan"},
	{"loan_schedules", deleteAll, nil, "exists because of a loan"},
	{"additional_loan_amounts", deleteAll, nil, "top-up on a loan"},
	{"payments", deleteAll, nil, "payment on a loan"},
	{"transactions", deleteAll, nil, "ledger row of a loan or payment"},
	{"transaction_views", deleteAll, nil, "projection of transactions"},
	{"karma_transactions", deleteAll, nil, "credit-score movement caused by a loan or payment"},
	{"capital", deleteAll, nil, "lender capital entry, feeds the reports"},
	{"cash_pool", deleteAll, nil, "lender cash movements"},
	{"products", deleteAll, nil, "loan product"},
	{"product_views", deleteAll, nil, "projection of products"},
	{"user_loan_views", deleteAll, nil, "projection of a borrower's loans"},
	{"reviews", deleteAll, nil, "review of a lender or loan"},
	{"notifications", deleteAll, nil, "written by the loan, payment and review triggers"},
	{"chat_rooms", deleteAll, nil, "chat rooms and their messages subcollection"},
	{"password_setup_tokens", deleteAll, nil, "one-time verification records for set-password links"},
}

// Realtime Database policy, per node dev/companies/{id}:
//   - the company document is deleted: the whole node is deleted;
//   - otherwise the report nodes are deleted (the triggers rebuild them from
//     new data), and for a kept company so is loansNode, whose loan-to-product
//     pairs only refer to loans that are being deleted;
//   - every other node under dev/ is kept and listed.
var reportNodes = map[string]bool{"report_summary": true, "report_events": true, "report_recomputes": true}

const loansNode = "loans"

// Rule texts that summary.txt counts by.
const (
	ruleUserInAuth  = "user: uid is in Firebase Auth"
	ruleUserClient  = "user: no Auth account, belongs to a kept company"
	ruleUserDeleted = "user: no Auth account and no kept company"
	ruleNoOwner     = "owned: no owner field, kept in doubt"

	ruleUserInDoubt     = "user: id or company_id is present but not a string, kept in doubt"
	ruleCompanyInDoubt  = "company: kept in doubt, the company_id of a user registered in Firebase Auth is not a string"
	ruleOwnerUnreadable = "owned: the owner field is present but not a string, kept in doubt"
)

func ruleFor(collection string) (rule, bool) {
	for _, r := range rules {
		if r.collection == collection {
			return r, true
		}
	}
	return rule{}, false
}

// selectFields are the only fields the planner loads from a top-level document
// of the collection: ids that the rules compare. Nothing else is read.
func selectFields(collection string) []string {
	r, ok := ruleFor(collection)
	switch {
	case ok && r.kind == keepUsers:
		return []string{"id", "company_id", "email_address"}
	case ok && r.kind == keepOwned:
		return r.owners
	}
	return nil
}

// doc is one existing Firestore document as the planner sees it: its path
// relative to the database (dev_users/U1, dev_users/U1/devices/D1) and, for a
// top-level document, the fields named by selectFields.
type doc struct {
	path   string
	fields map[string]string
	// bad names the selected fields that are present but not a string (a
	// number, a map, a reference). The rules cannot read such a field, so they
	// keep the document and what depends on it rather than treat it as absent.
	bad []string
}

// badRefs returns the unreadable fields that hold a reference or an owner.
func (d doc) badRefs() []string {
	return slices.DeleteFunc(slices.Clone(d.bad), func(f string) bool { return f == "email_address" })
}

// line is one row of plan.jsonl.
type line struct {
	Kind     string `json:"kind"` // "firestore" or "rtdb"
	Path     string `json:"path"`
	Decision string `json:"decision"`
	Rule     string `json:"rule"`
}

type classification struct {
	lines            []line
	keptUsers        map[string]bool
	keptCompanies    map[string]bool
	deletedCompanies map[string]bool
	// emailOverlap counts deleted user documents whose email address is the
	// email of a registered Auth user under another uid. A count, never a value.
	emailOverlap int
	// unreadable lists "path (field)" for every top-level document whose
	// reference or owner field is present but not a string.
	unreadable []string
	// companiesInDoubt is set when a user registered in Auth has an unreadable
	// company_id. Which company it names is unknown, so no company can be shown
	// to be unreferenced and every company document is kept.
	companiesInDoubt bool
}

// classify applies the rule table. authUsers maps every Firebase Auth uid to
// its lower-case email ("" when the account has none).
func classify(docs []doc, authUsers map[string]string) classification {
	c := classification{keptUsers: map[string]bool{}, keptCompanies: map[string]bool{}, deletedCompanies: map[string]bool{}}
	authEmails := map[string]bool{}
	for _, email := range authUsers {
		if email != "" {
			authEmails[email] = true
		}
	}
	inAuth := func(id string, fields map[string]string) bool {
		_, byID := authUsers[id]
		_, byField := authUsers[fields["id"]]
		return byID || byField
	}

	// Pass 1a: users registered in Auth are kept, and only they make a company kept.
	top := map[string]doc{}
	referenced := map[string]bool{}
	var users, companyIDs []string
	keepUser := func(d doc) {
		c.keptUsers[strings.Split(d.path, "/")[1]] = true
		if id := d.fields["id"]; id != "" {
			c.keptUsers[id] = true
		}
	}
	for _, d := range docs {
		segs := strings.Split(d.path, "/")
		if len(segs) != 2 {
			continue
		}
		top[d.path] = d
		if bad := d.badRefs(); len(bad) > 0 {
			c.unreadable = append(c.unreadable, d.path+" ("+strings.Join(bad, ", ")+")")
		}
		switch segs[0] {
		case collectionPrefix + "companies":
			companyIDs = append(companyIDs, segs[1])
		case collectionPrefix + "users":
			users = append(users, d.path)
			if inAuth(segs[1], d.fields) {
				keepUser(d)
				if company := d.fields["company_id"]; company != "" {
					referenced[company] = true
				}
				if slices.Contains(d.bad, "company_id") {
					c.companiesInDoubt = true
				}
			}
		}
	}
	for id := range referenced {
		c.keptCompanies[id] = true
	}
	if c.companiesInDoubt {
		for _, id := range companyIDs {
			c.keptCompanies[id] = true
		}
	}
	// Pass 1b: a user without an Auth account is kept when it belongs to a
	// kept company, or when its id or company_id cannot be read, so that what
	// it owns (address, settings) is kept with it.
	for _, path := range users {
		d := top[path]
		switch {
		case inAuth(strings.Split(path, "/")[1], d.fields):
		case c.keptCompanies[d.fields["company_id"]], len(d.badRefs()) > 0:
			keepUser(d)
		case authEmails[strings.ToLower(d.fields["email_address"])]:
			c.emailOverlap++
		}
	}

	// d is the top-level document; it is the zero doc when that document does
	// not exist and only its subcollections do, and the id alone decides.
	decide := func(collection, id string, d doc) (string, string) {
		r, ok := ruleFor(collection)
		if !ok {
			return keep, "unclassified: not in the rule table, kept in full"
		}
		switch r.kind {
		case keepUsers:
			switch {
			case inAuth(id, d.fields):
				return keep, ruleUserInAuth
			case c.keptCompanies[d.fields["company_id"]]:
				return keep, ruleUserClient
			case len(d.badRefs()) > 0:
				return keep, ruleUserInDoubt
			}
			return del, ruleUserDeleted
		case keepReferenced:
			switch {
			case referenced[id]:
				return keep, "company: a user registered in Firebase Auth references it"
			case c.companiesInDoubt:
				return keep, ruleCompanyInDoubt
			}
			return del, "company: no user registered in Firebase Auth references it"
		case keepOwned:
			found := false
			for _, field := range r.owners {
				owner := d.fields[field]
				if owner == "" {
					continue
				}
				found = true
				if c.keptUsers[owner] || c.keptCompanies[owner] {
					return keep, "owned: the owner is kept"
				}
			}
			switch {
			case len(d.badRefs()) > 0:
				return keep, ruleOwnerUnreadable
			case !found:
				return keep, ruleNoOwner
			}
			return del, "owned: the owner is not kept"
		}
		return del, "loans-domain or derived data"
	}

	// Pass 2: every document takes the decision of its top-level document.
	for _, d := range docs {
		segs := strings.Split(d.path, "/")
		collection := strings.TrimPrefix(segs[0], collectionPrefix)
		decision, why := decide(collection, segs[1], top[segs[0]+"/"+segs[1]])
		if len(segs) == 2 && collection == "companies" && decision == del {
			c.deletedCompanies[segs[1]] = true
		}
		c.lines = append(c.lines, line{Kind: "firestore", Path: d.path, Decision: decision, Rule: why})
	}
	sort.Slice(c.lines, func(i, j int) bool { return c.lines[i].Path < c.lines[j].Path })
	sort.Strings(c.unreadable)
	return c
}

// classifyRTDB turns the shape of dev/ into plan lines. topKeys are the
// children of dev/; companies maps each id under dev/companies to its children.
func classifyRTDB(topKeys []string, companies map[string][]string, keptCompanies, deletedCompanies map[string]bool) []line {
	var lines []line
	add := func(path, decision, why string) {
		lines = append(lines, line{Kind: "rtdb", Path: path, Decision: decision, Rule: why})
	}
	for _, key := range topKeys {
		if key != "companies" {
			add(rtdbRoot+"/"+key, keep, "rtdb: not a company node")
		}
	}
	for id, children := range companies {
		node := rtdbRoot + "/companies/" + id
		if deletedCompanies[id] {
			add(node, del, "rtdb: the company document is deleted, whole node")
			continue
		}
		if len(children) == 0 {
			add(node, keep, "rtdb: not a report or loans node")
		}
		for _, child := range children {
			switch {
			case reportNodes[child]:
				add(node+"/"+child, del, "rtdb: report node, rebuilt by the triggers from new data")
			case child == loansNode && keptCompanies[id]:
				add(node+"/"+child, del, "rtdb: loan-to-product pairs of a kept company, all for deleted loans")
			default:
				add(node+"/"+child, keep, "rtdb: not a report or loans node")
			}
		}
	}
	sort.Slice(lines, func(i, j int) bool { return lines[i].Path < lines[j].Path })
	return lines
}

// checkProject refuses every project but the dev one.
func checkProject(project string) error {
	if project != projectID {
		return fmt.Errorf("refusing project %q: this tool only works on %s", project, projectID)
	}
	return nil
}

// checkADCProject refuses when the credentials or the environment name a
// project other than the dev one. These are the three places the Admin SDK
// would take a project from if the tool did not hard-code it.
func checkADCProject(credentialsProject string, getenv func(string) string) error {
	named := []struct{ source, project string }{
		{"the Application Default Credentials", credentialsProject},
		{"GOOGLE_CLOUD_PROJECT", getenv("GOOGLE_CLOUD_PROJECT")},
		{"GCLOUD_PROJECT", getenv("GCLOUD_PROJECT")},
	}
	for _, n := range named {
		if n.project != "" && n.project != projectID {
			return fmt.Errorf("refusing to run: %s name project %q, this tool only works on %s", n.source, n.project, projectID)
		}
	}
	return nil
}

// safeSegment is the only shape of collection id, document id or Realtime
// Database key the tool handles. Firestore auto ids, Auth uids and the
// collection names all fit. Anything else (a dot, a percent sign, a question
// mark, a space) could change which URL a delete reaches, so a path with such
// a segment is refused: by -plan, which then writes no plan, and by -apply.
var safeSegment = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

func checkSegments(segs []string) error {
	for _, s := range segs {
		if !safeSegment.MatchString(s) {
			return fmt.Errorf("segment %q is empty or has a character outside A-Z a-z 0-9 _ -", s)
		}
	}
	return nil
}

// checkFirestorePath accepts only a document path whose root collection id
// starts with dev_: dev_users/U1, dev_chat_rooms/R1/messages/M1.
func checkFirestorePath(path string) error {
	segs := strings.Split(path, "/")
	if len(segs) < 2 || len(segs)%2 != 0 {
		return fmt.Errorf("firestore path %q is not a document path", path)
	}
	if err := checkSegments(segs); err != nil {
		return fmt.Errorf("firestore path %q: %w", path, err)
	}
	if !strings.HasPrefix(segs[0], collectionPrefix) || segs[0] == collectionPrefix {
		return fmt.Errorf("firestore path %q is not in a %s collection", path, collectionPrefix)
	}
	return nil
}

// checkRTDBPath accepts only the shapes the planner lists: dev/{key},
// dev/companies/{id} and dev/companies/{id}/{child}.
func checkRTDBPath(path string) error {
	segs := strings.Split(path, "/")
	if len(segs) < 2 || len(segs) > 4 || segs[0] != rtdbRoot || len(segs) > 2 && segs[1] != "companies" {
		return fmt.Errorf("rtdb path %q is not %s/{key}, %s/companies/{id} or %s/companies/{id}/{child}", path, rtdbRoot, rtdbRoot, rtdbRoot)
	}
	if err := checkSegments(segs); err != nil {
		return fmt.Errorf("rtdb path %q: %w", path, err)
	}
	return nil
}

// checkRTDBDeletePath accepts only dev/companies/{id}, dev/companies/{id}/
// {report node} and dev/companies/{id}/loans, with the fixed segments matched
// exactly. A hand-edited plan cannot delete dev/, dev/companies or any other
// node.
func checkRTDBDeletePath(path string) error {
	if err := checkRTDBPath(path); err != nil {
		return err
	}
	segs := strings.Split(path, "/")
	ok := len(segs) == 3 || len(segs) == 4 && (reportNodes[segs[3]] || segs[3] == loansNode)
	if !ok {
		return fmt.Errorf("rtdb path %q is not a company node, a company report node or a company loans node", path)
	}
	return nil
}

// checkLines returns the lines that checkLine refuses, as text.
func checkLines(lines []line) []string {
	var refused []string
	for _, l := range lines {
		if err := checkLine(l); err != nil {
			refused = append(refused, err.Error())
		}
	}
	return refused
}

func checkLine(l line) error {
	if l.Decision != keep && l.Decision != del {
		return fmt.Errorf("%q: decision %q is neither keep nor delete", l.Path, l.Decision)
	}
	switch {
	case l.Kind == "firestore":
		return checkFirestorePath(l.Path)
	case l.Kind == "rtdb" && l.Decision == del:
		return checkRTDBDeletePath(l.Path)
	case l.Kind == "rtdb":
		return checkRTDBPath(l.Path)
	}
	return fmt.Errorf("%q: unknown kind %q", l.Path, l.Kind)
}
