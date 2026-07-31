# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Release-time configuration.
#
# NOTE ON ELIXIR VERSIONS: `config/releases.exs` was the runtime-config file for
# `mix release` in Elixir 1.9–1.10. From Elixir 1.11 onward `config/runtime.exs`
# supersedes it and is evaluated for BOTH `mix` and assembled releases, so when
# `runtime.exs` is present (it is — see this directory) the release assembler
# uses that and this file is not consulted. All boot-time/release env reading and
# the fail-closed `Bag.Config.validate!/1` gate therefore live in
# `config/runtime.exs`; the `releases:` block (steps, env, include-erts) lives in
# `mix.exs`.
#
# This file is kept (inert: `import Config` with no `config/2` calls) as a signpost
# so the release story is discoverable from the conventional filename. Do NOT add
# `config/2` calls here on Elixir >= 1.11 — they would be silently ignored.
import Config
