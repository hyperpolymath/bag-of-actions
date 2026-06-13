# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.PlannerTest do
  @moduledoc """
  Typed-budget + capability action selection, and structured residue.
  Demonstrates the acceptance scenarios: an exhausted/insufficient paid budget
  removes the paid route (the "Claude/Codex out, cheaper route remains" analog),
  cheap reversible work relegates to the cheapest capable node, mutating work is
  gated on a verifier, and partial results carry repair obligations.
  """
  use ExUnit.Case, async: false
  alias Bag.{Planner, Budget, ActionResult}

  @repo_root Path.expand("../..", __DIR__)

  setup_all do
    {_out, 0} = System.cmd("zig", ["build"], cd: @repo_root, stderr_to_stdout: true)
    :ok
  end

  test "work that NEEDS the paid route uses it when the budget can afford it" do
    spec = %{check_id: "scan", command: ["true"], required_cap: "secret_access"}
    assert {:ok, "mesh-github-runner", 100} = Planner.plan(spec, Budget.unlimited())
  end

  test "insufficient paid budget removes the paid route → work needing it is SUSPENDED" do
    # Only mesh-github-runner (cost 100) has secret_access; a $50 budget can't
    # afford it, and nothing cheaper can do the work → suspend, don't run unsafely.
    spec = %{check_id: "scan", command: ["true"], required_cap: "secret_access"}
    assert {:suspended, :no_affordable_capable_node} = Planner.plan(spec, Budget.new(money: 50))
  end

  test "cheap reversible work relegates to the cheapest capable node" do
    spec = %{check_id: "fmt", command: ["true"], required_cap: "zig"}
    # mesh-laptop (2) and mesh-server-1 (1) both have zig; the min-cost wins.
    assert {:ok, "mesh-server-1", 1} = Planner.plan(spec, Budget.new(money: 50))
  end

  test "mutating work is rejected without a verifier, permitted with one" do
    base = %{check_id: "apply", command: ["true"], required_cap: "linux", mutating: true}
    assert {:rejected, :mutation_requires_verifier} = Planner.plan(base, Budget.unlimited())
    assert {:ok, _node, _cost} = Planner.plan(Map.put(base, :verifier, :human_approved), Budget.unlimited())
  end

  test "non-fungible budgets: money exhaustion does not touch other dimensions" do
    b = Budget.new(money: 0, mutation: 5)
    assert Budget.exhausted?(b, :money)
    refute Budget.exhausted?(b, :mutation)
    assert Budget.affords?(b, :mutation, 3)
  end

  test "a relegated pass still OWES the GitHub required-status-check (echo residue)" do
    r = ActionResult.new(:pass, "mesh-server-1", relegated: true)
    assert r.residue == {:owes, :github_required_check}
  end

  test "a dirty partial yields a repair obligation" do
    r = ActionResult.new(:dirty_partial, "mesh-server-1", repair: :revert_touched_files)
    assert {:dirty, :revert_touched_files} = r.residue
    assert {:ok, :revert_touched_files} = ActionResult.repair_obligation(r)
  end
end
