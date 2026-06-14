;; SPDX-License-Identifier: MPL-2.0
;; Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
;; Bag-of-Actions: Estate Manifest (Guix Edition)
;;
;; This file provides the Guix-native definition of your estate,
;; mirroring the formal Idris 2 Bag.Estate manifest.

(define-module (bag estate)
  #:use-module (guix gexp)
  #:use-module (gnu packages)
  #:export (estate-nodes))

(define estate-nodes
  '((name . "mesh-laptop")
    (capabilities . (macos guix trusted-host))
    (owner . "Jonathan"))
  '((name . "mesh-server-1")
    (capabilities . (linux gpu guix trusted-host))
    (owner . "Core-Infrastructure"))
  '((name . "mesh-github-runner")
    (capabilities . (linux secret-access))
    (owner . "GitHub"))
  ;; The hypatia "brain" (Elixir merge-orchestration host): emits/reads only and
  ;; deliberately WITHOUT secret-access, so a merge Baton (required-cap
  ;; secret-access) can never run here and must migrate to mesh-github-runner —
  ;; the token-free-brain invariant. Mirrors src/estate.zig / Bag.Estate.idr.
  '((name . "mesh-hypatia-brain")
    (capabilities . (linux trusted-host))
    (owner . "Jonathan")))

;; Note: In a production Guix System deployment, this would
;; be used to generate node-specific operating-system configurations.
