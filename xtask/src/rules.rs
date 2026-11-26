//! Règles d'architecture (ADR-0001). Pur : aucune I/O, entièrement testé.

use std::fmt;

/// Couche d'un crate, déduite de son nom.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Layer {
    Domain,
    Application,
    Adapter,
    Shell,
    Tooling,
}

impl Layer {
    pub(crate) fn of(crate_name: &str) -> Option<Self> {
        match crate_name {
            "vigie-domain" => Some(Self::Domain),
            "vigie-app" => Some(Self::Application),
            "vigie-shell" => Some(Self::Shell),
            "xtask" => Some(Self::Tooling),
            other if other.starts_with("vigie-adapter-") => Some(Self::Adapter),
            _ => None,
        }
    }

    /// Dépendances internes autorisées : uniquement vers l'intérieur de l'hexagone.
    const fn may_depend_on(self, target: Self) -> bool {
        match self {
            Self::Domain | Self::Tooling => false,
            Self::Application => matches!(target, Self::Domain),
            Self::Adapter => matches!(target, Self::Domain | Self::Application),
            Self::Shell => matches!(target, Self::Domain | Self::Application | Self::Adapter),
        }
    }

    /// Dépendances externes autorisées. `None` = libre (contrôlé par `cargo deny`).
    /// Élargir une liste = ADR obligatoire.
    const fn external_allowlist(self) -> Option<&'static [&'static str]> {
        match self {
            Self::Domain => Some(&["thiserror", "url"]),
            Self::Application => Some(&["thiserror"]),
            Self::Adapter | Self::Shell | Self::Tooling => None,
        }
    }
}

/// Vue d'un crate du workspace, réduite à ce que les règles examinent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CrateInfo {
    pub(crate) name: String,
    /// Dépendances `normal` et `build` vers d'autres crates du workspace.
    pub(crate) internal_deps: Vec<String>,
    /// Dépendances `normal` et `build` venant d'un registre.
    pub(crate) external_deps: Vec<String>,
    /// Le manifeste contient `[lints] workspace = true`.
    pub(crate) inherits_workspace_lints: bool,
}

/// Violation d'une règle d'architecture.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Violation {
    UnknownLayer { krate: String },
    ForbiddenInternal { from: String, to: String },
    ExternalNotAllowed { krate: String, dependency: String },
    MissingWorkspaceLints { krate: String },
}

impl fmt::Display for Violation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownLayer { krate } => write!(
                f,
                "{krate} : nom hors convention (vigie-domain, vigie-app, vigie-adapter-*, vigie-shell)"
            ),
            Self::ForbiddenInternal { from, to } => {
                write!(f, "{from} → {to} : dépendance interdite entre couches")
            }
            Self::ExternalNotAllowed { krate, dependency } => write!(
                f,
                "{krate} → {dependency} : hors liste blanche de la couche (ADR requis)"
            ),
            Self::MissingWorkspaceLints { krate } => {
                write!(f, "{krate} : `[lints] workspace = true` manquant")
            }
        }
    }
}

/// Vérifie toutes les règles sur l'ensemble des crates du workspace.
pub(crate) fn check(crates: &[CrateInfo]) -> Vec<Violation> {
    crates
        .iter()
        .flat_map(|krate| check_one(krate, crates))
        .collect()
}

