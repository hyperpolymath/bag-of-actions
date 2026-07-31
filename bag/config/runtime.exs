# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Runtime configuration. Unlike config/config.exs this file runs at *boot* —
# including inside a `mix release` — so it is the correct place to read the
# environment of the running node and to fail closed on missing prerequisites.
import Config

# Optional runtime override of the log level (e.g. BAG_LOG_LEVEL=debug).
if level = System.get_env("BAG_LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end

# Surface the environment into application config so Bag.Config (and callers)
# read a single source of truth rather than scattering System.get_env/1.
config :bag,
  attest_key: System.get_env("BAG_ATTEST_KEY"),
  sign_key_path: System.get_env("BAG_SIGN_KEY_PATH"),
  gh_token: System.get_env("GH_TOKEN"),
  state_dir: System.get_env("BAG_STATE_DIR"),
  executor_path: System.get_env("BAG_BIN")

# Fail closed — PROD ONLY. The validation is gated here so it is NEVER invoked
# under :test or :dev (which run without these secrets); `mix test` and plain
# `mix run` therefore stay green with no env vars set. Inside a `mix release`
# config_env() is :prod, so an unconfigured production node refuses to boot.
if config_env() == :prod do
  Bag.Config.validate!()
end
