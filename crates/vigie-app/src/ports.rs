//! Ports : ce dont l'application a besoin, sans savoir comment c'est fait.
//!
//! Chaque port a un adaptateur de production (`vigie-adapter-*`) et un fake en mémoire pour les tests.

use crate::ai::{ApiKey, ProviderKind};

/// Coffre à secrets. En production : le trousseau de l'OS.
pub trait SecretStore {
    /// Enregistre (ou remplace) la clé d'un fournisseur.
    ///
    /// # Errors
    ///
    /// [`SecretStoreError`] si le coffre est inaccessible.
    fn store(&mut self, provider: ProviderKind, key: ApiKey) -> Result<(), SecretStoreError>;

    /// Lit la clé d'un fournisseur, si elle existe.
    ///
    /// # Errors
    ///
    /// [`SecretStoreError`] si le coffre est inaccessible.
    fn load(&self, provider: ProviderKind) -> Result<Option<ApiKey>, SecretStoreError>;
}

/// Échecs du coffre à secrets.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SecretStoreError {
    /// Le coffre ne répond pas (verrouillé, service absent…).
    #[error("coffre à secrets indisponible : {reason}")]
    Unavailable {
        /// Explication fournie par l'adaptateur, sans aucun secret.
        reason: String,
    },
}

#[cfg(test)]
pub(crate) mod fake_page_engine;
pub mod page_engine;

pub use page_engine::{HistoryStep, PageEngine, PageEngineError, PageEvent, PageEventKind};
