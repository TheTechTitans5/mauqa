#!/usr/bin/env bash
# Applies every migration + seed to a fresh database on a local PostgreSQL 16 server
# (with a small Supabase stub), then runs the SQL test files. Any failed assertion aborts.
#
# Usage: PGHOST=/tmp/pg PGPORT=54329 PGUSER=postgres ./supabase/tests/run_sql_tests.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=${TEST_DB:-mauqa_test}
PSQL="psql -v ON_ERROR_STOP=1 -q -X"

$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$PSQL -d "$DB" -f supabase/tests/sql/00_supabase_stub.sql >/dev/null
for f in supabase/migrations/*.sql; do
  echo "migrate  $(basename "$f")"
  $PSQL -d "$DB" -f "$f" >/dev/null
done
echo "seed     seed.sql"
$PSQL -d "$DB" -f supabase/seed.sql >/dev/null
for f in supabase/tests/sql/[1-9]*.sql; do
  echo "test     $(basename "$f")"
  $PSQL -d "$DB" -f "$f"
done
echo "ALL SQL TESTS PASSED"
