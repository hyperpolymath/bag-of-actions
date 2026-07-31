# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Executor do
  @moduledoc """
  Interfaces with the Zig-based continuation runner.
  """
  alias Bag.Baton

  # Resolved at runtime via Bag.Config so BAG_BIN can override the in-tree build
  # output (e.g. inside a release). Falls back to repo-root zig-out/bin.
  defp executor_path, do: Bag.Config.executor_path()

  @doc """
  Returns the estate node names, read from the single mirrored manifest
  (`estate.zig` ← `verification/proofs/Bag/Estate.idr`) via the Zig host — so the
  orchestrator never keeps its own copy of the node list to drift out of step.
  """
  def list_nodes, do: Map.keys(node_costs())

  @doc """
  Returns `%{node_name => cost}` — the tropical (min-plus) money grade of each
  node, read from the same mirrored manifest. Owned nodes are cheap; the paid
  github-runner is expensive. Drives the planner's cheapest-capable routing.
  """
  def node_costs do
    case System.cmd(executor_path(), ["nodes"], cd: Path.expand("../../../", __DIR__)) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          case String.split(line, "\t") do
            [name, cost] -> {name, String.to_integer(cost)}
            [name] -> {name, 0}
          end
        end)

      {_output, _code} ->
        %{}
    end
  end

  @doc """
  Returns the estate node names, read from the single mirrored manifest
  (`estate.zig` ← `verification/proofs/Bag/Estate.idr`) via the Zig host — so the
  orchestrator never keeps its own copy of the node list to drift out of step.
  """
  def list_nodes, do: Map.keys(node_costs())

  @doc """
  Returns `%{node_name => cost}` — the tropical (min-plus) money grade of each
  node, read from the same mirrored manifest. Owned nodes are cheap; the paid
  github-runner is expensive. Drives the planner's cheapest-capable routing.
  """
  def node_costs do
    case System.cmd(@executor_path, ["nodes"], cd: Path.expand("../../../", __DIR__)) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          case String.split(line, "\t") do
            [name, cost] -> {name, String.to_integer(cost)}
            [name] -> {name, 0}
          end
        end)

      {_output, _code} ->
        %{}
    end
  end

  @doc """
  Checks if a node satisfies the required capabilities using the Idris-to-Zig bridge.
  """
  def node_satisfies?(node_name, requirements) do
    args = ["match", node_name | requirements]

    case System.cmd(executor_path(), args, cd: Path.expand("../../../", __DIR__)) do
      {_output, 0} -> true
      {_output, _code} -> false
    end
  end

  @doc """
  Runs a CI-check Baton on its capability-matched node, via the Zig `check`
  subcommand, and freezes the verdict to `freeze_path`.

  Returns `{verdict, updated_baton, output}` where verdict is one of
  `:pass | :fail | :suspended | :error`. No GitHub Actions minutes are used —
  the check runs on this (owned) node and the verdict is the portable artifact.
  """
  def run_check(%Bag.CiBaton{} = b, freeze_path) do
    args = ["check", b.node, b.required_cap, b.check_id, freeze_path | b.command]
    workdir = b.workdir || repo_root()

    # Pass artifact path via env var so the Zig host can hash the report after
    # the check runs and include its digest in the frozen Baton envelope.
    base_opts = [cd: workdir, stderr_to_stdout: true]

    opts =
      if b.artifact_path,
        do: Keyword.put(base_opts, :env, [{"BAG_ARTIFACT_PATH", b.artifact_path}]),
        else: base_opts

    {output, code} =
      if Path.type(workdir) == :absolute and File.dir?(workdir) do
        System.cmd(executor_path(), args, opts)
      else
        {"Bag.Executor: workdir must be an existing absolute directory: #{inspect(workdir)}", 126}
      end

    verdict =
      case code do
        0 -> :pass
        1 -> :fail
        2 -> :suspended
        _ -> :error
      end

    {verdict, %{b | verdict: verdict, exit_code: code, freeze_path: freeze_path}, output}
  end

  @doc """
  Thaws a frozen CI-check verdict on another node — zero re-execution.
  Returns `{verdict, output}`.
  """
  def thaw_check(freeze_path) do
    {output, code} =
      System.cmd(executor_path(), ["thaw", freeze_path],
        cd: Path.expand("../../../", __DIR__),
        stderr_to_stdout: true
      )

    verdict =
      case code do
        0 -> :pass
        1 -> :fail
        3 -> :tampered
        _ -> :error
      end

    {verdict, output}
  end

  @doc """
  Runs a single step of the Baton.
  """
  def execute(%Baton{} = baton) do
    # 1. Prepare the baton file for the Zig host
    save_baton_to_disk(baton)

    # 2. Run the Zig executor
    case System.cmd(executor_path(), ["run"], cd: Path.expand("../../../", __DIR__)) do
      {output, 0} ->
        # 3. Reload the updated baton from disk
        updated_baton = load_baton_from_disk()
        {:ok, updated_baton, output}

      {error, _code} ->
        {:error, error}
    end
  end

  defp save_baton_to_disk(baton) do
    # Matches the format expected by our Zig Milestone 1/3 host
    pkg = baton.guix_package || "none"
    # Serialize requirements to a comma-separated string for the text file
    caps = if baton.required_cap == [], do: "none", else: Enum.join(baton.required_cap, ",")
    content = "#{baton.counter}\n#{baton.module_cid}\n#{pkg}\n#{caps}\n"
    File.write!(Path.expand("../../../baton.txt", __DIR__), content)
  end

  defp load_baton_from_disk() do
    content = File.read!(Path.expand("../../../baton.txt", __DIR__))
    [counter_str, module_cid, pkg_line, caps_line | _] = String.split(content, "\n", trim: true)

    required_cap =
      if caps_line == "none" do
        []
      else
        caps_line |> String.split(",") |> Enum.map(&String.to_existing_atom/1)
      end

    %Baton{
      counter: String.to_integer(counter_str),
      module_cid: module_cid,
      guix_package: if(pkg_line == "none", do: nil, else: pkg_line),
      required_cap: required_cap,
      status: :floating
    }
  end

  defp repo_root, do: Path.expand("../../../", __DIR__)
end
