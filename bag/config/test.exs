# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
import Config

# Test runs are quiet by default (only warnings and above) so a green suite is
# readable. Like :dev, the attestation-key fallback is allowed.
config :logger, level: :warning
