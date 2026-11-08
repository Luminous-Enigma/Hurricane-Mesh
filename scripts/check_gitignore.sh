#!/usr/bin/env bash
# .gitignore gate: every path below must be ignored. Uses git's own matcher, not a grep.
set -euo pipefail
cd "$(dirname "$0")/.."
must_ignore=(
  local.properties app/local.properties
  release.jks app/upload.keystore keystore.properties signing.properties app/signing.gradle.kts
  .env .env.local app/.env
  google-services.json app/google-services.json
  models/gemma.litertlm models/x.tflite models/weights.bin
  maps/florida.pmtiles
  build/out.txt app/build/outputs/x.apk app/release.aab .gradle/cache
)
fail=0
for p in "${must_ignore[@]}"; do
  if git check-ignore -q --no-index "$p"; then :; else echo "FAIL not ignored: $p"; fail=1; fi
done
# And the opposite: files that must stay tracked.
must_track=(README.md SECURITY.md shared/theme-tokens/hurricane-mesh-themes.json .github/workflows/checks.yml)
for p in "${must_track[@]}"; do
  if git check-ignore -q --no-index "$p"; then echo "FAIL wrongly ignored: $p"; fail=1; fi
done
[ $fail -eq 0 ] && echo "PASS .gitignore (${#must_ignore[@]} must-ignore, ${#must_track[@]} must-track paths)"
exit $fail
