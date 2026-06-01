-- SPDX-License-Identifier: PMPL-1.0-or-later
||| Bag.Baton: Formal model of the mobile continuation unit.
module Bag.Baton

import Bag.Protocol

%default total

||| A Baton represents a mobile continuation indexed by its required capabilities.
public export
record Baton where
  constructor MkBaton
  id          : String
  counter     : Int
  requiredCap : List Capability

||| Linearity witness: A Baton is 'Consumed' when it is passed or completed.
public export
data BatonStatus = Floating | Executing | Completed

||| Proof that a Baton exists in exactly one place in the mesh.
public export
data IsLinear : Baton -> BatonStatus -> Type where
  AtRest : (b : Baton) -> IsLinear b Floating
  InFlight : (b : Baton) -> (node : String) -> IsLinear b Executing
  Finished : (b : Baton) -> IsLinear b Completed
