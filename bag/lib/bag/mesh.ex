# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Mesh do
  @moduledoc """
  The distributed orchestrator for Batons.
  """
  use GenServer
  alias Bag.{ActionResult, Baton, CiBaton, Budget, Executor, Planner}

  def start_link(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    :ok = :pg.join(:bag_mesh, pid)
    {:ok, pid}
  end

  @doc """
  Submit a CI-check Baton to the mesh. The orchestrator selects an estate node
  that satisfies `required_cap` (reading the node list from the mirrored
  manifest, capability-matching via the Idris-to-Zig bridge), runs the check
  there, and freezes an attested verdict — with ZERO GitHub Actions minutes.

  Options: `:required_cap` (default "linux"), `:freeze_path`.
  Returns `{verdict, node, baton}` where verdict is
  `:pass | :fail | :suspended | :tampered | :error` (`node` is nil if suspended).
  """
  def submit_check(check_id, command, opts \\ []) when is_binary(check_id) and is_list(command) do
    GenServer.call(__MODULE__, {:submit_check, check_id, command, opts}, 60_000)
  end

  @doc """
  Budget-and-capability-aware submission. The planner selects the cheapest
  capable node the budget can afford (gating mutating work on a verifier); the
  check runs there; the result carries structured residue.

  `spec`: `%{check_id, command, required_cap, mutating?, risk?, verifier?}`.
  Returns a `Bag.ActionResult` (verdict `:pass | :fail | :rejected | :suspended`).
  """
  def submit_planned(spec, %Budget{} = budget \\ Budget.unlimited()) do
    GenServer.call(__MODULE__, {:submit_planned, spec, budget}, 60_000)
  end

  @doc """
  Submits a new Baton to the Mesh.
  """
  def submit(counter \\ 0, guix_package \\ "hello", required_cap \\ [:guix]) do
    baton = Baton.new(counter, "counter.wat", guix_package, required_cap)
    route_baton(baton)
    baton.id
  end

  defp route_baton(baton) do
    # 1. Get all members in the mesh
    members = :pg.get_members(:bag_mesh)
    
    # 2. Filter members based on their node name and the Baton's requirements
    # For this POC, we assume the node name is the Elixir sname (e.g. mesh-laptop)
    # In a production system, this would be an attested identity.
    valid_targets = Enum.filter(members, fn pid ->
      node_name = node_to_name(node(pid))
      # Translate requiredCap to string list for the Zig bridge
      req_strings = Enum.map(baton.required_cap || [], fn
        :guix -> "guix"
        :linux -> "linux"
        :macos -> "macos"
        :gpu -> "gpu"
        :trusted_host -> "trusted_host"
        :zig -> "zig"
        :rust -> "rust"
        :cargo -> "cargo"
        :deno -> "deno"
        :scorecard -> "scorecard"
        :wasm -> "wasm"
        :nix -> "nix"
        _ -> "unknown"
      end)
      
      Executor.node_satisfies?(node_name, req_strings)
    end)

    IO.puts("Mesh: Routing Baton #{baton.id} [Requirements: #{inspect(baton.required_cap)}]")
    IO.puts("Mesh: Valid targets found: #{inspect(valid_targets)}")
    
    if valid_targets != [] do
      target = Enum.random(valid_targets)
      IO.puts("Mesh: Routing to verified node: #{inspect(target)}")
      GenServer.cast(target, {:process, baton})
    else
      IO.puts("Mesh: NO CAPABLE NODES FOUND for Baton #{baton.id}. Work suspended.")
    end
  end

  defp node_to_name(node_atom) do
    node_atom |> to_string() |> String.split("@") |> List.first()
  end

  # Callbacks

  @impl true
  def init(_opts) do
    # Ensure :pg is started (it's often started by default but let's be safe)
    # Actually :pg.start_link() is for a scope. The default scope is always available.
    {:ok, %{batons: %{}}}
  end

  @impl true
  def handle_call({:submit_check, check_id, command, opts}, _from, state) do
    required_cap = Keyword.get(opts, :required_cap, "linux")
    artifact_path = Keyword.get(opts, :artifact_path)

    freeze_path =
      Keyword.get(opts, :freeze_path, Path.join(System.tmp_dir!(), "#{check_id}.baton"))

    # Select a capable node from the mirrored estate manifest.
    capable =
      Executor.list_nodes()
      |> Enum.filter(fn node -> Executor.node_satisfies?(node, [required_cap]) end)

    case capable do
      [] ->
        # Operational logs go to stderr — stdout is reserved for machine output.
        IO.puts(:stderr, "Mesh: NO node satisfies '#{required_cap}' for check #{check_id}. Suspended.")
        {:reply, {:suspended, nil, nil}, state}

      [node | _] ->
        baton = CiBaton.new(check_id, command,
          node: node,
          required_cap: required_cap,
          artifact_path: artifact_path
        )
        IO.puts(:stderr, "Mesh: routing check #{check_id} → #{node} (cap: #{required_cap})")
        {verdict, updated, _output} = Executor.run_check(baton, freeze_path)
        IO.puts(:stderr, "Mesh: check #{check_id} verdict=#{verdict} on #{node} (0 GitHub minutes)")
        {:reply, {verdict, node, updated}, state}
    end
  end

  @impl true
  def handle_call({:submit_planned, spec, budget}, _from, state) do
    case Planner.plan(spec, budget) do
      {:ok, node, cost} ->
        IO.puts(:stderr, "Mesh: planned #{spec.check_id} → #{node} (money cost #{cost})")

        baton =
          CiBaton.new(spec.check_id, spec.command,
            node: node,
            required_cap: spec.required_cap,
            mutating: Map.get(spec, :mutating, false),
            risk: Map.get(spec, :risk, :low),
            artifact_path: Map.get(spec, :artifact_path)
          )

        freeze_path = Path.join(System.tmp_dir!(), "#{spec.check_id}.baton")
        {verdict, updated, _output} = Executor.run_check(baton, freeze_path)
        # Relegated = ran on an owned node, not GitHub's required-check route.
        relegated = node != "mesh-github-runner"
        result = ActionResult.new(verdict, node, relegated: relegated, baton: updated)
        {:reply, result, state}

      {:rejected, reason} ->
        IO.puts(:stderr, "Mesh: REJECTED #{spec.check_id}: #{reason}")
        {:reply, %ActionResult{verdict: :rejected, node: nil, residue: {:owes, reason}}, state}

      {:suspended, reason} ->
        IO.puts(:stderr, "Mesh: SUSPENDED #{spec.check_id}: #{reason} (budget/capability)")
        {:reply, %ActionResult{verdict: :suspended, node: nil, residue: :clean}, state}
    end
  end

  @impl true
  def handle_cast({:process, baton}, state) do
    IO.puts("Mesh [#{Node.self()}]: Claimed Baton #{baton.id} with count #{baton.counter}")
    
    case Executor.execute(baton) do
      {:ok, updated_baton, output} ->
        IO.puts("Mesh [#{Node.self()}]: Execution complete. Output: #{String.trim(output)}")
        
        # Decide whether to continue or complete
        if updated_baton.counter < 10 do
          IO.puts("Mesh [#{Node.self()}]: Baton not finished. Passing to next step...")
          # Simulate a delay
          Process.sleep(1000)
          
          # Handoff: pick a random node in the cluster
          route_baton(%{updated_baton | id: baton.id})
        else
          IO.puts("Mesh [#{Node.self()}]: Baton task COMPLETED at count #{updated_baton.counter}")
        end

      {:error, reason} ->
        IO.puts("Mesh: Execution FAILED for Baton #{baton.id}: #{reason}")
    end

    {:noreply, state}
  end
end
