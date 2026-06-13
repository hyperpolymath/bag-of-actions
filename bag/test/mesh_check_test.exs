# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.MeshCheckTest do
  @moduledoc """
  Integration test: CI-check Batons routed THROUGH the `Bag.Mesh` orchestrator
  (not just the Executor) to a capability-matched node, plus the `Bag.CiSweep`
  emitter — all on owned compute, zero GitHub Actions minutes.
  """
  use ExUnit.Case, async: false
  alias Bag.{Mesh, CiSweep, Executor}

  @repo_root Path.expand("../..", __DIR__)

  setup_all do
    {_out, 0} = System.cmd("zig", ["build"], cd: @repo_root, stderr_to_stdout: true)
    :ok
  end

  test "node list is read from the mirrored manifest (no Elixir-side copy)" do
    nodes = Executor.list_nodes()
    assert "mesh-server-1" in nodes
    assert "mesh-github-runner" in nodes
  end

  test "Mesh routes a check to a capability-matched node and returns a pass" do
    assert {:pass, node, baton} =
             Mesh.submit_check("mesh-pass", ["zig", "fmt", "--check", "build.zig"],
               required_cap: "zig"
             )

    assert node in ["mesh-laptop", "mesh-server-1"]
    assert baton.verdict == :pass
  end

  test "Mesh reports a real fail verdict through the orchestrator" do
    assert {:fail, _node, baton} =
             Mesh.submit_check("mesh-fail", ["zig", "fmt", "--check", "src/estate.zig"],
               required_cap: "zig"
             )

    assert baton.verdict == :fail
  end

  test "Mesh SUSPENDS when no node can satisfy the (unknown/unprovable) capability" do
    assert {:suspended, nil, nil} =
             Mesh.submit_check("mesh-susp", ["true"], required_cap: "bogus-cap")
  end

  test "CiSweep runs a batch of checks and summarises verdicts" do
    checks = [
      %{check_id: "sweep-ok", command: ["zig", "fmt", "--check", "build.zig"], required_cap: "zig"},
      %{check_id: "sweep-bad", command: ["zig", "fmt", "--check", "src/estate.zig"], required_cap: "zig"}
    ]

    {results, summary} = CiSweep.run(checks)

    assert length(results) == 2
    assert summary[:pass] == 1
    assert summary[:fail] == 1
    refute CiSweep.all_passed?({results, summary})
  end
end
