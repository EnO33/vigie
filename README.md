# Vigie

Navigateur assisté par IA, **sans serveur, sans télémétrie, en BYOK**. Écrit en Rust.
Construit et maintenu par une **software factory autonome** d'agents Claude.

| Document | Contenu |
|---|---|
| [VISION.md](VISION.md) | Vision produit (board uniquement) |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Roadmap tenue par le Product Owner |
| [docs/factory/FACTORY.md](docs/factory/FACTORY.md) | Organisation, machine à états, gates |
| [docs/engineering/RUST_STRICT.md](docs/engineering/RUST_STRICT.md) | Rust strict (équivalent TS strict) |
| [docs/engineering/FRESHNESS.md](docs/engineering/FRESHNESS.md) | Anti-obsolescence des agents |
| [docs/adr/](docs/adr/) | Décisions d'architecture |

## Structure

```
crates/vigie-domain   types métier purs
crates/vigie-app      cas d'usage + ports
xtask/                gate d'architecture (cargo xtask arch)
factory/              orchestrateur, gates, hooks, plugins.lock (protégé)
.claude/agents/       les 7 rôles de la factory (protégé)
.claude/skills/       skills du projet (protégé)
.githooks/            commit-msg : aucune attribution IA (protégé)
docker/               image des agents
```

## Démarrer la factory

1. Crée le dépôt GitHub et pousse ce code. Active Dependabot.
2. Règle de branche sur `main` : status check requis `factory/gates`, pas de push direct,
   **contournement autorisé pour les administrateurs** (c'est ainsi que tu merges tes PR `board`).
3. Token GitHub fine-grained **de ton compte**, limité au dépôt (contents, issues, pull requests,
   commit statuses). Seul ton compte apparaîtra sur GitHub.
4. `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN`.
5. `cp .env.example .env` et remplis-le (dont ton adresse noreply GitHub).
6. Labels : `bash factory/bin/setup-labels.sh` (une fois, avec ton propre `gh`).
7. `git config core.hooksPath .githooks` dans ton clone (refuse les attributions IA chez toi aussi).
8. `docker compose up -d --build`, puis `docker compose logs -f`.

Pause : ouvre une issue avec le label `factory:halt`. Reprise : ferme-la.
Changer une règle protégée : PR avec le label `board`, mergée par toi.

## Depuis Zed

Ouvre `D:/projects/vigie` dans Zed, puis **Shift+Alt+T** (`task: spawn`) et tape `Vigie`.
Tâches principales : gates complets (Docker), tests, clippy strict, démarrer / logs / arrêter la
factory, pause et reprise (`factory:halt`), Claude Code, `/check-versions`.
rust-analyzer affiche directement les lints clippy stricts (`.zed/settings.json`).
Prérequis : Git pour Windows (Git Bash), Docker Desktop, `gh` connecté, rustup.

Sous Windows sans Visual Studio Build Tools, rust-analyzer a besoin de la toolchain GNU
(linker MinGW inclus, ~1 Go), activée pour ce dossier seulement :

```bash
rustup toolchain install stable-x86_64-pc-windows-gnu --profile minimal --component clippy,rustfmt,rust-src
rustup override set stable-x86_64-pc-windows-gnu   # dans le dossier du projet
```

L'override reste sur ta machine (pas dans le dépôt) ; la factory et les tâches « (Docker) »
utilisent la toolchain Linux de l'image.

## Vérifier en local

```bash
factory/bin/in-agent-image.sh bash factory/gates.sh --local   # dans l'image des agents
```
