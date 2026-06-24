#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# ci-baton-demo.sh — Run an estate CI check as a Baton on owned compute.
#
# This is the bag-of-actions answer to the GitHub Actions billing wall:
# a CI check runs LOCALLY (zero billable minutes), routed only to a node that
# has the required capability, and its verdict is FROZEN into a portable
# envelope that can migrate to / be consumed on another node without re-running.
set -euo pipefail

cd "$(dirname "$0")/.."
BIN=./zig-out/bin/bag_of_actions
FREEZE_DIR="${TMPDIR:-/tmp}"

echo "=== Building the Zig host ==="
zig build
echo

echo "=== Estate nodes (read from the single mirrored manifest) ==="
$BIN nodes
echo

echo "=== (1) PASS: a clean file checked on a zig-capable node ==="
$BIN check mesh-server-1 zig zig-fmt-clean "$FREEZE_DIR/cib-pass.txt" zig fmt --check build.zig \
  && echo "gate: PASS (exit 0)" || echo "gate: FAIL (exit $?)"
echo

echo "=== (2) FAIL: a badly-formatted file (real, honest fail) ==="
# Negative fixture is GENERATED here (not a tracked source file) so it can never
# rot to clean — src/estate.zig used to be this fixture and got formatted, making
# the fail case silently pass.
DIRTY="$FREEZE_DIR/cib-dirty.zig"
printf 'const std=@import("std");\npub fn main()void{\n  _=std;\n}\n' > "$DIRTY"
$BIN check mesh-server-1 zig zig-fmt-dirty "$FREEZE_DIR/cib-fail.txt" zig fmt --check "$DIRTY" \
  && echo "gate: PASS (exit 0)" || echo "gate: FAIL (exit $?)"
rm -f "$DIRTY"
echo

echo "=== (3) SUSPENDED: required capability absent → work suspended, no minutes burned ==="
$BIN check mesh-github-runner zig needs-zig "$FREEZE_DIR/cib-susp.txt" zig fmt --check build.zig \
  && echo "gate: PASS (exit 0)" || echo "gate: SUSPENDED/FAIL (exit $?)"
echo

echo "=== (4) THAW: another node consumes the frozen PASS verdict (attestation verified) ==="
$BIN thaw "$FREEZE_DIR/cib-pass.txt" \
  && echo "gate: PASS (exit 0)" || echo "gate: FAIL (exit $?)"
echo

echo "=== (5) TAMPER: forge verdict=pass→fail in the frozen file, then thaw → REJECTED ==="
sed 's/verdict=pass/verdict=fail/' "$FREEZE_DIR/cib-pass.txt" > "$FREEZE_DIR/cib-forged.txt"
$BIN thaw "$FREEZE_DIR/cib-forged.txt" \
  && echo "gate: PASS (exit 0)" || echo "gate: REJECTED (exit $?)"
echo

echo "=== Frozen PASS envelope (the attested, portable artifact that replaces a paid run) ==="
cat "$FREEZE_DIR/cib-pass.txt"
