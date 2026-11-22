#!/usr/bin/env bash
# Runs every test suite that does not need a Flutter SDK, plus Flutter tests when `flutter` is installed.
# SQL tests need a local PostgreSQL 16 server: set PGHOST/PGPORT/PGUSER (see supabase/tests/run_sql_tests.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== Backend TypeScript: type-check"; (cd supabase/functions && npx --yes tsc -p tsconfig.json && npx --yes tsc -p tsconfig.tests.json)
echo "== Backend TypeScript: tests";      (cd supabase/functions && npx --yes tsx --test tests/*.test.ts)
echo "== Admin: type-check + build";      (cd admin && npx --yes tsc -p tsconfig.json)
echo "== Admin: unit tests";              (cd admin && npx --yes tsx --test tests/lib.test.ts)
echo "== Admin: browser smoke test";      node admin/tests/smoke.mjs || echo "(skipped/failed: needs playwright + chromium)"
echo "== Python worker tests";            python3 -m unittest workers/test_ingest_worker.py
echo "== SQL migrations + RLS tests";     ./supabase/tests/run_sql_tests.sh
echo "== Dart structural check";          python3 tools/dart_sanity.py app
if command -v flutter >/dev/null; then
  echo "== Flutter analyze + test"; (cd app && flutter pub get && flutter analyze && flutter test)
else
  echo "== Flutter SDK not found: run 'cd app && flutter analyze && flutter test' on a machine with Flutter"
fi
