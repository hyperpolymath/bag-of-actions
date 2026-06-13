-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Bag.Estate: Formal definition of the physical infrastructure nodes and their capabilities.
module Bag.Estate

import Bag.Protocol
import Data.List

%default total

||| A Node in the Bag-of-Actions mesh.
public export
record Node where
  constructor MkNode
  name         : String
  capabilities : List Capability

||| The canonical Estate Manifest.
||| This serves as the ground truth for the orchestrator's routing decisions.
public export
estate : List Node
estate =
  [ MkNode "mesh-laptop"        [MacOS, Guix, TrustedHost "Jonathan", Zig]
  , MkNode "mesh-server-1"      [Linux, GPU, Guix, TrustedHost "Core-Infrastructure", Zig, Rust, Cargo, Deno]
  , MkNode "mesh-github-runner" [Linux, SecretAccess "GitHub-Deploy-Token"]
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
