# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Mesh do
  @moduledoc """
  The distributed orchestrator for Batons.
  """
  use GenServer
  alias Bag.{Baton, Executor}

  def start_link(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    :ok = :pg.join(:bag_mesh, pid)
    {:ok, pid}
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
