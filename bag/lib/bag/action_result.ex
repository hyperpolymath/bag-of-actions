# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.ActionResult do
  @moduledoc """
  The result of an action, carrying structured **residue** (the echo-types idea:
  lossy/partial transformations retain a proof-relevant residue, not just
  success/failure).

  `residue` is one of:
    * `:clean`                       — nothing owed, nothing to repair
    * `{:owes, obligation}`          — succeeded, but an obligation remains
                                       (e.g. a *relegated* check still owes the
                                       GitHub required-status-check it can't
                                       natively satisfy)
    * `{:dirty, repair_obligation}`  — a partial/failed action left damage that
                                       must be repaired or discarded

  A cheap action is only truly cheap if its residue is cheap to verify/repair.
  """
  defstruct [:verdict, :node, :residue, :baton]

  @type residue :: :clean | {:owes, term()} | {:dirty, term()}
  @type t :: %__MODULE__{verdict: atom(), node: String.t() | nil, residue: residue(), baton: any()}

  @doc """
  Classify the residue from a verdict + context.

  Opts: `:relegated` (ran off the canonical paid route → owes its native gate),
  `:repair` (the repair obligation to attach to a dirty/partial verdict).
  """
  def classify(verdict, opts \\ []) do
    cond do
      verdict in [:dirty_partial, :catastrophic_partial] ->
        {:dirty, Keyword.get(opts, :repair, :unspecified_repair_obligation)}

      verdict == :pass and Keyword.get(opts, :relegated, false) ->
        {:owes, :github_required_check}

      true ->
        :clean
    end
  end

  @doc "Build a result, classifying residue from the verdict + context."
  def new(verdict, node, opts \\ []) do
    %__MODULE__{
      verdict: verdict,
      node: node,
      residue: classify(verdict, opts),
      baton: Keyword.get(opts, :baton)
    }
  end

  @doc "The repair obligation a dirty result imposes, or `:none`."
  def repair_obligation(%__MODULE__{residue: {:dirty, ob}}), do: {:ok, ob}
  def repair_obligation(%__MODULE__{}), do: :none
end
