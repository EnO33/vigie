# Journal de veille (tenu par `tech-watch`)

Faits vérifiés, datés, sourcés. Plus récent en haut.

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
