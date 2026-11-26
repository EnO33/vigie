# Rust strict — l'équivalent de `strict: true` + `no-explicit-any`

Tout est **appliqué par la machine** (lints dans `Cargo.toml`, `clippy.toml`, `deny.toml`,
`cargo xtask arch`). Une règle qui n'est pas vérifiée automatiquement n'existe pas.

## Correspondance TypeScript → Rust

| Interdit en TS strict | Équivalent Rust interdit | Ce qu'on fait à la place | Appliqué par |
|---|---|---|---|
| `any` | `unsafe`, `transmute`, casts `as` | conversions `From` / `TryFrom` | `unsafe_code = forbid`, `clippy::as_conversions` |
| `unknown` | `serde_json::Value`, `Box<dyn Any>`, `Box<dyn Error>`, `anyhow` | types concrets, enums d'erreur `thiserror` | `clippy.toml` disallowed-types, `deny.toml` bans |
| `try/catch` | `std::panic::catch_unwind` | `Result<T, E>` + `?` | `clippy.toml` disallowed-methods |
| exception non gérée | `unwrap`, `expect`, `panic!`, `todo!`, `unreachable!`, indexation `v[i]`, overflow arithmétique | `?`, `.get(i)`, `checked_*`, `saturating_*` | lints `clippy::*` en `deny` |
| `// @ts-ignore` | `#[allow(...)]` | `#[expect(lint, reason = "...")]` justifié, relu par le reviewer | `clippy::allow_attributes`, `allow_attributes_without_reason` |
| `default:` dans un switch sur union | `_ =>` sur un enum | match exhaustif | `clippy::wildcard_enum_match_arm` |
| promesse ignorée | `Result` ignoré, `let _ = f()` | traiter ou propager | `unused_must_use`, `let_underscore_must_use` |
| `console.log` | `println!`, `dbg!` | `tracing` | `print_stdout`, `dbg_macro` |

Dans les **tests**, `unwrap`/`expect`/`panic` sont tolérés (`clippy.toml`) : un test qui échoue
*doit* paniquer.

## Gestion des erreurs

- Chaque crate expose **ses propres enums d'erreur** (`thiserror`), un variant par cas métier.
- Les erreurs d'une couche inférieure sont **enveloppées** (`#[from]`) ou **traduites**, jamais
  aplaties en `String`.
- Le binaire final renvoie `std::process::ExitCode` après un `match` exhaustif sur l'erreur racine.
- Profil release : `panic = "abort"`. Si une panique survient malgré tout (dépendance), elle est
  bruyante et immédiate, jamais avalée.

## Modélisation : « parse, don't validate »

- Pas de `String` / `u64` nus pour des concepts métier : **newtypes** (`TabId`, `WebUrl`, `ApiKey`).
- Un newtype ne se construit **que** via un constructeur faillible (`parse`, `TryFrom`) :
  un `WebUrl` existant est toujours valide.
- Les secrets ont un `Debug` masqué et ne sont jamais `Display`.
- États exclusifs → enum, pas de booléens combinés.

## Segmentation (architecture hexagonale)

```
crates/
  vigie-domain        types métier purs : pas d'I/O, pas d'async, pas d'horloge
  vigie-app           cas d'usage + ports (traits) ; dépend de domain uniquement
  vigie-adapter-*     implémentations des ports (moteur web, LLM, trousseau, stockage)
  vigie-shell         binaire, racine de composition : seul crate qui connaît tout le monde
xtask/                outillage (gate d'architecture)
```

| Crate | Peut dépendre de (workspace) | Dépendances externes |
|---|---|---|
| domain | rien | liste blanche (`xtask/src/rules.rs`) |
| app | domain | liste blanche |
| adapter-* | domain, app (jamais un autre adapter) | libre (passe `cargo deny`) |
| shell | tout sauf xtask | libre |

Toute violation fait échouer `cargo xtask arch`. Élargir une liste blanche = ADR obligatoire.

## Tests (TDD)

1. **Red** : écrire le test qui exprime le critère d'acceptation, le voir échouer.
2. **Green** : le code minimal qui passe.
3. **Refactor** : nettoyer, lints verts.

- Tests unitaires dans le module (`#[cfg(test)]`), tests d'intégration dans `tests/`.
- Les ports sont testés avec des **fakes** en mémoire, jamais de mock magique.
- `cargo mutants` sur le diff : un mutant survivant = un test manquant.
- Propriétés et parsers : `proptest` / fuzzing quand l'entrée vient du web.
