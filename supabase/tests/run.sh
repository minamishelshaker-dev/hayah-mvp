#!/usr/bin/env bash
# Runs the whole SQL chain + assertion tests on a throw-away local database.
# Needs PostgreSQL 15+ and a superuser:   PGUSER=postgres bash supabase/tests/run.sh
# The Supabase pieces are emulated (tests/stubs.sql); this does NOT replace testing on a real Supabase project.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${HAYAH_TEST_DB:-hayah_test}"
psql -q -v ON_ERROR_STOP=1 -d postgres -c "drop database if exists $DB" -c "create database $DB" 2>&1 | sed '/does not exist, skipping/d'
FILES=(tests/stubs.sql migrations/*.sql tests/helpers.sql)
for f in "${FILES[@]}"; do
  echo "== load $f"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1 | sed '/NOTICE:  extension/d'
done
echo "== tests"
out="$(mktemp)"
for f in tests/tests.sql tests/lifecycle_tests.sql tests/mfa_tests.sql tests/trust_tests.sql tests/followups_tests.sql tests/arbitration_tests.sql tests/arb_signing_tests.sql tests/settlement_bound_tests.sql; do
  if ! psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" >>"$out" 2>&1; then
    grep -E "FAIL|ERROR" "$out" | tail -5
    echo "TESTS FAILED in $f"; exit 1
  fi
done
echo "PASSED: $(grep -c 'PASS:' "$out") assertions"
