#!/usr/bin/env bash
# Re-verify the volatile facts in finstack-roadmap-and-frontier (authored 2026-07-07).
# READ-ONLY: gh reads, git reads, greps. Safe to run anytime, from anywhere.
# Expectations printed inline are as-of 2026-07-07 — divergence means the SKILL.md
# needs updating, not that something is broken.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
REPO="anatechopc/finstack"
ARCHIVE="anatechopc/loooans"

section() { printf '\n== %s ==\n' "$1"; }

section "Roadmap state check $(date +%F) (expectations dated 2026-07-07)"

section "Chat frontend PR finstack#84 (expected then: OPEN, +10.9k lines)"
gh pr view 84 --repo "$REPO" --json state,title,updatedAt \
  -q '"\(.state)  \(.title)  (updated \(.updatedAt))"' || echo "!! gh unavailable"

section "Prod deploy branches (expected then: NONE — first prod deploy still pending)"
gh api "repos/$REPO/branches?per_page=100" -q '.[].name' 2>/dev/null \
  | grep -E '^(master|release/)' || echo "no master/release branches on remote (unchanged)"

section "Open issues (expected then: 14 — #6 #9 #10 #13 #14 #21 #28 #30 #31 #32 #40 #41 #42 #63)"
gh issue list --repo "$REPO" --state open --limit 100 --json number,title \
  -q '.[] | "#\(.number)  \(.title)"' || echo "!! gh unavailable"

section "Stale local refs trap (run 'git fetch origin' if dates look old)"
git -C "$ROOT" log -1 --format='local origin/develop: %h %ad' --date=short origin/develop
echo "GitHub develop HEAD: $(gh api "repos/$REPO/commits/develop" -q '.sha' 2>/dev/null | cut -c1-7)"

section "Deploy script function count (develop had 17 incl. messageWritten as of 2026-07-07)"
grep -c "gcloud functions deploy" "$ROOT/.github/scripts/deploy_functions.sh"
grep -q "messageWritten" "$ROOT/.github/scripts/deploy_functions.sh" \
  && echo "messageWritten present" || echo "messageWritten ABSENT"

section "Dormant assets still present?"
for p in packages/loans/karma_transaction_repository \
         packages/loans/transaction_repository \
         packages/loans/transaction_view_repository \
         apps/loans/test/counter \
         functions/loans/job; do
  [ -d "$ROOT/$p" ] && echo "present: $p" || echo "GONE:    $p"
done
[ -f "$ROOT/apps/sms-gateway/java_pid7112.hprof" ] \
  && echo "present: apps/sms-gateway/java_pid7112.hprof (git-ignored, local-only, 681MB)" \
  || echo "GONE:    apps/sms-gateway/java_pid7112.hprof"
grep -n "sometest\|updateUser\|subscriptionJob" "$ROOT/functions/loans/loooans_cloud_functions.go" \
  || echo "scratch/disabled function registrations no longer in init()"

section "Refile sources on archive repo (as of 2026-07-07: #130 CLOSED, #131-#134 OPEN)"
for n in 130 131 132 133 134; do
  gh issue view "$n" --repo "$ARCHIVE" --json number,state,title \
    -q '"loooans#\(.number)  \(.state)  \(.title)"' 2>/dev/null \
    || echo "loooans#$n: not readable (archive repo access?)"
done

section "Done"
echo "If anything above differs from SKILL.md, update the skill (repo/gh wins)."
