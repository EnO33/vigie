# ADR-0002 — Erreurs typées, zéro panique

- Statut : accepté
- Date : 2026-11-26

## Décision

- Erreurs : un enum `thiserror` par crate, propagation par `?`. `anyhow`/`eyre` bannis
  (équivalents de `unknown`).
- `unwrap`, `expect`, `panic!`, indexation, overflow arithmétique, `catch_unwind` interdits hors tests.
- `#[allow]` interdit ; seul `#[expect(lint, reason = "...")]` est accepté.
- Release : `panic = "abort"`.

## Conséquences

Code plus verbeux, mais chaque chemin d'échec est visible dans les signatures. Les paniques
résiduelles ne peuvent venir que de dépendances, et sont immédiatement visibles.
Détails : `docs/engineering/RUST_STRICT.md`.
