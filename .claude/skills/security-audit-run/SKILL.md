---
name: security-audit-run
description: Lance un audit de sécurité complet de Vigie avec la skill security-audit (Cloudflare) et ouvre des issues pour ce qu'il confirme. Use for "/security-audit-run", "audit de sécurité complet", avant une release, et chaque fin d'epic par l'agent security-auditor.
argument-hint: "[quick|standard]"
---

# security-audit-run

Profil : `$ARGUMENTS`, `quick` si vide.

1. Charger la skill `security-audit` en **mode audit complet** avec ce profil. Cible : ce dépôt au
   commit courant de `main` (arbre propre ; le dire s'il ne l'est pas). Domaines compagnons :
   `AI-AND-LLM.md` (injection de prompt, contenu de page traité comme donnée, actions de l'IA),
   `DESKTOP-MOBILE-AND-LOCAL-IPC.md` (application de bureau, IPC moteur ↔ interface, trousseau),
   `CLIENT-SIDE.md` (contenu web non fiable, schémas d'URL), `MEMORY-SAFETY-AND-BINARY.md`
   (FFI éventuelle du moteur), `SUPPLY-CHAIN-AND-RELEASE.md` (crates, images Docker, plugins épinglés).
2. Dossier de sortie hors du dépôt : `~/security-audit-skill/vigie/run-<N>` (défaut de la skill).
   Jamais de fichier d'audit dans le dépôt.
3. Périmètre à donner aux auditeurs : navigateur de bureau en Rust embarquant un moteur web ; l'IA
   tourne avec la clé API de l'utilisateur (trousseau de l'OS) ou un modèle local ; aucune donnée ne
   sort sans action explicite, et seulement vers le fournisseur choisi ; aucun serveur Vigie.
4. Rien de contrôlé par la cible ne s'exécute hors du bac à sable exigé par la skill. Aucune vraie
   clé API pendant l'audit : les constats qui en exigent une restent `needs_validation`.
5. À la fin, lire `REPORT.md`. Pour chaque constat `confirmed` : une issue `type:bug`, gravité dans
   le titre, sections Constat / À faire, sauf si elle existe. Les `needs_validation` : une seule issue
   récapitulative. Un constat exploitable contre les utilisateurs : **pas d'issue publique**, ouvrir
   un avis de sécurité GitHub privé (`gh api repos/{owner}/{repo}/security-advisories -X POST ...`)
   et le signaler dans le rapport hebdomadaire.
6. Rapport : profil, déclaration de couverture du rapport, issues ouvertes.
