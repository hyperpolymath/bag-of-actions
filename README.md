<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

[![OpenSSF Best Practices](https://img.shields.io/badge/OpenSSF-Best_Practices-green?logo=opensourcesecurity)](https://www.bestpractices.dev/en/projects/new?repo_url=https://github.com/hyperpolymath/bag-of-actions)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0--1.0-blue.svg)](https://github.com/hyperpolymath/palimpsest-license) <embed
src="https://api.thegreenwebfoundation.org/greencheckimage/github.com"
data-link="https://www.thegreenwebfoundation.org/green-web-check/?url=github.com" />
image:<a href="https://img.shields.io/badge/Elixir-1.14+-4B275F?logo=elixir"
data-link="https://elixir-lang.org/">Elixir</a>
image:<a href="https://img.shields.io/badge/Zig-0.15+-F7A41D?logo=zig"
data-link="https://ziglang.org/">Zig</a>
[![Ephapax](https://img.shields.io/badge/Ephapax-Core-blue)](https://github.com/hyperpolymath/ephapax)

**Capability-Aware Continuation Mesh**

*Mobile work that follows resources, not static DAGs.*

# What is Bag-of-Actions?

Bag-of-Actions is a **distributed operating system for mobile
continuations**. Unlike traditional workflow engines that push tasks to
static queues, Bag-of-Actions represents units of work as
**Batons**—serialized execution states that search for environments
matching their required capabilities.

- **Resource Safety** — Linear types ensure work is never lost or
  duplicated.

- **Resumable execution** — Pause execution on one node, resume on
  another.

- **Capability Routing** — Dynamic dispatch based on hardware, identity,
  and trust.

- **Polylingual Mesh** — Orchestrated by Elixir, executed by Zig, proven
  by Idris.

# Implementation status

| Milestone | Status | Capability |
|----|----|----|
| 1\. Local Baton Cycle | ✓ Complete | Zig-hosted Wasm "Freeze/Thaw" state cycle. |
| 2\. Elixir Mesh | ✓ Complete | Distributed orchestration and Baton handoffs via process groups. |
| 3\. Verified ABI | ✓ Complete | Idris 2 formal proofs for linear resource preservation. |
| 4\. Guix Integration | ✓ Complete | Native Guix build orchestration via Zig FFIs. |

# Features

- **Linear Baton Logic** — Powered by **Ephapax**, ensuring one-time
  consumption of resources (tokens, memory, credits).

- **Mobile Wasm Contexts** — Native state capture of WebAssembly modules
  for seamless migration.

- **Guix-Powered Builds** — Integrated **Guix** orchestration for
  reproducible artifact creation during continuation steps.

- **Formal Estate Manifest** — Verified mapping of infrastructure
  capabilities (Linux, MacOS, GPU, Guix) to physical nodes.

- **Distributed Fault Tolerance** — Built on **Elixir/OTP**, leveraging
  the BEAM for robust node discovery and supervision.

- **Trust Attestation** — Cryptographic proof-chain for every state
  transition (Milestone 3).

# Quick start

```bash
# Build the Zig host
zig build

# Initialize a new Baton starting at counter 0
./zig-out/bin/bag_of_actions init

# Run the Elixir orchestrator
# This will trigger a recursive 10-step distributed handoff demo
cd bag
mix compile
elixir --sname mesh1 --cookie bag_secret -S mix run -e "Bag.Mesh.submit(0); :timer.sleep(15000)"
```

Wondering how this works? See [EXPLAINME.adoc](EXPLAINME.adoc).

# Repository layout

| Path | Purpose |
|----|----|
| `src/` | Zig source code for the Execution Host (Baton supervisor). |
| `bag/` | Elixir source code for the Mesh Orchestrator (Control Plane). |
| `verification/` | Idris 2 formal proofs and the **Estate Manifest** (`Bag.Estate`). |
| `nodes.scm` | Guix-native representation of the estate capabilities. |
| `baton.txt` | Persistent serialization format for the Milestone 1/2 Baton. |

# Documentation

- <a href="EXPLAINME.adoc" class="adoc">EXPLAINME</a> — Implementation
  receipts and evidence index.

- <a href="CONTRIBUTING.md" class="md">CONTRIBUTING</a> — How to add new
  capability matchers.

- <a href="SECURITY.md" class="md">SECURITY</a> — Attestation and secret
  handling protocols.

# License

Distributed under the <a href="LICENSE" class="0 (MPL-2 0)">MPL-2</a>.

*The future of work is mobile.*
