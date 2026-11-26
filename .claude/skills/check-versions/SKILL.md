---
name: check-versions
description: Vérifie à la source, maintenant, les dernières versions stables de la toolchain Rust, des crates, des images Docker, de Node, des plugins Claude Code épinglés et des CLI, puis met à jour ce qui est autorisé et ouvre des issues pour le reste. Use for "/check-versions", "est-ce qu'on est à jour", avant d'ajouter ou d'épingler quoi que ce soit, avant toute affirmation sur une version ou une API.
---

# check-versions

Une version ne s'écrit **jamais** de mémoire. Une conclusion ne se tire **jamais** sans preuve :
chaque ligne du rapport cite la commande qui l'établit. Ce qui n'a pas pu être vérifié est écrit
« non vérifié », jamais deviné.

## Sources, interrogées maintenant

| Quoi | Commande |
|---|---|
| Rust stable | `curl -fsSL https://static.rust-lang.org/dist/channel-rust-stable.toml \| grep -m1 -A2 '^\[pkg.rustc\]'` puis `rustc -V` |
| Crate | `cargo info <crate>` (version, MSRV, licence) ; dates : `curl -fsSL https://crates.io/api/v1/crates/<crate>/versions \| jq -r '.versions[:5][] \| "\(.num) \(.created_at) yanked=\(.yanked)"'` |
| API d'un crate | source de la version résolue : `~/.cargo/registry/src/*/<crate>-<version>/` (après `cargo fetch`) |
| Image Docker | `curl -fsSL https://hub.docker.com/v2/repositories/library/<image>/tags/<tag> \| jq -r .last_updated` ; digest : `docker buildx imagetools inspect <image>:<tag>` |
| Node LTS | `curl -fsSL https://nodejs.org/dist/index.json \| jq -r '[.[] \| select(.lts != false)][0] \| "\(.version) \(.date)"'` |
| Plugin / skill (`factory/plugins.lock`) | `gh api repos/<o>/<r>/releases --jq '[.[] \| select(.prerelease==false and .draft==false)][0:3][] \| "\(.tag_name) \(.published_at)"'`, puis tag → commit : `gh api repos/<o>/<r>/git/ref/tags/<tag> --jq '.object.type+" "+.object.sha'` (si `tag`, déréférencer avec `git/tags/<sha>` jusqu'à `commit`) |
| Option d'une CLI | `<cli> --help` de la version installée (`claude`, `gh`, `cargo <outil>`) |
| Réglage Claude Code | `curl -fsSL https://json.schemastore.org/claude-code-settings.json \| jq '.properties.<clé>'` |

## Règles

1. **Délai de 7 jours** : une release de moins de 7 jours est notée, pas adoptée, sauf correctif
   de sécurité (avis RustSec, GHSA, CVE cité).
2. **Pas de pré-release.**
3. **Montée majeure** : lire les notes de version et le guide de migration dans la source avant
   tout ; c'est une story à part (`type:chore`, `build(deps)!:`).
4. **Fichiers protégés** (`factory/plugins.lock`, `rust-toolchain.toml`, `docker/`, lints) :
   l'agent ne les modifie pas, il ouvre une issue `area:factory` avec la ligne exacte à changer,
   la source et la date de vérification.
5. Croiser deux sources quand c'est possible (registre + tag Git, Docker Hub + digest).

## Étapes

1. Lister ce qui est épinglé : `Cargo.toml` (`[workspace.dependencies]`), `Cargo.lock`,
   `docker/agent.Dockerfile`, `factory/plugins.lock`, `rust-toolchain.toml`.
2. Interroger chaque source ci-dessus.
3. Appliquer ce qui est autorisé (crates patch/minor hors délai) via `cargo update -p <crate>`
   ou une story ; ouvrir une issue pour chaque élément protégé ou majeur.
4. Ajouter une entrée datée dans `docs/knowledge/LOG.md`.
5. Rapport : **changé**, **retenu (et pourquoi)**, **non vérifié**.
