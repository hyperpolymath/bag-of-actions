# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.CiBatonTest do
  @moduledoc """
  End-to-end smoke test for the CI-check Baton: runs a REAL estate CI check
  (`zig fmt --check`) through the Zig host on a capability-matched node, with
  ZERO GitHub Actions minutes, and proves the frozen verdict survives migration.
  """
  use ExUnit.Case, async: false
  alias Bag.{CiBaton, Executor}

  @repo_root Path.expand("../..", __DIR__)

  setup_all do
    # The check runs through the compiled Zig host — make sure it exists.
    {_out, 0} = System.cmd("zig", ["build"], cd: @repo_root, stderr_to_stdout: true)
    :ok
  end

  setup do
    freeze = Path.join(System.tmp_dir!(), "cib-test-#{:rand.uniform(1_000_000)}.txt")
    on_exit(fn -> File.rm(freeze) end)
    {:ok, freeze: freeze}
  end

  test "a clean file PASSES the formatting check via a Baton (0 GitHub minutes)", %{freeze: freeze} do
    baton = CiBaton.new("zig-fmt-clean", ["zig", "fmt", "--check", "build.zig"])

    assert {:pass, updated, _output} = Executor.run_check(baton, freeze)
    assert updated.verdict == :pass
    assert updated.exit_code == 0
    assert File.exists?(freeze)
    assert File.read!(freeze) =~ "verdict=pass"
  end

  test "a badly-formatted file FAILS the check and freezes a fail verdict", %{freeze: freeze} do
    baton = CiBaton.new("zig-fmt-dirty", ["zig", "fmt", "--check", dirty_fixture()])

    assert {:fail, updated, _output} = Executor.run_check(baton, freeze)
    assert updated.verdict == :fail
    assert updated.exit_code == 1
    assert File.read!(freeze) =~ "verdict=fail"
  end

  # A deliberately mis-formatted Zig file written at RUNTIME. Using a tracked
  # source file (src/estate.zig) as the negative fixture is how this rotted:
  # the file got formatted, so every "should fail" case silently passed.
  # Generated content cannot rot to clean.
  defp dirty_fixture do
    path = Path.join(System.tmp_dir!(), "bag_negtest_dirty.zig")
    File.write!(path, ~s|const std=@import("std");\npub fn main()void{\n  _=std;\n}\n|)
    path
  end

  test "a check is SUSPENDED (not failed) when no node has the capability", %{freeze: freeze} do
    baton =
      CiBaton.new("needs-guix", ["zig", "fmt", "--check", "build.zig"],
        node: "mesh-github-runner",
        required_cap: "guix"
      )

    assert {:suspended, updated, _output} = Executor.run_check(baton, freeze)
    assert updated.verdict == :suspended
  end

  test "a frozen PASS verdict can be thawed on another node with no re-execution", %{freeze: freeze} do
    baton = CiBaton.new("zig-fmt-migrate", ["zig", "fmt", "--check", "build.zig"])
    assert {:pass, _updated, _output} = Executor.run_check(baton, freeze)

    # Another node consumes the verdict from the frozen envelope alone.
    assert {:pass, output} = Executor.thaw_check(freeze)
    assert output =~ "VERDICT=pass"
  end
end
