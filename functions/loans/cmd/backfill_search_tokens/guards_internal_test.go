package backfill

import "testing"

// The project selects the database; ENVIRONMENT selects the collection prefix.
// Nothing else in this job checks that the two agree, and every failure mode of
// a disagreement is silent: -project=loooans-prod with a leftover
// ENVIRONMENT=development pages dev_users INSIDE production, which either
// builds a parallel dev_-prefixed dataset there or scans nothing at all and
// reports a clean pass while production stays unbackfilled.
func TestCheckEnvironmentMatchesProject(t *testing.T) {
	cases := []struct {
		project     string
		environment string
		wantErr     bool
	}{
		{"loooans-prod", "production", false},
		{"loooans-prod", "development", true},
		{"loooans-prod", "staging", true},
		// One project hosts both, separated by the prefix.
		{"loooans-dev-stg", "development", false},
		{"loooans-dev-stg", "staging", false},
		{"loooans-dev-stg", "production", true},
		// An unrecognised project has no pairing to check, so it falls back to
		// the substring heuristic: a project that reads as production may only
		// be paired with production, and vice versa.
		{"acme-prod-2", "production", false},
		{"acme-prod-2", "development", true},
		{"acme-sandbox", "development", false},
		{"acme-sandbox", "production", true},
	}

	for _, tc := range cases {
		t.Run(tc.project+"/"+tc.environment, func(t *testing.T) {
			err := checkEnvironmentMatchesProject(tc.project, tc.environment)
			if tc.wantErr && err == nil {
				t.Fatalf("ENVIRONMENT=%s against %s was allowed", tc.environment, tc.project)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("ENVIRONMENT=%s against %s was refused: %v", tc.environment, tc.project, err)
			}
		})
	}
}
