# La software factory

Une entreprise miniature : chaque agent a **un rôle, un périmètre, des droits**. Le backlog GitHub
est la seule mémoire partagée. Aucun humain dans la boucle de décision : les décisions sont prises
par les agents et **validées par des gates objectifs**, pas par un autre LLM seul.

## Organigramme

| Rôle | Agent (`.claude/agents/`) | Modèle | Produit | Ne fait jamais |
|---|---|---|---|---|
| Board (humain) | — | — | `VISION.md`, rapport hebdo lu en asynchrone, kill switch | bloquer le flux |
| Product Owner | `product-owner` | opus | Epics, priorités, `docs/ROADMAP.md` | écrire du code |
| Architecte | `architect` | opus | Sub-issues prêtes à coder, ADR | implémenter une story |
| Développeur | `developer` | sonnet | Une PR par story, en TDD | toucher aux fichiers protégés |
| Reviewer | `reviewer` | opus | Revue qualité (`/code-review`, `/simplify`) | corriger lui-même le code |
| Auditeur sécurité | `security-auditor` | opus | Revue sécurité (`/security-review`) + modèle de menace | approuver une PR non auditée |
| Steward dépendances | `dependency-steward` | haiku | Tri des PR Dependabot | monter une version majeure sans issue |
| Veille techno | `tech-watch` | sonnet | `docs/knowledge/LOG.md`, issues de mise à jour | modifier du code |

## Machine à états (labels GitHub)

```
Epic   : status:backlog ─PO─▶ status:ready ─Architecte─▶ status:in-progress ─(toutes sub-issues closes)─▶ fermée
Story  : status:ready ─Dev─▶ status:in-progress ─PR─▶ status:in-review
         status:in-review ─Reviewer + Sécu─▶ review:approved + security:approved ─gates verts─▶ merge (fermée)
                          └──────────────▶ status:changes-requested ─Dev─▶ status:in-review
         status:blocked : dépendance non résolue, l'architecte arbitre
```

Labels annexes : `type:epic|story|bug|chore`, `prio:p0|p1|p2`, `area:domain|app|adapter|shell|factory`.

## Boucle de l'orchestrateur (`factory/orchestrator.sh`)

Système **pull** : on finit avant de commencer. À chaque tick, la première règle qui s'applique gagne :

1. PR en `status:changes-requested` → `developer` corrige.
2. PR en `status:in-review` sans verdict → `reviewer` puis `security-auditor`.
3. PR approuvée deux fois → `factory/gates.sh` → merge squash si vert, sinon `changes-requested`.
4. PR Dependabot ouverte → `dependency-steward`.
5. Story `status:ready` (WIP < `WIP_LIMIT`) → `developer`.
6. Epic `status:ready` sans sub-issues → `architect`.
7. Rien de prêt → `product-owner` planifie le prochain epic.

Une fois par semaine : `tech-watch`, puis rapport du `product-owner` (issue `type:report`).
Quand la limite d'usage Claude est atteinte, l'orchestrateur attend et reprend (backoff).

## Gates (`factory/gates.sh`) — ce qui remplace la revue humaine

| Gate | Commande | Bloque si |
|---|---|---|
| Format | `cargo fmt --check` | diff de formatage |
| Lints stricts | `cargo clippy --all-targets -- -D warnings` | un seul warning |
| Tests | `cargo test --workspace --locked` | un échec |
| Architecture | `cargo xtask arch` | dépendance interdite entre couches |
| Supply chain | `cargo deny check` | CVE, licence, crate banni (`anyhow`…), source inconnue |
| Couverture | `cargo llvm-cov --fail-under-lines 80` | < 80 % |
| Mutation | `cargo mutants --in-diff` | un mutant survivant sur le code modifié |
| Intégrité | diff des fichiers protégés | une PR affaiblit les règles |
| Attribution | commits, titre et corps de PR vs `factory/attribution.patterns` | une mention de Claude/IA, un `Co-Authored-By` |

Le résultat est publié en **commit status** `factory/gates` sur GitHub. Tout tourne en local, dans Docker.
Le merge (squash) se fait au nom du board, avec un message maîtrisé, et seulement si la tête de PR
est celle que les gates ont validée (`--match-head-commit`).

## Un seul compte GitHub : le tien

La factory utilise ton token et ton identité Git : **seul ton compte apparaît** comme auteur et
contributeur. Aucun compte bot, aucune attribution IA (réglage `attribution` de Claude Code vide,
hook `commit-msg`, hook PreToolUse et gate « attribution »). Les commits squash des PR Dependabot
sont aussi signés de ton adresse ; Dependabot reste l'auteur de ses PR, c'est inévitable.

## Fichiers protégés (anti-triche)

Un agent pressé peut être tenté d'affaiblir un lint pour passer. Les agents ne peuvent pas modifier
(hook PreToolUse) et les gates refusent toute PR qui modifie : `VISION.md`, `CLAUDE.md`, `docs/factory/`, `docs/engineering/`,
`clippy.toml`, `deny.toml`, `rustfmt.toml`, `rust-toolchain.toml`, `.claude/`, `.zed/`, `.githooks/`, `.github/`, `docker/`, `docker-compose.yml`,
`factory/` (dont `plugins.lock`), `xtask/`, `.cargo/`, ou les sections `[workspace.lints*]` et
`[profile*]` du `Cargo.toml` racine.

Le board change ces fichiers dans une PR portant le label **`board`** : la factory l'ignore
totalement, et le board la merge lui-même (droit d'administrateur sur la règle de branche).

## Skills et plugins

Épinglés par SHA dans `factory/plugins.lock` (dernière release ≥ 7 jours), installés dans l'image
Docker par `factory/bin/install-plugins.sh`. Correspondance rôle → skills : `CLAUDE.md`.

| Source | Apport |
|---|---|
| caveman (JuliusBrussee) | communication compressée (hooks) |
| ponytail (DietrichGebert) | simplicité, YAGNI (hooks), `ponytail-review` |
| ECC (affaan-m) | `rust-patterns`, `rust-testing`, `hexagonal-architecture`, `architecture-decision-records`, `security-review` ; ~28 hooks Node |
| mattpocock/skills | `to-spec`, `to-tickets`, `domain-modeling`, `code-review`, `diagnosing-bugs`, `tdd` |
| impeccable (pbakaus), hallmark (Nutlope) | qualité de l'interface (crate shell) |
| security-audit (Cloudflare) | audit complet via `security-audit-run` |
| Skills du projet | `check-versions`, `tdd`, `work-issue`, `next-issue`, `plan-epic`, `security-audit-run` (adaptées de tes projets) |

## Économie de tokens

- **caveman** pour tout ce qui est échange inter-agents, commentaires de revue, logs.
  Les issues, ADR et la doc restent en prose claire (audit humain possible).
- Petites stories (≤ 1 jour humain, ≤ ~300 lignes de diff) : moins de contexte par session.
- Modèle adapté au rôle (haiku → sonnet → opus).
- `WIP_LIMIT=1` au départ.
