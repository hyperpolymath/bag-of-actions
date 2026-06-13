# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Mix.Tasks.Bag.Sweep do
  @shortdoc "Run a CI-check Baton sweep from a manifest (0 GitHub minutes)"
  @moduledoc """
  Run a set of estate CI checks as Batons on owned compute — zero GitHub
  Actions minutes — and emit a ci-health-compatible report.

      mix bag.sweep [manifest.exs]

  The manifest (default `../ci-checks.exs`, i.e. the repo root) returns a list of
  `%{check_id, command, required_cap}` maps. Each check is routed through
  `Bag.Mesh` to a capability-matched node, run there, and its verdict frozen +
  attested.

  Output:
    * stdout — one TSV line per check: `check_id<TAB>BATON-<VERDICT><TAB>node`
      (the line hypatia/ci-health folds into its estate report).
    * stderr — a human summary.
    * exit status — 0 if every check passed, 1 otherwise (a CI gate).
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "../ci-checks.exs"
    {checks, _bindings} = Code.eval_file(path)
    {results, summary} = Bag.CiSweep.run(checks)

    # Machine-readable TSV on stdout (consumed by hypatia/ci-health).
    Enum.each(results, fn r ->
      verdict = r.verdict |> to_string() |> String.upcase()
      IO.puts("#{r.check_id}\tBATON-#{verdict}\t#{r.node || "-"}")
    end)

    IO.puts(:stderr, "\nbag.sweep: #{inspect(summary)} (0 GitHub minutes)")

    if Bag.CiSweep.all_passed?({results, summary}) do
      IO.puts(:stderr, "bag.sweep: ALL PASS ✅")
    else
      IO.puts(:stderr, "bag.sweep: NOT GREEN ❌")
      exit({:shutdown, 1})
    end
  end
end
