# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.CiSweepManifestTest do
  @moduledoc """
  Wires the dogfood manifest (`ci-checks.exs`): proves bag-of-actions can run
  its OWN CI as Batons, all green, with zero GitHub Actions minutes.
  """
  use ExUnit.Case, async: false

  @repo_root Path.expand("../..", __DIR__)

  setup_all do
    {_out, 0} = System.cmd("zig", ["build"], cd: @repo_root, stderr_to_stdout: true)
    :ok
  end

  test "the dogfood manifest checks all pass as Batons" do
    {checks, _bindings} = Code.eval_file(Path.join(@repo_root, "ci-checks.exs"))
    assert is_list(checks) and checks != []

    {results, summary} = Bag.CiSweep.run(checks)
    assert Bag.CiSweep.all_passed?({results, summary}),
           "manifest sweep not green: #{inspect(summary)} / #{inspect(results)}"
  end
end
