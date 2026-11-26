# Fraîcheur — ne pas coder avec les connaissances périmées des agents

Les modèles ont une date de coupure. Ils connaissent des versions de crates et des API qui ont
peut-être changé. Règle d'or : **la mémoire du modèle n'est jamais une source de vérité**.

## Sources de vérité, par ordre

1. **Le code source exact de la version résolue**, présent localement :
   `~/.cargo/registry/src/*/<crate>-<version>/` (la version est dans `Cargo.lock`).
2. **La doc générée localement** : `cargo doc -p <crate> --no-deps`, puis lire `target/doc/`.
3. **Le registre** : `cargo info <crate>` (dernière version, features, MSRV).
4. Les notes de version / CHANGELOG du crate (dans le dossier source, ou en ligne).
5. En dernier : la mémoire du modèle, uniquement pour des concepts stables du langage.

## Règles appliquées

| Règle | Mécanisme |
|---|---|
| Toolchain toujours à jour | `rust-toolchain.toml` → `channel = "stable"` (flottant) ; image Docker `rust:1` |
| Édition la plus récente | `edition = "2024"`, montée d'édition = issue ouverte par `tech-watch` |
| Jamais de version écrite de mémoire | avant d'ajouter un crate : `cargo info <crate>`, puis version dans `[workspace.dependencies]`, puis `cargo add <crate> -p <membre>` |
| API dépréciées refusées | lint `deprecated = "deny"` |
| Dépendances suivies | Dependabot (cargo, docker) quotidien + agent `dependency-steward` |
| Vulnérabilités / crates yankés | `cargo deny check` dans les gates |
| Contexte injecté à chaque session | hook `SessionStart` : date du jour, `rustc -V`, `cargo -V`, dépendances directes résolues |
| Veille hebdomadaire | agent `tech-watch` : notes de version Rust + crates clés → `docs/knowledge/LOG.md` + issues |

## Délai de 7 jours et périmètre

- Toujours la **dernière version stable** publiée depuis **au moins 7 jours**. Plus récente : notée,
  pas adoptée, sauf correctif de sécurité. Jamais de pré-release.
- La règle vaut pour **tout** ce qui a une version : toolchain, crates, images Docker, Node, CLI,
  plugins Claude Code (`factory/plugins.lock`), réglages de Claude Code (schéma officiel).
- Procédure unique : skill `check-versions`.

## Ne pas conclure trop vite

Un indice n'est pas une preuve. Avant d'affirmer qu'une API existe, qu'une version corrige un bug,
qu'un réglage fait ce qu'on croit : une commande ou une lecture de source, citée. Ce qui n'a pas pu
être vérifié est écrit « non vérifié ».

## Quand un agent n'est pas sûr d'une API

Il **lit la source** de la version résolue avant d'écrire le code. Un reviewer qui voit un appel
dont l'existence n'est pas évidente demande la preuve (chemin du fichier source).
