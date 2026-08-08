#!/usr/bin/env bash
# Run once after unpacking or cloning.
#
# Zip archives do not reliably preserve the executable bit, and a hook that is
# not executable fails silently — the harness cannot run it, and every guard it
# carries disappears without a message. Absence reads as permission. This is the
# same failure shape as a guard that cannot parse its input, so it gets the same
# treatment: make it loud.
set -euo pipefail
cd "$(dirname "$0")"

chmod +x hooks/*.sh tests/*.sh bootstrap.sh 2>/dev/null || true
git update-index --chmod=+x hooks/*.sh tests/*.sh bootstrap.sh 2>/dev/null || true

fail=0
for f in hooks/*.sh tests/*.sh; do
  [ -x "$f" ] || { echo "NOT EXECUTABLE: $f"; fail=1; }
done
[ "$fail" -eq 0 ] || { echo "Fix the above before trusting any hook."; exit 1; }

echo "Hooks executable. Verifying they actually fire..."
bash tests/hooks_test.sh | tail -1
echo
echo "Next: read docs/BACKLOG.md"
