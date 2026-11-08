#!/usr/bin/env bash
# Workflow policy gate. Fails if any workflow:
#   1. uses the pull_request_target trigger (it hands secrets to forked PR code), or
#   2. is triggered by pull_request AND references secrets.*, or
#   3. is the release workflow and can be triggered by anything but workflow_dispatch,
#      or does not restrict itself to refs/heads/main.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
shopt -s nullglob
files=(.github/workflows/*.yml .github/workflows/*.yaml)
[ ${#files[@]} -gt 0 ] || { echo "FAIL: no workflows found"; exit 1; }
for f in "${files[@]}"; do
  # Ignore comment lines so the explanation of the rule does not trip the rule.
  body=$(grep -v '^\s*#' "$f")
  if grep -q 'pull_request_target' <<<"$body"; then
    echo "FAIL $f: uses pull_request_target"; fail=1
  fi
  if grep -qE '^\s*pull_request:?' <<<"$body" && grep -q 'secrets\.' <<<"$body"; then
    echo "FAIL $f: pull_request workflow references secrets"; fail=1
  fi
done
rel=.github/workflows/release.yml
if [ -f "$rel" ]; then
  body=$(grep -v '^\s*#' "$rel")
  triggers=$(awk '/^on:/{f=1;next} f&&/^[^ ]/{f=0} f&&/^  [a-z_]+:/{gsub(/[ :]/,"");print}' <<<"$body")
  if [ "$triggers" != "workflow_dispatch" ]; then
    echo "FAIL $rel: triggers are [$triggers], must be only workflow_dispatch"; fail=1
  fi
  grep -q "github.ref == 'refs/heads/main'" <<<"$body" || { echo "FAIL $rel: not restricted to main"; fail=1; }
fi
[ $fail -eq 0 ] && echo "PASS workflow policy (${#files[@]} workflow files checked)"
exit $fail
