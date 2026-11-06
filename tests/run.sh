#!/bin/bash
# Runs the plugin against each fixture and checks the menu bar title (first line).
set -u
cd "$(dirname "$0")/.." || exit 1
PLUGIN="$(ls netstatus.*.sh | head -1)"
pass=0; fail=0
bash -n "$PLUGIN" || { echo "syntax error in $PLUGIN"; exit 1; }
for dir in tests/fixtures/*/; do
  name="$(basename "$dir")"
  expected="$(cat "$dir/expected_title.txt")"
  out="$(NETSTATUS_FIXTURE_DIR="$dir" bash "$PLUGIN")"
  got="$(printf '%s\n' "$out" | head -1)"
  if [ "$got" = "$expected" ]; then
    echo "PASS  $name  ->  $got"; pass=$((pass + 1))
  else
    echo "FAIL  $name"; echo "      expected: $expected"; echo "      got:      $got"; fail=$((fail + 1))
  fi
  if [ "${VERBOSE:-0}" = "1" ]; then printf '%s\n\n' "$out" | sed 's/^/      /'; fi
done
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
