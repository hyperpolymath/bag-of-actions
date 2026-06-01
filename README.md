<!--
SPDX-License-Identifier: MPL-2.0
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

* *Milestone 1:* Local Baton Cycle (Completed)
* *Milestone 2:* Elixir Mesh Orchestration (Completed)
* *Milestone 3:* Verified ABI (Planned)
