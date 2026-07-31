# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
import Config

# Production: info-level by default. The hard environment requirements (a real
# BAG_ATTEST_KEY, a present Zig host binary) are enforced fail-closed at boot in
# config/runtime.exs via Bag.Config.validate!/1.
config :logger, level: :info
