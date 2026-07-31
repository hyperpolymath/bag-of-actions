-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Bag.Estate: Formal definition of the physical infrastructure nodes and their capabilities.
module Bag.Estate

import Bag.Protocol
import Data.List

%default total

||| A Node in the Bag-of-Actions mesh.
||| `cost` is the tropical (min-plus) money grade of running a unit of work here:
||| owned nodes ≈ free (electricity only); the github-runner is the paid route.
||| The planner minimises this subject to capability ⇒ "relegate to the cheapest
||| capable node; reserve the paid route for work whose capabilities only it has".
public export
record Node where
  constructor MkNode
  name         : String
  capabilities : List Capability
  cost         : Nat

||| The canonical Estate Manifest.
||| This serves as the ground truth for the orchestrator's routing decisions.
public export
estate : List Node
estate =
  [ MkNode "mesh-laptop"        [MacOS, Guix, TrustedHost "Jonathan", Zig] 2
  , MkNode "mesh-server-1"      [Linux, GPU, Guix, TrustedHost "Core-Infrastructure", Zig, Rust, Cargo, Deno, Scorecard, Wasm, Idris2, Just] 1
  , MkNode "mesh-github-runner" [Linux, SecretAccess "GitHub-Deploy-Token"] 100
  -- The hypatia "brain" (Elixir merge-orchestration host): emits/reads only, and
  -- deliberately has NO `SecretAccess` capability. A merge Baton requires
  -- `SecretAccess`, so `cheapestCapable` can never select the brain for it — the
  -- token-free-brain invariant proved as a capability fact: the Baton must
  -- migrate to `mesh-github-runner`.
  , MkNode "mesh-hypatia-brain" [Linux, TrustedHost "Jonathan"] 1
  ]

||| Lookup a node by name in the estate.
public export
findNode : String -> Maybe Node
findNode target = find (\n => name n == target) estate

||| Verify that a specific node in the estate satisfies a set of requirements.
public export
nodeSatisfies : (nodeName : String) -> (requirements : List Capability) -> Bool
nodeSatisfies name reqs =
  case findNode name of
       Nothing => False
       Just n  => satisfies reqs (capabilities n)

||| The routing objective (tropical ⊕ over feasible nodes): among nodes that
||| satisfy the requirements, the least-cost one. Infeasible nodes contribute
||| nothing (they are simply not in `feasible`) — capability and cost are one
||| decision. This is the formal spec the Elixir planner mirrors.
public export
cheapestCapable : (requirements : List Capability) -> Maybe Node
cheapestCapable reqs =
  case filter (\n => satisfies reqs (capabilities n)) estate of
       []        => Nothing
       (x :: xs) => Just (foldl (\best, n => if cost n < cost best then n else best) x xs)
