# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Planner do
  @moduledoc """
  Capability- and budget-typed action selection.

  Mirrors the formal routing objective `Bag.Estate.cheapestCapable` (Idris):
  among nodes that satisfy the required capability AND that the current typed
  budget can still afford, choose the least-cost (tropical ⊕ = min) one.

  Policy realised here:
    * relegate to the cheapest capable node (reserve the paid route for work
      whose capability only it provides);
    * an exhausted/insufficient typed budget removes a route (context change) —
      work that needs an unaffordable route is *suspended*, not run unsafely;
    * mutating / hard-to-undo work requires a verifier before it is planned.

  A `spec` is a map: `%{required_cap: String, mutating: bool (default false),
  risk: atom (default :low), verifier: any | nil}`.
  Returns `{:ok, node, cost}` | `{:rejected, reason}` | `{:suspended, reason}`.
  """
  alias Bag.{Budget, Executor}

  def plan(spec, %Budget{} = budget) when is_map(spec) do
    required_cap = Map.fetch!(spec, :required_cap)
    mutating = Map.get(spec, :mutating, false)
    verifier = Map.get(spec, :verifier)

    cond do
      # Gate: mutating / irreversible work needs a verifier or approval path.
      mutating and is_nil(verifier) ->
        {:rejected, :mutation_requires_verifier}

      true ->
        feasible =
          Executor.node_costs()
          |> Enum.filter(fn {name, cost} ->
            Executor.node_satisfies?(name, [required_cap]) and Budget.affords?(budget, :money, cost)
          end)

        case feasible do
          [] ->
            {:suspended, :no_affordable_capable_node}

          nodes ->
            {name, cost} = Enum.min_by(nodes, fn {_name, cost} -> cost end)
            {:ok, name, cost}
        end
    end
  end
end
