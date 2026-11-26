//! Outillage du workspace Vigie.
//!
//! `cargo xtask arch` : vérifie les règles d'architecture (ADR-0001).

mod rules;

use std::fs;
use std::io::{self, Write};
use std::process::ExitCode;

use cargo_metadata::{DependencyKind, MetadataCommand, Package};
use serde::Deserialize;

use crate::rules::CrateInfo;

#[derive(Debug, thiserror::Error)]
enum XtaskError {
    #[error("usage : cargo xtask arch")]
    Usage,
    #[error("commande inconnue : {0}")]
    UnknownCommand(String),
    #[error("cargo metadata a échoué : {0}")]
    Metadata(#[from] cargo_metadata::Error),
    #[error("lecture impossible : {0}")]
    Io(#[from] io::Error),
    #[error("manifeste illisible ({path}) : {source}")]
    Manifest {
        path: String,
        source: toml::de::Error,
    },
    #[error("{0} violation(s) d'architecture")]
    Violations(usize),
}

/// Seule partie du manifeste qui nous intéresse : `[lints] workspace = true`.
#[derive(Deserialize)]
struct Manifest {
    lints: Option<LintsSection>,
}

#[derive(Deserialize)]
struct LintsSection {
    workspace: Option<bool>,
}

fn main() -> ExitCode {
    let mut out = io::stderr().lock();
    let result = run(std::env::args().nth(1).as_deref(), &mut out);
    let reported = match &result {
        Ok(()) => writeln!(out, "architecture : OK"),
        Err(error) => writeln!(out, "erreur : {error}"),
    };
    match (result, reported) {
        (Ok(()), Ok(())) => ExitCode::SUCCESS,
        (Ok(()) | Err(_), Err(_)) | (Err(_), Ok(())) => ExitCode::FAILURE,
    }
}

fn run(command: Option<&str>, out: &mut impl Write) -> Result<(), XtaskError> {
    match command {
        Some("arch") => {
            let metadata = MetadataCommand::new().no_deps().exec()?;
            let crates = metadata
                .workspace_packages()
                .into_iter()
                .map(crate_info)
                .collect::<Result<Vec<_>, _>>()?;
            let violations = rules::check(&crates);
            for violation in &violations {
                writeln!(out, "✗ {violation}")?;
            }
            if violations.is_empty() {
                Ok(())
            } else {
                Err(XtaskError::Violations(violations.len()))
            }
        }
        Some(other) => Err(XtaskError::UnknownCommand(other.to_owned())),
        None => Err(XtaskError::Usage),
    }
}

fn crate_info(package: &Package) -> Result<CrateInfo, XtaskError> {
    let mut internal_deps = Vec::new();
    let mut external_deps = Vec::new();
    for dependency in &package.dependencies {
        match dependency.kind {
            DependencyKind::Normal | DependencyKind::Build | DependencyKind::Unknown => {
                if dependency.path.is_some() {
                    internal_deps.push(dependency.name.clone());
                } else {
                    external_deps.push(dependency.name.clone());
                }
            }
            DependencyKind::Development => {}
        }
    }
    let raw = fs::read_to_string(&package.manifest_path)?;
    let manifest: Manifest = toml::from_str(&raw).map_err(|source| XtaskError::Manifest {
        path: package.manifest_path.to_string(),
        source,
    })?;
    Ok(CrateInfo {
        name: package.name.to_string(),
        internal_deps,
        external_deps,
        inherits_workspace_lints: manifest
            .lints
            .and_then(|lints| lints.workspace)
            .unwrap_or(false),
    })
}
