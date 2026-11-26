#!/usr/bin/env bash
# Crée (ou met à jour) les labels de la machine à états. Idempotent.
set -euo pipefail

label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null; echo "label $1"; }

label type:epic   5319e7 "Epic produit (product-owner)"
label type:story  1d76db "Story prête à coder (architect)"
label type:bug    d73a4a "Défaut"
label type:chore  c5def5 "Maintenance, dépendances, outillage"
label type:report fbca04 "Rapport hebdomadaire au board"

label status:backlog           ededed "Pas encore prêt"
label status:ready             0e8a16 "Prêt à être pris"
label status:in-progress       1d76db "En cours"
label status:in-review         5319e7 "PR en revue"
label status:changes-requested d93f0b "Retour au développeur"
label status:blocked           b60205 "Bloqué : arbitrage de l'architecte"

label review:approved   0e8a16 "Revue qualité OK"
label security:approved 0e8a16 "Audit sécurité OK"

label prio:p0 b60205 "Critique"
label prio:p1 d93f0b "Important"
label prio:p2 fbca04 "Normal"

label area:domain  bfd4f2 "crates/vigie-domain"
label area:app     bfd4f2 "crates/vigie-app"
label area:adapter bfd4f2 "crates/vigie-adapter-*"
label area:shell   bfd4f2 "crates/vigie-shell"
label area:factory bfd4f2 "Outillage de la factory (board)"

label factory:halt 000000 "Issue ouverte = la factory se met en pause"
label board        6f42c1 "PR du board humain : ignorée par la factory, mergée par le board"
