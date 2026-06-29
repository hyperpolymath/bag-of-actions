;; SPDX-License-Identifier: MPL-2.0
;; Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
;;
;; bag-of-actions mesh toolchain — the BAG PILOT subset.
;; Consumed on a Debian node by Guix-as-package-manager:
;;     guix package -m guix/manifest.scm
;;
;; Verified present in the base Guix 1.5.0 channel (no `guix pull` needed):
;;   zig 0.15.2, elixir 1.19.3, just 1.43.0, age 1.2.1, jq 1.8.1.
;;
;; NOT in Guix (acquired out-of-band by bootstrap.sh `extra`, see that script):
;;   - idris2   — Guix only ships Idris *1*; idris2 needs a Chez bootstrap build
;;                (the "support/ + lib/ symlink" gotcha). Needed for the Phase-3
;;                conformance gate + proof typecheck, NOT for the first green check.
;;   - wasmtime — Bytecode Alliance wasmtime is unpackaged; install the official
;;                static binary (+ the C-API tarball for the Phase-5 FFI). Needed
;;                for the wasm:// check path + continuation frontier, not the pilot.
;;
;; git / openssh / gnupg / coreutils come from the base Debian system.
;;
;; echidna's caps (rust/cargo, julia, GNAT/SPARK via gprbuild+gnatprove, z3) are
;; deferred to Phase 6 onboarding, per the standing rust/SPARK rule.
(specifications->manifest
 (list
  "zig"        ; Zig host (src/*.zig)            — 0.15.2
  "elixir"     ; Baton orchestrator (bag/)       — 1.19.3 / OTP 27
  "just"       ; de-templated Justfile recipes   — 1.43.0
  "age"        ; shared BAG_ATTEST_KEY store     — 1.2.1
  "jq"))       ; conformance-gate harness        — 1.8.1
