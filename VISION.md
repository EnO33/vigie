# Vigie — Vision produit

> Fichier **protégé**. Seul l'humain (le « board ») le modifie. Les agents le lisent, ne l'éditent jamais.
> Vigie est un nom de code.

## Mission

Un navigateur assisté par IA où **l'utilisateur reste propriétaire de ses données et de son IA**.
Pas de serveur Vigie, pas de compte Vigie, pas de télémétrie. L'IA tourne avec la clé API de
l'utilisateur (BYOK) ou un modèle local.

## Pour qui

Des utilisateurs exigeants (devs, power users) qui aiment les navigateurs « augmentés »
mais refusent d'envoyer leur navigation à un tiers dont le modèle économique est opaque.

## Principes non négociables (ordre de priorité)

1. **Confidentialité par construction.** Aucune donnée ne quitte la machine sauf vers le
   fournisseur IA choisi par l'utilisateur, et seulement sur une action explicite de sa part.
   Zéro télémétrie, zéro analytics, zéro « phone home ».
2. **Le web est hostile.** Tout contenu de page est une *donnée*, jamais une *instruction*.
   L'IA est en lecture seule par défaut. Toute action (clic, formulaire, navigation) proposée par
   l'IA exige une confirmation explicite. Défense contre l'injection de prompt dès la conception.
3. **Secrets au coffre.** Les clés API vivent dans le trousseau de l'OS, jamais en clair sur disque,
   jamais dans les logs, jamais dans un `Debug`.
4. **Robustesse.** Le navigateur ne crashe pas sur une entrée inattendue : toute erreur est typée,
   gérée et remontée proprement (voir `docs/engineering/RUST_STRICT.md`).
5. **Performance.** Démarrage < 1 s, interface fluide, empreinte mémoire maîtrisée.
6. **Remplaçabilité.** Moteur web, fournisseurs IA, stockage : tout est un adaptateur derrière un port.

## Fonctionnalités cibles (MVP → v1)

| Jalon | Contenu |
|---|---|
| M1 — Coquille | Fenêtre, onglets verticaux, barre d'URL, navigation, historique local |
| M2 — IA BYOK | Panneau IA, fournisseurs Anthropic / OpenAI / Mistral / Ollama, clés au trousseau |
| M3 — Contexte | « Discuter avec cet onglet / ces onglets », résumé, citations des sources |
| M4 — Skills | Prompts réutilisables définis par l'utilisateur, stockés localement |
| M5 — Espaces | Espaces de travail (groupes d'onglets persistants), profils isolés |

## Non-objectifs

- Écrire un moteur de rendu. On embarque un moteur existant (voir ADR moteur).
- Synchronisation cloud, comptes, backend Vigie.
- Agent autonome qui agit sur le web sans confirmation.
- Support mobile.

## Indicateurs de succès

- 0 requête réseau non initiée par l'utilisateur (vérifiable par test d'intégration).
- 0 `panic` en production (lints + tests de mutation + fuzzing).
- Couverture de lignes ≥ 80 % sur `domain` et `app`.
