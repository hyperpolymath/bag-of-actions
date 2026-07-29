# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.CiBaton do
  @moduledoc """
  A CI-check Baton: a mobile unit of CI work.

  Where `Bag.Baton` carries a counter that a Wasm module increments, a
  `CiBaton` carries a real estate CI check (`command`) plus the capability a
  node must have to run it (`required_cap`). Once executed on a capable node the
  Zig host freezes the verdict; that frozen verdict is the portable artifact
  that replaces a paid GitHub Actions run — it can migrate to, and be consumed
  on, any other node without re-executing the check.
  """
  defstruct [
    :id,
    :check_id,
    :node,
    :required_cap,
    :command,
    :verdict,
    :exit_code,
    :freeze_path,
    :workdir,
    artifact_path: nil,
    mutating: false,
    risk: :low
  ]

  @type verdict :: :pending | :pass | :fail | :suspended | :error

  @type t :: %__MODULE__{
          id: String.t(),
          check_id: String.t(),
          node: String.t(),
          required_cap: String.t(),
          command: [String.t()],
          verdict: verdict(),
          exit_code: integer() | nil,
          freeze_path: String.t() | nil,
          workdir: String.t() | nil,
          artifact_path: String.t() | nil
        }

  @doc """
  Build a new CI-check Baton.

  `check_id` names the check (e.g. "zig-fmt"); `command` is the argv list to run
  (e.g. `["zig", "fmt", "--check", "build.zig"]`). Options: `:node` (default
  "mesh-server-1"), `:required_cap` (default "linux"), `:freeze_path` (the
  attested result envelope), and `:workdir` (an absolute target repository
  directory; defaults to the Bag repository root).
  """
  def new(check_id, command, opts \\ []) when is_binary(check_id) and is_list(command) do
    %__MODULE__{
      id: "cib-" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)),
      check_id: check_id,
      node: Keyword.get(opts, :node, "mesh-server-1"),
      required_cap: Keyword.get(opts, :required_cap, "linux"),
      command: command,
      verdict: :pending,
      exit_code: nil,
      freeze_path: Keyword.get(opts, :freeze_path),
      workdir: Keyword.get(opts, :workdir),
      artifact_path: Keyword.get(opts, :artifact_path),
      mutating: Keyword.get(opts, :mutating, false),
      risk: Keyword.get(opts, :risk, :low)
    }
  end
end
