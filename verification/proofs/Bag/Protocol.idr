-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Bag.Protocol: Base types and capability algebra for Bag-of-Actions.
module Bag.Protocol

%default total

||| Core hardware, identity, and toolchain capabilities.
||| Toolchain capabilities (Zig/Rust/Cargo/Deno) let a CI-check Baton be routed
||| only to a node that actually has the toolchain the check needs.
||| External-tool capabilities (Scorecard) indicate that a node has the runtime
||| required to execute an external security/analysis tool as a Baton payload.
public export
data Capability
  = Linux
  | MacOS
  | GPU
  | Guix
  | TrustedHost String
  | SecretAccess String
  | Zig
  | Rust
  | Cargo
  | Deno
  | Scorecard
  | Wasm

public export
Eq Capability where
  Linux == Linux = True
  MacOS == MacOS = True
  GPU == GPU = True
  Guix == Guix = True
  (TrustedHost s1) == (TrustedHost s2) = s1 == s2
  (SecretAccess s1) == (SecretAccess s2) = s1 == s2
  Zig == Zig = True
  Rust == Rust = True
  Cargo == Cargo = True
  Deno == Deno = True
  Scorecard == Scorecard = True
  Wasm == Wasm = True
  _ == _ = False

||| Check if a node's provided capabilities satisfy the Baton's requirements.
public export
satisfies : (required : List Capability) -> (provided : List Capability) -> Bool
satisfies [] _ = True
satisfies (r :: rs) provided =
  if r `elem` provided
     then satisfies rs provided
     else False

||| C-ABI encoding for capabilities (tags for Zig/Elixir).
public export
capToTag : Capability -> Int
capToTag Linux            = 1
capToTag MacOS            = 2
capToTag GPU              = 3
capToTag Guix             = 4
capToTag (TrustedHost _)  = 5
capToTag (SecretAccess _) = 6
capToTag Zig              = 7
capToTag Rust             = 8
capToTag Cargo            = 9
capToTag Deno             = 10
capToTag Scorecard        = 11
capToTag Wasm             = 12
