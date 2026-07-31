# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Mix.Tasks.Bag.Report do
  @shortdoc "Run a Baton sweep on owned compute + post each verdict to a GitHub commit"
  @moduledoc """
  Run a CI-check Baton sweep on owned compute (**zero GitHub Actions minutes**) AND
  publish each verdict back to a GitHub commit as a *status* (via `Bag.GitHubBridge`),
  satisfying a branch-protection **required check** without a GitHub-hosted runner.
  This is the dispatcher that makes the bag→GitHub bridge live — `bag.sweep` runs
  the checks; `bag.report` runs them *and* reports back.

      GITHUB_REPOSITORY=hyperpolymath/snifs GITHUB_SHA=<head-sha> \\
        mix bag.report /path/to/snifs/ci-checks.exs

  `GITHUB_REPOSITORY` + `GITHUB_SHA` are the standard GitHub env vars (set by the
  triggering dispatcher; `BAG_HEAD_SHA` is accepted as a fallback for the PR head).
  Each manifest check may carry an optional `:github_context` — the required-check
  NAME its verdict posts to; absent, the context defaults to `bag/<check_id>`.

  Exit status: `0` iff every check passed AND every status posted; `1` otherwise.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {repo, head_sha} = github_context!()
    path = List.first(args) || "../ci-checks.exs"
    {checks, _bindings} = Code.eval_file(path)

    {results, summary} = Bag.CiSweep.run(checks)
    context_map = context_map_from(checks)

    posts =
      Bag.GitHubBridge.report_sweep({results, summary},
        repo: repo,
        head_sha: head_sha,
        context_map: context_map
      )

    Enum.each(posts, fn
      {id, {:ok, url}} -> IO.puts("#{id}\tposted\t#{url}")
      {id, {:refused, reason}} -> IO.puts(:stderr, "#{id}\tREFUSED\t#{inspect(reason)}")
      {id, {:error, reason}} -> IO.puts(:stderr, "#{id}\tPOST-FAILED\t#{inspect(reason)}")
    end)

    IO.puts(:stderr, "bag.report: #{inspect(summary)} on owned compute (0 GitHub minutes)")

    green? = Bag.CiSweep.all_passed?({results, summary})
    posted? = Enum.all?(posts, &match?({_id, {:ok, _url}}, &1))
    refused? = Enum.any?(posts, &match?({_id, {:refused, _}}, &1))

    cond do
      green? and posted? ->
        IO.puts(:stderr, "bag.report: ALL PASS + posted ✅")

      refused? ->
        IO.puts(:stderr, "bag.report: GREEN REFUSED — verdict not attested prod+ed25519 ❌")
        exit({:shutdown, 1})

      not posted? ->
        IO.puts(:stderr, "bag.report: posted-with-errors ❌")
        exit({:shutdown, 1})

      true ->
        IO.puts(:stderr, "bag.report: NOT GREEN ❌")
        exit({:shutdown, 1})
    end
  end

  @doc """
  Build a `%{check_id => github_context}` map from the manifest checks that declare
  a `:github_context`. Checks without one fall through to `Bag.GitHubBridge`'s
  `bag/<check_id>` default. Pure — unit-tested.
  """
  def context_map_from(checks) do
    checks
    |> Enum.filter(&Map.has_key?(&1, :github_context))
    |> Map.new(fn c -> {c.check_id, c.github_context} end)
  end

  defp github_context! do
    repo =
      System.get_env("GITHUB_REPOSITORY") ||
        Mix.raise("bag.report: GITHUB_REPOSITORY not set (expected \"owner/repo\")")

    sha =
      System.get_env("GITHUB_SHA") || System.get_env("BAG_HEAD_SHA") ||
        Mix.raise("bag.report: GITHUB_SHA (or BAG_HEAD_SHA) not set (the PR head commit)")

    {repo, sha}
  end
end
