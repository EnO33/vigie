---
name: work-issue
description: Mène une story Vigie de la lecture à une PR verte prête pour la revue — lire, vérifier les faits, brancher, construire en TDD, lancer les gates, ouvrir la PR. Use for "/work-issue 12", "travaille sur l'issue 12", et par l'agent developer.
argument-hint: "<numéro d'issue>"
---

# work-issue

Issue : `$ARGUMENTS`. Sans numéro : lancer `next-issue` et prendre la première.

## 1. Comprendre

1. `gh issue view <n> --json number,title,body,labels,state,comments`. S'arrêter (commentaire
   caveman sur l'issue) si elle est close, pas `status:ready`, bloquée par une issue ouverte,
   ou a déjà une PR ouverte (`gh pr list --state open --search "<n> in:body"`).
2. Lire `CLAUDE.md`, les ADR cités, et uniquement les fichiers touchés.
3. **Vérifier avant de conclure.** Chaque fait dont dépend l'issue (API d'un crate, option d'une CLI,
   comportement d'un moteur) est vérifié à la source (`check-versions`, source du crate dans
   `~/.cargo/registry/src/`, `--help`). Un fait non vérifiable → `status:blocked` + commentaire
   à l'architecte, pas de supposition.

## 2. Planifier

- Worktree depuis `origin/main` à jour :
  `git fetch origin && git worktree add ../wt/<n> -b <type>/<n>-<slug> origin/main`.
- Transformer les critères d'acceptation en liste de tests. Chercher l'existant (newtypes, ports,
  erreurs) et l'étendre plutôt que dupliquer.

## 3. Construire

- Skill `tdd`, couche la plus intérieure d'abord. Pour du Rust idiomatique : skills
  `ecc:rust-patterns`, `ecc:rust-testing`. Pour l'interface (crate shell) : `impeccable`, `hallmark`.

## 4. Vérifier

1. `factory/gates.sh --local` vert.
2. `/simplify` sur le diff ; appliquer ce qui retire duplication ou code mort, puis gates à nouveau.

## 5. Livrer

1. Commit : sujet Conventional avec scope, corps qui dit pourquoi, écrit dans un fichier temporaire
   hors dépôt et committé avec `git commit -F <fichier>`. **Aucune mention de Claude ou d'IA, aucune
   ligne Co-Authored-By** (le hook `commit-msg` refuse).
2. `git push -u origin <branche>`.
3. `gh pr create --base main --body-file <fichier>` ; titre = sujet du commit ; corps :
   `## Quoi`, `## Pourquoi`, `## Risques`, `## Validation` (gates, versions vérifiées et comment),
   `Closes #<n>`. Label `status:in-review`.
4. Ne pas merger. Rapport caveman : lien PR, gates, ce qui n'est pas vérifié.
