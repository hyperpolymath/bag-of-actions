# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Mix.Tasks.Bag.ReportTest do
  use ExUnit.Case, async: true

  test "context_map_from keeps only checks that declare :github_context" do
    checks = [
      %{check_id: "snifs-proofs", command: ["x"], required_cap: "nix", github_context: "bag / Formal proofs (owned compute)"},
      %{check_id: "snifs-abi", command: ["y"], required_cap: "nix", github_context: "bag / ABI conformance (owned compute)"},
      # a check with no github_context falls through to the bag/<check_id> default
      %{check_id: "extra", command: ["z"], required_cap: "nix"}
    ]

    assert Mix.Tasks.Bag.Report.context_map_from(checks) == %{
             "snifs-proofs" => "bag / Formal proofs (owned compute)",
             "snifs-abi" => "bag / ABI conformance (owned compute)"
           }
  end

  test "context_map_from is empty when no check declares a context" do
    assert Mix.Tasks.Bag.Report.context_map_from([%{check_id: "a", command: ["x"]}]) == %{}
  end
end
