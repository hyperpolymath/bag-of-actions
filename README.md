<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/hyperpolymath)

= Bag-of-Actions
:toc:
:toclevels: 3
:icons: font

Capability-aware, resumable, distributed continuation runtime based on Elixir, Ephapax, and Zig.

== Vision

Bag-of-Actions is not merely a workflow engine. It is a capability-aware, resumable, distributed continuation runtime that allows work to move dynamically between different execution environments depending on circumstances.

== Architecture

* *Orchestrator:* Elixir/OTP
* *Workload Logic:* Ephapax (Linear Types)
* *Execution Host:* Zig (Wasm-based)
* *Formal Auditor:* Idris 2

== Getting Started

[source,bash]
----
zig build
./zig-out/bin/bag_of_actions init
./zig-out/bin/bag_of_actions run
----

== Status

* *Milestone 1:* Local Baton Cycle (Complete)
* *Milestone 2:* Elixir Mesh Orchestration (Complete)
* *Milestone 3:* Verified ABI — Idris 2 proofs typecheck (Complete; not yet invoked at runtime)
* *Milestone 4:* Guix Integration via the Zig host (Complete)

NOTE: This is the short summary. The authoritative status table, caveats, and
the claim-to-implementation map live in link:README.adoc[] and link:EXPLAINME.adoc[].
