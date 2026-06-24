# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Compile-time configuration. Values here are baked into the build; anything
# that must be read from the environment of the *running* node lives in
# config/runtime.exs (which executes at boot, including inside a release).
import Config

# Logger: structured, level-gated. The actual level is overridden per-env below
# and can be raised at runtime via BAG_LOG_LEVEL (see runtime.exs).
config :logger, :console, metadata: [:check_id, :node, :verdict]

# Environment-specific compile-time overrides.
import_config "#{config_env()}.exs"
