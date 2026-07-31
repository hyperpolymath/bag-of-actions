# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.GitHubBridgeTest do
  use ExUnit.Case, async: true
  alias Bag.GitHubBridge

  test "verdict → commit-status state: only :pass is success" do
    assert GitHubBridge.state_for(:pass) == "success"
    assert GitHubBridge.state_for(:fail) == "failure"
    assert GitHubBridge.state_for(:error) == "error"
    # a suspended check (no capable owned node) must NOT silently pass a required gate
    assert GitHubBridge.state_for(:suspended) == "failure"
  end

  test "gh_command posts a commit STATUS (not a check-run — a PAT can't write checks)" do
    {"gh", args} =
      GitHubBridge.gh_command("hyperpolymath/snifs", "deadbeef", "bag/snifs-proofs", :pass,
        node: "mesh-server-1"
      )

    assert "api" in args
    assert "--method" in args and "POST" in args
    assert "repos/hyperpolymath/snifs/statuses/deadbeef" in args
    assert "state=success" in args
    assert "context=bag/snifs-proofs" in args
    assert Enum.any?(args, &String.starts_with?(&1, "description="))
    # the whole point: statuses, never the App-only check-runs endpoint
    refute Enum.any?(args, &String.contains?(&1, "check-runs"))
  end

  test "gh_command threads target_url (link to the attested verdict envelope)" do
    {"gh", args} =
      GitHubBridge.gh_command("o/r", "sha", "ctx", :fail, target_url: "https://node/attest.txt")

    assert "target_url=https://node/attest.txt" in args
    assert "state=failure" in args
  end

  test "description is truncated to GitHub's 140-char commit-status limit" do
    {"gh", args} =
      GitHubBridge.gh_command("o/r", "sha", "ctx", :pass, node: String.duplicate("x", 300))

    desc = Enum.find(args, &String.starts_with?(&1, "description="))
    assert String.length(String.replace_prefix(desc, "description=", "")) <= 140
  end

  @verified %{mode: "prod", ed25519: :verified}

  test "report_sweep posts one status per check, mapping verdicts + contexts (fake runner)" do
    test_pid = self()

    runner = fn cmd, args ->
      send(test_pid, {:posted, cmd, args})
      {"https://api.github.com/repos/o/r/statuses/1", 0}
    end

    sweep =
      {[
         # the :pass carries verified-prod attestation, so its green is authorised
         %{check_id: "snifs-proofs", verdict: :pass, node: "mesh-server-1", attestation: @verified},
         %{check_id: "snifs-abi", verdict: :fail, node: "mesh-server-1"}
       ], %{pass: 1, fail: 1}}

    out =
      GitHubBridge.report_sweep(sweep,
        repo: "hyperpolymath/snifs",
        head_sha: "sha1",
        context_map: %{"snifs-abi" => "ABI conformance — interface drift gate"},
        runner: runner
      )

    assert [{"snifs-proofs", {:ok, _}}, {"snifs-abi", {:ok, _}}] = out

    posts = for _ <- 1..2, do: (receive do {:posted, "gh", args} -> Enum.join(args, " ") end)

    # default context for the un-mapped check; the mapped one matches the required name
    assert Enum.any?(posts, &(String.contains?(&1, "context=bag/snifs-proofs") and String.contains?(&1, "state=success")))
    assert Enum.any?(posts, &(String.contains?(&1, "context=ABI conformance — interface drift gate") and String.contains?(&1, "state=failure")))
  end

  test "report_check surfaces a non-zero gh exit as {:error, {code, output}}" do
    runner = fn _cmd, _args -> {"gh: Not Found (HTTP 404)", 1} end

    assert {:error, {1, "gh: Not Found (HTTP 404)"}} =
             GitHubBridge.report_check("o/r", "sha", "ctx", :pass,
               attestation: @verified,
               runner: runner
             )
  end

  test "FAIL-CLOSED: a :pass without verified attestation is refused, never posted" do
    test_pid = self()
    runner = fn cmd, args -> send(test_pid, {:posted, cmd, args}); {"url", 0} end

    # no attestation at all
    assert {:refused, {:unverified_attestation, :none}} =
             GitHubBridge.report_check("o/r", "sha", "ctx", :pass, runner: runner)

    # dev-mode attestation
    assert {:refused, _} =
             GitHubBridge.report_check("o/r", "sha", "ctx", :pass,
               attestation: %{mode: "dev", ed25519: :verified},
               runner: runner
             )

    # prod but unsigned
    assert {:refused, _} =
             GitHubBridge.report_check("o/r", "sha", "ctx", :pass,
               attestation: %{mode: "prod", ed25519: :none},
               runner: runner
             )

    # the runner must NOT have been called for any refused green
    refute_received {:posted, _, _}
  end

  test "non-green verdicts post without needing attestation" do
    runner = fn _cmd, _args -> {"url", 0} end
    assert {:ok, "url"} = GitHubBridge.report_check("o/r", "sha", "ctx", :fail, runner: runner)
    assert {:ok, "url"} = GitHubBridge.report_check("o/r", "sha", "ctx", :suspended, runner: runner)
  end

  test "verdict_attestation parses the Zig thaw output (prod + ed25519 verified)" do
    out = """
    VERDICT=pass
    check_id=zig-fmt node=mesh-server-1 cap=zig exit_code=0
    command=zig fmt --check build.zig
    mode=prod
    attestation=hmac:verified ed25519:verified
    """

    assert GitHubBridge.verdict_attestation(out) == %{mode: "prod", ed25519: :verified}

    # a dev-mode / unsigned thaw is not greenlight-eligible
    assert %{mode: "dev", ed25519: :none} =
             GitHubBridge.verdict_attestation("VERDICT=pass\nmode=dev\nattestation=hmac:verified ed25519:none\n")
  end
end
