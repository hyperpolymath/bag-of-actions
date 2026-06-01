-- SPDX-License-Identifier: PMPL-1.0-or-later
||| Bag.Protocol: Base types and capability algebra for Bag-of-Actions.
module Bag.Protocol

%default total

||| Core hardware and identity capabilities.
public export
data Capability
  = Linux
  | MacOS
  | GPU
  | TrustedHost String
  | SecretAccess String

public export
Eq Capability where
  Linux == Linux = True
  MacOS == MacOS = True
  GPU == GPU = True
  (TrustedHost s1) == (TrustedHost s2) = s1 == s2
  (SecretAccess s1) == (SecretAccess s2) = s1 == s2
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
capToTag (TrustedHost _)  = 4
capToTag (SecretAccess _) = 5
