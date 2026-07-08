#!/usr/bin/env bash
# export-live-rules.sh — read-only helper to export a project's LIVE security rules
# (Firestore + Storage + RTDB) so you can diff console-vs-repo.
#
# The live Firestore & Storage rules are console-managed; the repo files are stale
# placeholders. This is Step 1 of references/rules-into-source-campaign.md.
#
# NOTHING here mutates the project or the repo. It only reads and writes files into
# the given output directory (default: a scratch dir under the system temp).
#
# Usage:
#   bash scripts/export-live-rules.sh <projectId> [outDir]
#   bash scripts/export-live-rules.sh loooans-dev-stg  /tmp/rules-dev-stg
#   bash scripts/export-live-rules.sh loooans-prod     /tmp/rules-prod
#
# Prereqs: firebase CLI logged in (`firebase login`) with access to the project.
# For the CLI to read Firestore/Storage rules non-interactively this uses the
# Firebase Rules REST API via `firebase` auth is NOT exposed, so this script
# PRINTS the exact steps and runs the RTDB export (which has a stable REST path).
# Firestore/Storage export is easiest via the firebase MCP tool inside a Claude
# session — see the printed instructions.

set -uo pipefail

PROJECT="${1:-}"
OUTDIR="${2:-${TMPDIR:-/tmp}/finstack-live-rules-$PROJECT}"

if [[ -z "$PROJECT" ]]; then
  echo "Usage: $0 <projectId> [outDir]" >&2
  echo "  projectId is loooans-dev-stg or loooans-prod" >&2
  exit 2
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "ERROR: firebase CLI not found on PATH. Install firebase-tools and 'firebase login'." >&2
  exit 2
fi

mkdir -p "$OUTDIR"
echo "Project : $PROJECT"
echo "Out dir : $OUTDIR"
echo

# ---- RTDB rules -------------------------------------------------------------
# Live RTDB rules are served at /.settings/rules.json on the DB instance.
case "$PROJECT" in
  loooans-dev-stg) DB_URL="https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app" ;;
  loooans-prod)    DB_URL="https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app" ;;
  *)               DB_URL="" ;;
esac

if [[ -n "$DB_URL" ]]; then
  echo "== RTDB rules =="
  echo "Fetch the live RTDB rules (read-only) with an auth token, e.g.:"
  echo "  curl -s -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \\"
  echo "    \"$DB_URL/.settings/rules.json\" > \"$OUTDIR/database.rules.live.json\""
  echo "Then diff against the repo:"
  if [[ "$PROJECT" == "loooans-prod" ]]; then
    echo "  diff \"$OUTDIR/database.rules.live.json\" apps/loans/database.rules.prod.json"
  else
    echo "  diff \"$OUTDIR/database.rules.live.json\" apps/loans/database.rules.json"
  fi
  echo "(Or use the firebase MCP tool firebase_get_security_rules with type=rtdb.)"
  echo
fi

# ---- Firestore + Storage rules ---------------------------------------------
cat <<EOF
== Firestore + Storage rules ==
These live only in the console. Three read-only ways to export them:

(1) Firebase MCP (easiest inside a Claude session):
      set the active project to $PROJECT, then call
      firebase_get_security_rules with type=firestore, then type=storage.
      Save each to:
        $OUTDIR/firestore.rules.live
        $OUTDIR/storage.rules.live

(2) firebase CLI init in a SCRATCH dir (never in the repo — it can overwrite):
      mkdir -p /tmp/fb-init-$PROJECT && cd /tmp/fb-init-$PROJECT
      firebase init firestore --project $PROJECT   # "Downloaded the existing ... rules"
      firebase init storage   --project $PROJECT
      then copy the downloaded firestore.rules / storage.rules into $OUTDIR.

(3) Firebase Rules REST API (firebaserules.googleapis.com/v1):
      GET /v1/projects/$PROJECT/releases
        -> find release name starting with projects/$PROJECT/releases/cloud.firestore
           (and .../firebase.storage); read its rulesetName
      GET /v1/<rulesetName>
        -> source.files[].content is the live rules text

Then diff against the (stale) repo files to confirm what the live rules contain:
  diff $OUTDIR/firestore.rules.live apps/loans/firestore.rules   # expect large diff
  diff $OUTDIR/storage.rules.live   apps/loans/storage.rules     # expect large diff

Next: references/rules-into-source-campaign.md Step 2 onward.
EOF
