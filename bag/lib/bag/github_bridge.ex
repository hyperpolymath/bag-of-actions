# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.GitHubBridge do
  @moduledoc """
  Discharges the `{:owes, :github_required_check}` residue (see `Bag.ActionResult`):
  publishes a CI-check Baton verdict — produced on owned compute, **zero GitHub
  Actions minutes** — back to a GitHub commit, so a *required* status check is
  satisfied without a GitHub-hosted runner. This is the one bridge `docs/ci-check-baton.adoc`
  names as "a separate cloud-native bridge ... not replaced by this Batonisation".

  ## Design notes

    * **Commit Status, not Check-Run.** The Checks API can only be *written* by a
      GitHub **App** token; a personal/OAuth token (what the `gh` CLI carries)
      cannot create check-runs. The **Commit Status** API
      (`POST /repos/{repo}/statuses/{sha}`) *is* writable by a normal token and
      equally satisfies a branch-protection required context (matched by the
      `context` string). So this bridge posts a status.
    * **Dependency-free.** It shells out to the `gh` CLI via `System.cmd/3`,
      reusing its existing auth — no HTTP client is added to `:bag`.
    * **Conservative mapping.** Only `:pass` maps to `success`; everything else
      (`:fail` → `failure`, `:error` → `error`, `:suspended` → `failure`) is
      non-green, so a check that did not truly pass can never silently satisfy a
      *required* gate (a suspended check = no capable owned node = needs attention).

  Pure argv construction (`gh_command/5`) is separated from the side-effecting
  `report_check/5`, and the command runner is injectable (`:runner` opt), so the
  whole flow is unit-testable without touching GitHub.
  """

  # GitHub commit-status `description` is capped at 140 characters.
  @max_description 140

  @doc "Verdict atom → GitHub commit-status `state` (only `:pass` is green)."
  @spec state_for(atom()) :: String.t()
  def state_for(:pass), do: "success"
  def state_for(:error), do: "error"
  def state_for(_other), do: "failure"

  @doc """
  Build the `gh api` argv that posts a commit status. Pure and testable.

  `context` is the string a branch-protection *required status check* rule matches.
  Options: `:description`, `:target_url` (link to the attested verdict envelope),
  `:node` (folded into the default description).
  """
  @spec gh_command(String.t(), String.t(), String.t(), atom(), keyword()) :: {String.t(), [String.t()]}
  def gh_command(repo, head_sha, context, verdict, opts \\ []) do
    state = state_for(verdict)

    description =
      opts
      |> Keyword.get(:description, default_description(verdict, opts))
      |> truncate()

    base = [
      "api",
      "--method",
      "POST",
      "repos/#{repo}/statuses/#{head_sha}",
      "-f",
      "state=#{state}",
      "-f",
      "context=#{context}",
      "-f",
      "description=#{description}"
    ]

    with_url =
      case Keyword.get(opts, :target_url) do
        nil -> base
        url -> base ++ ["-f", "target_url=#{url}"]
      end

    {"gh", with_url ++ ["--jq", ".url"]}
  end

  @doc """
  Post one verdict as a commit status. Returns `{:ok, status_url}` or
  `{:error, {exit_code, output}}`. Pass `:runner` (a `fn cmd, args -> {out, code} end`)
  to intercept the shell-out (defaults to the real `gh`).
  """
  @spec report_check(String.t(), String.t(), String.t(), atom(), keyword()) ::
          {:ok, String.t()} | {:error, {integer(), String.t()}}
  def report_check(repo, head_sha, context, verdict, opts \\ []) do
    {cmd, args} = gh_command(repo, head_sha, context, verdict, opts)
    runner = Keyword.get(opts, :runner, &default_runner/2)

    case runner.(cmd, args) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, {code, String.trim(out)}}
    end
  end

  @doc """
  Publish a whole `Bag.CiSweep.run/1` result to GitHub.

  `context_opts` requires `:repo` (e.g. `"hyperpolymath/snifs"`) and `:head_sha`.
  Each check's status context defaults to `"bag/<check_id>"`; override per check
  with `:context_map` (e.g. `%{"snifs-abi" => "ABI conformance — interface drift gate"}`)
  to satisfy an existing required-check name. `:runner` is threaded through for tests.

  Returns `[{check_id, {:ok, url} | {:error, reason}}]`.
  """
  @spec report_sweep({[map()], map()}, keyword()) :: [{String.t(), {:ok, String.t()} | {:error, term()}}]
  def report_sweep({results, _summary}, context_opts) do
    repo = Keyword.fetch!(context_opts, :repo)
    head_sha = Keyword.fetch!(context_opts, :head_sha)
    context_map = Keyword.get(context_opts, :context_map, %{})
    runner = Keyword.get(context_opts, :runner)

    Enum.map(results, fn r ->
      context = Map.get(context_map, r.check_id, "bag/#{r.check_id}")
      opts = [node: r.node]
      opts = if runner, do: Keyword.put(opts, :runner, runner), else: opts
      {r.check_id, report_check(repo, head_sha, context, r.verdict, opts)}
    end)
  end

  # ── internals ──────────────────────────────────────────────────────────────

  defp default_runner(cmd, args), do: System.cmd(cmd, args, stderr_to_stdout: true)

  defp default_description(verdict, opts) do
    node = Keyword.get(opts, :node)
    base = "#{verdict} via a bag-of-actions Baton on owned compute (0 GitHub minutes)"
    if node, do: base <> " — node #{node}", else: base
  end

  defp truncate(s) when is_binary(s) do
    if String.length(s) <= @max_description, do: s, else: String.slice(s, 0, @max_description)
  end
end
