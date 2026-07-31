# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.MergeOrchestrationE2ETest do
  @moduledoc """
  End-to-end: a hypatia merge decision — shaped exactly as
  `Hypatia.MergeOrchestration.BatonEmitter.to_spec/2` produces it — crosses into
  the Bag-of-Actions mesh.

  The decision FREEZES on the token-free brain (which lacks `secret_access`) and
  MIGRATES to the token-bearing `mesh-github-runner`, which re-verifies and runs
  the merge, returning a verdict + residue that feeds back as trust-chain
  evidence. This is the capability-routed actuation backend the
  `05-execution-substrate-bag-of-actions.adoc` design describes.

  SAFETY: no real `gh pr merge` is ever executed. The merge command is replaced
  by a harmless stand-in (`true`) so the routing / mutation-gate / freeze / thaw /
  verdict path is exercised end to end without touching a real PR — and the brain
  holds no token anyway. The real command shape is checked through the planner
  only (which selects a node but executes nothing).
  """
  use ExUnit.Case, async: false
  alias Bag.{Mesh, Planner, Budget, Executor}

  @repo_root Path.expand("../..", __DIR__)
  @exe Path.expand("zig-out/bin/bag_of_actions", Path.expand("../..", __DIR__))

  setup_all do
    {_out, 0} = System.cmd("zig", ["build"], cd: @repo_root, stderr_to_stdout: true)
    :ok
  end

  # The exact spec shape hypatia's `BatonEmitter.to_spec/2` emits for an armed
  # merge — `command` swapped for the caller's so the real `gh pr merge` shape and
  # a safe stand-in can both be exercised.
  defp merge_spec(command) do
    %{
      check_id: "merge-hyperpolymath__a-7",
      command: command,
      required_cap: "secret_access",
      mutating: true,
      verifier: %{
        by: "git-private-farm:decide_action",
        reverifies: %{authority_bot: "robot-repo-automaton", contributing_bots: ["ci"]}
      },
      risk: :low,
      attestation: %{
        lease_id: "lease-hyperpolymath-a-7",
        route: %{authority_bot: "robot-repo-automaton", contributing_bots: ["ci"]},
        method: "squash",
        pool: "p2",
        rationale: "chore/object -> arm_auto"
      }
    }
  end

  defp real_merge_command,
    do: ["gh", "pr", "merge", "7", "--repo", "hyperpolymath/a", "--squash"]

  test "the token-free brain cannot satisfy secret_access; only the runner can" do
    refute Executor.node_satisfies?("mesh-hypatia-brain", ["secret_access"]),
           "the brain must NOT hold secret_access (token-free-brain invariant)"

    assert Executor.node_satisfies?("mesh-github-runner", ["secret_access"])
  end

  test "the real `gh pr merge` spec routes to the token-bearing runner (planner only — nothing run)" do
    # Planner.plan selects a node but executes NOTHING, so it is safe to feed it
    # the real merge command: it proves the routing without merging anything.
    assert {:ok, "mesh-github-runner", 100} =
             Planner.plan(merge_spec(real_merge_command()), Budget.unlimited())
  end

  test "a mutating merge with no verifier is rejected — defence in depth" do
    no_verifier = merge_spec(["true"]) |> Map.delete(:verifier)

    assert {:rejected, :mutation_requires_verifier} =
             Planner.plan(no_verifier, Budget.unlimited())
  end

  test "submit_planned migrates the merge to the runner, runs it, returns verdict + clean residue" do
    # safe stand-in for `gh pr merge` — full freeze/run/verdict path on the
    # secret_access node, no real PR touched.
    result = Mesh.submit_planned(merge_spec(["true"]), Budget.unlimited())

    assert result.node == "mesh-github-runner"
    assert result.verdict == :pass
    # ran on the token/paid route (NOT relegated) -> it satisfied the real gate ->
    # nothing owed: the trust-chain residue is clean.
    assert result.residue == :clean
  end

  test "freeze on the brain (no token) -> thaw on the runner: the continuation hand-off" do
    freeze =
      Path.join(System.tmp_dir!(), "merge-e2e-#{System.unique_integer([:positive])}.baton")

    # 1. Brain attempts the merge but LACKS secret_access -> work is SUSPENDED and
    #    a PENDING baton is frozen so it can migrate (exit 2).
    {brain_out, brain_code} =
      System.cmd(
        @exe,
        ["check", "mesh-hypatia-brain", "secret_access", "merge-7", freeze, "true"],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert brain_code == 2
    assert brain_out =~ "VERDICT=suspended"
    assert brain_out =~ "lacks capability"
    assert File.exists?(freeze)

    # 2. The runner HOLDS secret_access -> it runs the (safe stand-in) merge and
    #    freezes the executed verdict (exit 0).
    {runner_out, runner_code} =
      System.cmd(
        @exe,
        ["check", "mesh-github-runner", "secret_access", "merge-7", freeze, "true"],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert runner_code == 0
    assert runner_out =~ "VERDICT=pass"

    # 3. The verdict thaws on another node with ZERO re-execution; attestation
    #    verifies -> this is the trust-chain residue fed back to the brain.
    {thaw_out, thaw_code} =
      System.cmd(@exe, ["thaw", freeze], cd: @repo_root, stderr_to_stdout: true)

    assert thaw_code == 0
    assert thaw_out =~ "VERDICT=pass"
    assert thaw_out =~ "attestation=hmac:verified"

    File.rm(freeze)
  end
end
