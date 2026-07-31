# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
import Config

# Developer machines: chatty logs, and the documented dev fallbacks for the
# attestation key are permitted (see Bag.Config — fail-closed only in :prod).
config :logger, level: :debug
