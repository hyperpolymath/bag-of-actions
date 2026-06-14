# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.CiSweep do
  @moduledoc """
  Runs a *set* of estate CI checks as Batons through the mesh — the local
  emitter that `hypatia/scripts/ci-health` calls instead of spending GitHub
  Actions minutes. Each check is a map:

      %{check_id: "zig-fmt", command: ["zig", "fmt", "--check", "build.zig"], required_cap: "zig"}

  `required_cap` defaults to "linux". Returns `{results, summary}` where
  `results` is a list of per-check verdicts and `summary` counts verdicts.
  """
  alias Bag.Mesh

  def run(checks) when is_list(checks) do
    results =
      Enum.map(checks, fn check ->
        cap = Map.get(check, :required_cap, "linux")
        artifact_path = Map.get(check, :artifact_path)
        {verdict, node, _baton} = Mesh.submit_check(check.check_id, check.command,
          required_cap: cap,
          artifact_path: artifact_path
        )
        %{check_id: check.check_id, verdict: verdict, node: node}
      end)

    summary = Enum.frequencies_by(results, & &1.verdict)
    {results, summary}
  end

  @doc """
  True only if every check passed — the gate a caller (e.g. hypatia) checks to
  decide a green/red verdict for the whole sweep, with zero paid minutes.
  """
  def all_passed?({results, _summary}), do: Enum.all?(results, &(&1.verdict == :pass))
end
