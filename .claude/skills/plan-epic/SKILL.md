---
name: plan-epic
description: Transforme un epic, une idée de la roadmap ou une issue trop grosse en stories Vigie prêtes pour un agent, liées en sub-issues, sans attendre de validation humaine. Use for "/plan-epic", "découpe cet epic", et par l'agent architect.
argument-hint: "<#epic, idée de la roadmap, ou #n à découper>"
---

# plan-epic

Entrée : `$ARGUMENTS`.

1. **Faits d'abord.** Si l'epic dépend de faits non vérifiés (API d'un moteur web, d'un fournisseur
   IA, d'un crate), la première story est une story de recherche qui les établit à la source et les
   consigne dans `docs/knowledge/LOG.md`. Les stories qui en dépendent sont « Bloquée par » elle.
2. Spécifier : skill `mattpocock-skills:to-spec` ; modéliser : `mattpocock-skills:domain-modeling` ;
   découper : `mattpocock-skills:to-tickets`. Respecter les couches (`ecc:hexagonal-architecture`).
3. Décision structurante (crate, moteur, format) → ADR dans `docs/adr/` (`ecc:architecture-decision-records`),
   versions établies par `check-versions`.
4. Créer les stories (`type:story`, `area:*`, `prio:*`), chacune avec critères Given/When/Then,
   types et erreurs attendus, plan de test, liens « Bloquée par #m ». Lier chacune à l'epic :
   `factory/bin/link-sub-issue.sh <epic> <story>`.
5. Label `status:ready` uniquement pour les stories sans fait « à vérifier » ni bloquant ouvert.
6. Pas d'attente de validation : la factory décide seule. Les arbitrages sont écrits dans l'epic
   (option retenue, alternatives, raison tirée de `VISION.md`).
7. Rapport : liens des stories dans l'ordre de livraison.
