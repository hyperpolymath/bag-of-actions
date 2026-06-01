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
  def submit(counter \\ 0, guix_package \\ "hello") do
    baton = Baton.new(counter, "counter.wat", guix_package)
    route_baton(baton)
    baton.id
  end

  defp route_baton(baton) do
    # Pick a random node/process in the group
    members = :pg.get_members(:bag_mesh)
    IO.puts("Mesh: Active members in :bag_mesh: #{inspect(members)}")
    IO.puts("Mesh: Cluster nodes: #{inspect([Node.self() | Node.list()])}")
    
    if members != [] do
      target = Enum.random(members)
      IO.puts("Mesh: Routing Baton to target: #{inspect(target)}")
      GenServer.cast(target, {:process, baton})
    else
      IO.puts("Mesh: No active nodes found. Dropping Baton.")
    end
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
