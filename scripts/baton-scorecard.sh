#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# baton-scorecard.sh — Run OSSF Scorecard as a Baton payload.
#
# This wrapper is the stable interface between the Baton system and the
# Scorecard CLI. It ensures a deterministic output path so the Zig host
# can hash the report and include the digest in the frozen Baton envelope.
#
# Usage:
#   ./scripts/baton-scorecard.sh [REPO]
#
# REPO defaults to github.com/hyperpolymath/bag-of-actions.
#
# Environment:
#   GITHUB_AUTH_TOKEN  Required. A read-only PAT (or GITHUB_TOKEN in CI).
#                      Scorecard uses it to query the GitHub API.
#   BAG_SCORECARD_MIN_SCORE  Optional. If set, exit 1 when the aggregate
#                             score is below this value (0–10). Default:
#                             preserve Scorecard's own exit code (no threshold).
#
# Output:
#   _bag_artifacts/scorecard/scorecard.json  Machine-readable results.
#
# Exit codes (passed through from Scorecard unless BAG_SCORECARD_MIN_SCORE is set):
#   0  Scorecard ran successfully.
#   1  Scorecard reported a failure or the score is below the configured threshold.
#
# NOT handled here (separate publication concerns):
#   - publish_results: true / OSSF API upload
#   - GitHub Security tab (SARIF upload via github/codeql-action/upload-sarif)
#   - OSSF badge updates
#
# See docs/external-tool-batonisation.adoc for the general pattern.
set -euo pipefail

REPO="${1:-github.com/hyperpolymath/bag-of-actions}"
ARTIFACT_DIR="_bag_artifacts/scorecard"
ARTIFACT_PATH="${ARTIFACT_DIR}/scorecard.json"

mkdir -p "${ARTIFACT_DIR}"

if ! command -v scorecard &>/dev/null; then
  echo "baton-scorecard: 'scorecard' CLI not found." >&2
  echo "Install via: go install sigs.k8s.io/scorecard/v5/cmd/scorecard@latest" >&2
  echo "Or run via container: see docs/external-tool-batonisation.adoc" >&2
  exit 1
fi

echo "baton-scorecard: running Scorecard for ${REPO}" >&2
# Export version so the Zig host can bind it to the Baton canonical string.
export BAG_TOOL_VERSION="scorecard $(scorecard version 2>&1 | head -1)"
scorecard \
  --repo="${REPO}" \
  --format=json \
  --show-details \
  >"${ARTIFACT_PATH}"

EXIT_CODE=$?

if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "baton-scorecard: Scorecard exited with code ${EXIT_CODE}" >&2
  exit "${EXIT_CODE}"
fi

echo "baton-scorecard: results written to ${ARTIFACT_PATH}" >&2

# Optional score threshold gate.
if [[ -n "${BAG_SCORECARD_MIN_SCORE:-}" ]]; then
  SCORE=$(jq -r '.score // empty' "${ARTIFACT_PATH}" 2>/dev/null || echo "")
  if [[ -z "${SCORE}" ]]; then
    echo "baton-scorecard: could not parse .score from ${ARTIFACT_PATH}" >&2
    exit 1
  fi
  # Use awk for float comparison (bash arithmetic is integers only).
  if awk "BEGIN { exit (${SCORE} >= ${BAG_SCORECARD_MIN_SCORE}) ? 0 : 1 }"; then
    echo "baton-scorecard: score ${SCORE} >= ${BAG_SCORECARD_MIN_SCORE} (threshold met)" >&2
  else
    echo "baton-scorecard: score ${SCORE} < ${BAG_SCORECARD_MIN_SCORE} (threshold NOT met)" >&2
    exit 1
  fi
fi
