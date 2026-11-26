# ADR-0001 — Workspace Cargo hexagonal

- Statut : accepté
- Date : 2026-11-26

## Contexte

Un navigateur mélange logique métier (onglets, sessions, politique IA) et intégrations lourdes
(moteur web, réseau, trousseau). Les agents doivent pouvoir tester la logique sans interface
graphique, dans Docker, et le moteur web doit rester remplaçable.

## Décision

Workspace Cargo découpé en couches (`domain` → `app` → `adapter-*` → `shell`), dépendances
uniquement vers l'intérieur, vérifiées par `cargo xtask arch`. Les ports sont des traits dans
`vigie-app`. `vigie-shell` est la seule racine de composition.

## Conséquences

- `domain` et `app` se testent en millisecondes, sans moteur ni réseau.
- Changer de moteur (WebView2 → CEF) = écrire un nouvel adaptateur.
- Coût : plus de crates, et une liste blanche de dépendances à maintenir (ADR pour l'élargir).
