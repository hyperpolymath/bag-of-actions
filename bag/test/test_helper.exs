# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
ExUnit.start()

# Phase 1 security: the Zig host is fail-closed — it refuses to freeze a verdict
# without a real shared HMAC key (>= 32 bytes) AND a usable ed25519 signing key,
# and thaw rejects any unsigned / HMAC-only / non-v2 envelope. The integration
# tests that shell out to the `check`/`thaw` subcommands therefore need a real
# attestation context. Provide a deterministic one for the suite.
System.put_env("BAG_ATTEST_KEY", "bag-test-attestation-key-0123456789abcdef")
System.put_env("BAG_MODE", "prod")

sign_key = Path.join(System.tmp_dir!(), "bag-test-signing")

unless File.exists?(sign_key) do
  {_out, 0} =
    System.cmd("ssh-keygen", ["-t", "ed25519", "-q", "-N", "", "-C", "bag-test", "-f", sign_key])
end

System.put_env("BAG_SIGN_KEY_PATH", sign_key)
