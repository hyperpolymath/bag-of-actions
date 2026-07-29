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
  alias Bag.{CiBaton, Executor, GitHubBridge, Mesh}

  def run(checks) when is_list(checks) do
    results =
      Enum.map(checks, fn check ->
        cap = Map.get(check, :required_cap, "linux")
        artifact_path = Map.get(check, :artifact_path)
        workdir = Map.get(check, :workdir)

        {verdict, node, baton} =
          Mesh.submit_check(check.check_id, check.command,
            required_cap: cap,
            artifact_path: artifact_path,
            workdir: workdir
          )

        verified_result(check.check_id, verdict, node, baton)
      end)

    summary = Enum.frequencies_by(results, & &1.verdict)
    {results, summary}
  end

  @doc """
  True only if every check passed — the gate a caller (e.g. hypatia) checks to
  decide a green/red verdict for the whole sweep, with zero paid minutes.
  """
  def all_passed?({results, _summary}), do: Enum.all?(results, &(&1.verdict == :pass))

  # The signed envelope, not the in-memory execution return, authorises a green
  # GitHub status. Thaw every executed Baton here so downstream reporters receive
  # the verified production attestation produced by the Zig host.
  defp verified_result(check_id, verdict, node, %CiBaton{freeze_path: freeze_path})
       when is_binary(freeze_path) do
    {thawed_verdict, thaw_output} = Executor.thaw_check(freeze_path)

    effective_verdict =
      if thawed_verdict == verdict do
        verdict
      else
        :tampered
      end

    %{
      check_id: check_id,
      verdict: effective_verdict,
      execution_verdict: verdict,
      node: node,
      freeze_path: freeze_path,
      attestation: GitHubBridge.verdict_attestation(thaw_output)
    }
  end

  defp verified_result(check_id, verdict, node, _baton) do
    %{check_id: check_id, verdict: verdict, node: node}
  end
end
