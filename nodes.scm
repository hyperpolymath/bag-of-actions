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
    (owner . "GitHub")))

;; Note: In a production Guix System deployment, this would
;; be used to generate node-specific operating-system configurations.
