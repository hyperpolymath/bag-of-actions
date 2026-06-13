# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Budget do
  @moduledoc """
  Typed, **non-fungible** resource budgets.

  Budgets are NOT a single scalar: a paid-runner money budget, a mutation
  budget, human-review attention, and rollback/repair capacity are not
  interchangeable. Budget exhaustion is a *context change* — when a typed budget
  runs out, plans that relied on it stop type-checking (the resource is simply
  not available to the planner), which is how a depleted paid quota removes the
  paid route while cheaper/owned routes remain.

  Each field is either a number (remaining units) or `:infinity` (untracked).
  """
  defstruct money: :infinity, mutation: :infinity, human_review: :infinity, repair: :infinity

  @type level :: number() | :infinity
  @type t :: %__MODULE__{money: level, mutation: level, human_review: level, repair: level}

  @doc "A new budget from keyword/map fields; unset dimensions are `:infinity`."
  def new(fields \\ []), do: struct(__MODULE__, fields)

  @doc "An untracked (unlimited) budget — the back-compatible default."
  def unlimited, do: %__MODULE__{}

  @doc "True if `key` has at least `amount` units left (`:infinity` always affords)."
  def affords?(%__MODULE__{} = b, key, amount) do
    case Map.get(b, key) do
      :infinity -> true
      have when is_number(have) -> have >= amount
      _ -> false
    end
  end

  @doc "True if `key` cannot afford even one unit (the resource is exhausted)."
  def exhausted?(%__MODULE__{} = b, key), do: not affords?(b, key, 1)

  @doc "Spend `amount` of `key` (floored at 0; `:infinity` is unchanged)."
  def debit(%__MODULE__{} = b, key, amount) do
    case Map.get(b, key) do
      :infinity -> b
      have when is_number(have) -> Map.put(b, key, max(have - amount, 0))
      _ -> b
    end
  end
end