fn check_one(krate: &CrateInfo, all: &[CrateInfo]) -> Vec<Violation> {
    let mut violations = Vec::new();
    if !krate.inherits_workspace_lints {
        violations.push(Violation::MissingWorkspaceLints {
            krate: krate.name.clone(),
        });
    }
    let Some(layer) = Layer::of(&krate.name) else {
        violations.push(Violation::UnknownLayer {
            krate: krate.name.clone(),
        });
        return violations;
    };
    for target in &krate.internal_deps {
        let allowed = all
            .iter()
            .any(|other| &other.name == target)
            .then(|| Layer::of(target))
            .flatten()
            .is_some_and(|target_layer| layer.may_depend_on(target_layer));
        if !allowed {
            violations.push(Violation::ForbiddenInternal {
                from: krate.name.clone(),
                to: target.clone(),
            });
        }
    }
    if let Some(allowlist) = layer.external_allowlist() {
        violations.extend(
            krate
                .external_deps
                .iter()
                .filter(|dep| !allowlist.contains(&dep.as_str()))
                .map(|dep| Violation::ExternalNotAllowed {
                    krate: krate.name.clone(),
                    dependency: dep.clone(),
                }),
        );
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    fn krate(name: &str, internal: &[&str], external: &[&str]) -> CrateInfo {
        CrateInfo {
            name: name.to_owned(),
            internal_deps: internal.iter().map(|s| (*s).to_owned()).collect(),
            external_deps: external.iter().map(|s| (*s).to_owned()).collect(),
            inherits_workspace_lints: true,
        }
    }

    fn workspace(extra: CrateInfo) -> Vec<CrateInfo> {
        vec![
            krate("vigie-domain", &[], &["thiserror", "url"]),
            krate("vigie-app", &["vigie-domain"], &["thiserror"]),
            krate(
                "vigie-adapter-keyring",
                &["vigie-app", "vigie-domain"],
                &["keyring"],
            ),
            krate("vigie-adapter-sqlite", &["vigie-app"], &[]),
            krate(
                "vigie-shell",
                &["vigie-app", "vigie-adapter-keyring"],
                &["tracing"],
            ),
            krate("xtask", &[], &["cargo_metadata"]),
            extra,
        ]
    }

    #[test]
    fn layers_follow_naming_convention() {
        assert_eq!(Layer::of("vigie-domain"), Some(Layer::Domain));
        assert_eq!(Layer::of("vigie-app"), Some(Layer::Application));
        assert_eq!(Layer::of("vigie-adapter-cef"), Some(Layer::Adapter));
        assert_eq!(Layer::of("vigie-shell"), Some(Layer::Shell));
        assert_eq!(Layer::of("xtask"), Some(Layer::Tooling));
        assert_eq!(Layer::of("utils"), None);
    }

    #[test]
    fn clean_workspace_has_no_violation() {
        let crates = workspace(krate("vigie-adapter-ollama", &["vigie-app"], &["reqwest"]));
        assert_eq!(check(&crates), Vec::new());
    }

    #[test]
    fn domain_cannot_depend_on_app() {
        let crates = vec![
            krate("vigie-domain", &["vigie-app"], &[]),
            krate("vigie-app", &[], &[]),
        ];
        assert_eq!(
            check(&crates),
            vec![Violation::ForbiddenInternal {
                from: "vigie-domain".to_owned(),
                to: "vigie-app".to_owned()
            }]
        );
    }

    #[test]
    fn app_cannot_depend_on_adapter_or_shell() {
        let crates = vec![
            krate("vigie-app", &["vigie-adapter-x", "vigie-shell"], &[]),
            krate("vigie-adapter-x", &[], &[]),
            krate("vigie-shell", &[], &[]),
        ];
        assert_eq!(check(&crates).len(), 2);
    }

    #[test]
    fn adapters_cannot_depend_on_each_other() {
        let crates = workspace(krate("vigie-adapter-bad", &["vigie-adapter-sqlite"], &[]));
        assert_eq!(
            check(&crates),
            vec![Violation::ForbiddenInternal {
                from: "vigie-adapter-bad".to_owned(),
                to: "vigie-adapter-sqlite".to_owned()
            }]
        );
    }

    #[test]
    fn tooling_cannot_depend_on_product() {
        let crates = vec![
            krate("xtask", &["vigie-domain"], &[]),
            krate("vigie-domain", &[], &[]),
        ];
        assert_eq!(check(&crates).len(), 1);
    }

    #[test]
    fn dependency_on_unknown_internal_crate_is_forbidden() {
        let crates = vec![krate("vigie-shell", &["vigie-ghost"], &[])];
        assert_eq!(
            check(&crates),
            vec![Violation::ForbiddenInternal {
                from: "vigie-shell".to_owned(),
                to: "vigie-ghost".to_owned()
            }]
        );
    }

    #[test]
    fn domain_external_allowlist_is_enforced() {
        let crates = vec![krate("vigie-domain", &[], &["url", "tokio"])];
        assert_eq!(
            check(&crates),
            vec![Violation::ExternalNotAllowed {
                krate: "vigie-domain".to_owned(),
                dependency: "tokio".to_owned()
            }]
        );
    }

    #[test]
    fn app_external_allowlist_is_enforced() {
        let crates = vec![krate("vigie-app", &[], &["reqwest"])];
        assert_eq!(check(&crates).len(), 1);
    }

    #[test]
    fn unknown_layer_and_missing_lints_are_reported() {
        let mut rogue = krate("helpers", &[], &[]);
        rogue.inherits_workspace_lints = false;
        assert_eq!(
            check(&[rogue]),
            vec![
                Violation::MissingWorkspaceLints {
                    krate: "helpers".to_owned()
                },
                Violation::UnknownLayer {
                    krate: "helpers".to_owned()
                },
            ]
        );
    }

    #[test]
    fn violations_are_readable() {
        let messages: Vec<String> = [
            Violation::UnknownLayer {
                krate: "a".to_owned(),
            },
            Violation::ForbiddenInternal {
                from: "a".to_owned(),
                to: "b".to_owned(),
            },
            Violation::ExternalNotAllowed {
                krate: "a".to_owned(),
                dependency: "c".to_owned(),
            },
            Violation::MissingWorkspaceLints {
                krate: "a".to_owned(),
            },
        ]
        .iter()
        .map(ToString::to_string)
        .collect();
        assert!(messages[0].contains("hors convention"));
        assert!(messages[1].contains("a → b"));
        assert!(messages[2].contains("a → c"));
        assert!(messages[3].contains("[lints]"));
    }
}
