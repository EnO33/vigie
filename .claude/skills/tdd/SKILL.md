---
name: tdd
description: Boucle red-green-refactor pour Vigie en Rust — test qui échoue d'abord, code minimal, refactor sous vert, couche la plus intérieure d'abord (domain, app, adapters, shell). Use for any new behaviour or bug fix, "/tdd", "en TDD".
argument-hint: "<comportement à ajouter ou bug à corriger>"
---

# tdd

Comportement : `$ARGUMENTS`.

## 0. Choisir la couche (la plus intérieure d'abord)

1. `crates/vigie-domain` : types et fonctions purs (newtypes, invariants, transitions d'état).
   Tests simples, aucun fake.
2. `crates/vigie-app` : cas d'usage avec des **fakes** des ports écrits dans le module de test
   (`InMemory…`, `Failing…`). Jamais de crate de mock.
3. `crates/vigie-adapter-*` : contre des fixtures réelles anonymisées (`tests/fixtures/`, avec un
   `.md` voisin : source, version, date). Aucun appel réseau réel dans les tests.
4. `crates/vigie-shell` : composition uniquement ; un test d'intégration qui démarre et s'arrête.

## 1. Red

- Un test pour le plus petit comportement suivant, nommé d'après lui :
  `fn closing_active_tab_activates_right_neighbour()`.
- Lancer uniquement lui : `cargo test -p <crate> <nom>`. Il doit échouer **sur l'assertion**,
  pas sur une erreur de compilation. Bug : le premier test reproduit le bug.

## 2. Green

- Le minimum de code qui passe. Aucune option ni abstraction « pour plus tard ».
- Toujours dans les règles de `docs/engineering/RUST_STRICT.md` : `Result` typé, pas de panique.

## 3. Refactor

- Sous vert uniquement : duplication, noms, fonction > ~40 lignes, fichier > ~300 lignes.
- `cargo clippy -p <crate> --all-targets -- -D warnings` vert.

## 4. Élargir, puis finir

- Cas suivants : entrée vide, invalide, limite (`u64::MAX`, chaîne vide, Unicode), erreur de port,
  entrée hostile venue du web (pour tout ce qui parse).
- Propriétés : `proptest` quand l'espace d'entrée est grand (vérifier la version avec `check-versions`).
- Fini : `factory/gates.sh --local` vert (couverture ≥ 80 %, mutants tués sur le diff).

## Règles

- Pas de code de production sans un test qui l'a exigé. Jamais affaiblir ni supprimer un test pour passer.
- Pas de réseau, pas d'horloge réelle (horloge injectée par un port), pas de `sleep`, pas de dépendance d'ordre.
- Pas de `git stash` : committer le travail en cours sur la branche (la PR est squashée).
