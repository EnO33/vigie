# Journal de veille (tenu par `tech-watch`)

Faits vérifiés, datés, sourcés. Plus récent en haut.

## 2026-11-26 — veille hebdomadaire

Toolchain
- `rustc 1.100.0 (2026-11-09)` / `cargo 1.100.0` = stable courante : `channel-rust-stable.toml`
  (`date = "2026-11-12"`, version `1.100.0`).
- `RELEASES.md` (branche master de rust-lang/rust) annonce `1.100.1 (2026-11-27)`, correctif de
  régression `Iterator` (const). Non publié à ce jour sur le canal stable : non vérifié côté
  installation, à surveiller la semaine prochaine.
- 1.100.0 : type `!` stabilisé, `extern "custom"`, allocateurs personnalisés (`Allocator`, `Vec::new_in`),
  `bool::toggle`, `str::trim_prefix`/`trim_suffix`, `Box::map`/`Rc::map`/`Arc::map`, `core::mem::DropGuard`.
  Aucun n'est requis par le code actuel. Pas de nouvelle édition.
- Clippy 1.100 (`CHANGELOG.md` de rust-clippy) : nouveaux lints `option_zip_none` (suspicious) et
  `needless_nonzero_get` (complexity), déjà couverts par `clippy::all` = deny. `unwrap_used` :
  `allow-unwrap-in-tests` vaut aussi pour les tests d'intégration. Rien à activer.

Dépendances directes (`cargo info` + API crates.io)
- thiserror 2.0.21 (2026-09-23), serde 1.0.229 (2026-07-18), cargo_metadata 0.23.1 (2025-11-12),
  url 2.5.9 (2026-11-20), toml 1.2.3 (2026-11-25) : tous à la dernière version, aucune yankée,
  aucun écart de version majeure, aucune dépréciation constatée.
- Point d'attention : url 2.5.9 (6 jours) et toml 1.2.3 (1 jour) sont plus récents que le délai
  de 7 jours. Dernières versions éligibles : url 2.5.8, toml 1.2.1 (2026-11-06) ; toml 1.2.2 date de 5 jours.
- cargo_metadata : dernière release 2025-11-12, soit ~12 mois. Seuil d'abandon à surveiller.

Plugins (`factory/plugins.lock`, API releases GitHub)
- ponytail v5.3.3, ECC v2.2.3, mattpocock/skills v1.3.2 : toujours la dernière release.
- hallmark et security-audit : pas de release, pin sur `main` inchangé (HEAD identique au SHA épinglé).
- impeccable : pin `skill-v4.10.0` (2026-11-18). Plus récentes : `skill-v4.11.0` (2026-11-24),
  `skill-v4.11.1` (2026-11-26), toutes < 7 jours, donc notées, pas adoptées. Éligible : v4.11.0 le 2026-12-01.
- caveman : pin v4.1.0 ; `v4.2.0` publiée le 2026-11-22 (4 jours), éligible le 2026-11-29.
  Tag annoté `b32e5af2…` : à déréférencer vers le commit avant épinglage (non fait).
- Aucune release de plus de 7 jours en attente : pas d'issue `area:factory`.

## 2026-11-26 — état initial (bootstrap)

- Toolchain : `rustc 1.100.0`, `cargo 1.100.0` (image `rust:1-bookworm`).
- Édition 2024, resolver 3.
- Versions résolues via `cargo info` : thiserror 2.0.21, url 2.5.9, cargo_metadata 0.23.1,
  serde 1.0.229, toml 1.2.3.
- `cargo_metadata` 0.23 : `Package::name` est un newtype `PackageName` (plus un `String`),
  `DependencyKind` a un variant caché `Unknown`. Source : `src/lib.rs`, `src/dependency.rs`.
- Cargo signale les dépendances de workspace inutilisées (`cargo::unused_workspace_dependencies`).
- Clippy : lint `assert_is_empty` (pedantic) disponible ; `disallowed-types` signale les chemins
  introuvables sauf `allow-invalid = true`.
