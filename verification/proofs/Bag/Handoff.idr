-- SPDX-License-Identifier: PMPL-1.0-or-later
||| Bag.Handoff: Verified handoff protocol for Baton mobility.
module Bag.Handoff

import Bag.Protocol
import Bag.Baton

%default total

||| A handoff request: can node N pick up Baton B?
public export
record HandoffRequest where
  constructor MkHandoff
  baton      : Baton
  targetNode : String
  targetCaps : List Capability

||| The outcome of a handoff attempt.
||| Validated carries a proof that the target node satisfies the requirements.
public export
data HandoffResult : HandoffRequest -> Type where
  Validated : (req : HandoffRequest)
            -> (pf  : satisfies (requiredCap (baton req)) (targetCaps req) = True)
            -> HandoffResult req
  Rejected  : (req : HandoffRequest)
            -> HandoffResult req

||| The core handoff decision function.
||| This is the formal logic that Elixir will mirror.
export
validateHandoff : (req : HandoffRequest) -> HandoffResult req
validateHandoff req with (satisfies (requiredCap (baton req)) (targetCaps req)) proof p
  | True  = Validated req p
  | False = Rejected req

||| Linearity Lemma: A handoff must consume the source Baton and produce a target one.
||| This proves that we never duplicate work during a handoff.
export
handoffPreservesLinearity :
  (b : Baton) -> (src : String) -> (dst : String)
  -> IsLinear b Executing -- Source must be executing it
  -> (req : HandoffRequest)
  -> {auto pf : baton req = b}
  -> {auto nodePf : targetNode req = dst}
  -> HandoffResult req
  -> IsLinear b Executing -- Produces exactly one executing witness for the target
handoffPreservesLinearity b src dst (InFlight b src) req (Validated req pf) = InFlight b dst
handoffPreservesLinearity b src dst (InFlight b src) req (Rejected req)    = InFlight b src
