#!/usr/bin/env bash
# Repository gates. Prints every result, including failures (BUILD_PROTOCOL Part A).
# App gates (A1–A8, G-*) are added in M1, when there is code for them to check.
set -uo pipefail
cd "$(dirname "$0")"
fails=0
run() { local id="$1"; shift; echo "── $id"; if "$@"; then echo "   $id: PASS"; else echo "   $id: FAIL"; fails=$((fails+1)); fi; }

run R-WORKFLOWS ./scripts/check_workflows.sh
run R-GITIGNORE ./scripts/check_gitignore.sh
if command -v gitleaks >/dev/null; then
  run R-SECRETS gitleaks git --redact --verbose --exit-code 1 .
else
  echo "── R-SECRETS: NOT RUN (gitleaks not installed). CI runs it on every pull request."
fi
echo "── A1–A8, G-*: NOT WIRED (no app code yet, see STUBS.md)"
echo
[ $fails -eq 0 ] && echo "gates: all run gates passed" || echo "gates: $fails FAILED"
exit $fails
