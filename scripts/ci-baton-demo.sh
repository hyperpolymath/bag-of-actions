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

# Phase 1 security: attestation is now fail-closed. A verdict can only be frozen
# with a real shared key (>= 32 bytes) AND a per-node ed25519 signing key — there
# is no dev-key fallback and signing is mandatory. Provide both for the demo.
export BAG_ATTEST_KEY="${BAG_ATTEST_KEY:-bag-demo-attestation-key-0123456789abcdef}"  # 40 bytes
DEMO_SIGN_KEY="$FREEZE_DIR/bag-demo-signing"
if [ ! -f "$DEMO_SIGN_KEY" ]; then
  ssh-keygen -t ed25519 -q -N "" -C bag-demo -f "$DEMO_SIGN_KEY"
fi
export BAG_SIGN_KEY_PATH="$DEMO_SIGN_KEY"

echo "=== Building the Zig host ==="
zig build
echo

echo "=== (0) FAIL-CLOSED: with no BAG_ATTEST_KEY the host refuses to attest (exit 78) ==="
( unset BAG_ATTEST_KEY; $BIN check mesh-server-1 zig needs-key "$FREEZE_DIR/cib-nokey.txt" zig fmt --check build.zig ) \
  && echo "UNEXPECTED: attested without a key" || echo "refused as designed (exit $?)"
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

echo "=== (6) UNSIGNED: strip the ed25519 signature (HMAC-only) → thaw REJECTS ==="
# This is the old forgeable-verdict hole: an unsigned envelope whose HMAC still
# matches used to verify green. v2 makes the signature mandatory.
grep -v '^signature=' "$FREEZE_DIR/cib-pass.txt" | grep -v '^signing_pubkey=' > "$FREEZE_DIR/cib-unsigned.txt"
$BIN thaw "$FREEZE_DIR/cib-unsigned.txt" \
  && echo "gate: PASS (exit 0)" || echo "gate: REJECTED (exit $?)"
echo

echo "=== Frozen PASS envelope (the attested, portable artifact that replaces a paid run) ==="
cat "$FREEZE_DIR/cib-pass.txt"
