# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Security CI manifest: external security-analysis tools run as Batons on owned
# compute (zero GitHub Actions minutes). These checks require network access or
# additional tooling beyond the base Zig toolchain, so they live in a separate
# manifest from ci-checks.exs (the reliable local dogfood manifest).
#
# Run via:
#   cd bag && mix bag.sweep ../ci-checks.security.exs
#
# OSSF Scorecard notes:
#   - Requires GITHUB_AUTH_TOKEN in the environment (read-only PAT or GITHUB_TOKEN).
#   - The wrapper script writes JSON output to _bag_artifacts/scorecard/scorecard.json.
#   - The Zig host hashes that file and includes the digest in the frozen Baton.
#   - `publish_results: true`, OSSF badge updates, and GitHub Security tab upload
#     are separate publication concerns NOT handled by this Baton — they remain
#     optional GitHub-native bridges run after the attested result is produced.
#   - See docs/external-tool-batonisation.adoc for the general pattern.
[
  %{
    check_id: "ossf-scorecard",
    command: ["./scripts/baton-scorecard.sh", "github.com/hyperpolymath/bag-of-actions"],
    required_cap: "scorecard",
    artifact_path: "_bag_artifacts/scorecard/scorecard.json"
  }
]
