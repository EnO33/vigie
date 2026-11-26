//! Cas d'usage : l'utilisateur renseigne la clé API d'un fournisseur.

use crate::ai::{ApiKey, ApiKeyError, ProviderKind};
use crate::ports::{SecretStore, SecretStoreError};

/// Échecs possibles de [`configure_provider`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ConfigureProviderError {
    /// Le fournisseur (local) n'utilise pas de clé.
    #[error("{0:?} n'utilise pas de clé API")]
    KeyNotRequired(ProviderKind),
    /// La saisie n'est pas une clé valide.
    #[error(transparent)]
    InvalidKey(#[from] ApiKeyError),
    /// Le coffre à secrets a échoué.
    #[error(transparent)]
    Store(#[from] SecretStoreError),
}

/// Valide la clé saisie puis la range dans le coffre.
///
/// # Errors
///
/// Voir [`ConfigureProviderError`].
pub fn configure_provider<S: SecretStore>(
    store: &mut S,
    provider: ProviderKind,
    raw_key: &str,
) -> Result<(), ConfigureProviderError> {
    if !provider.requires_api_key() {
        return Err(ConfigureProviderError::KeyNotRequired(provider));
    }
    let key = ApiKey::parse(raw_key)?;
    store.store(provider, key)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    /// Fake en mémoire du port : pas de mock magique.
    #[derive(Default)]
    struct InMemoryStore(HashMap<ProviderKind, ApiKey>);

    impl SecretStore for InMemoryStore {
        fn store(&mut self, provider: ProviderKind, key: ApiKey) -> Result<(), SecretStoreError> {
            self.0.insert(provider, key);
            Ok(())
        }

        fn load(&self, provider: ProviderKind) -> Result<Option<ApiKey>, SecretStoreError> {
            Ok(self.0.get(&provider).cloned())
        }
    }

    struct LockedStore;

    impl SecretStore for LockedStore {
        fn store(&mut self, _: ProviderKind, _: ApiKey) -> Result<(), SecretStoreError> {
            Err(SecretStoreError::Unavailable {
                reason: "verrouillé".to_owned(),
            })
        }

        fn load(&self, _: ProviderKind) -> Result<Option<ApiKey>, SecretStoreError> {
            Err(SecretStoreError::Unavailable {
                reason: "verrouillé".to_owned(),
            })
        }
    }

    #[test]
    fn stores_valid_key() {
        let mut store = InMemoryStore::default();
        configure_provider(&mut store, ProviderKind::Anthropic, " sk-ant ").unwrap();
        let saved = store.load(ProviderKind::Anthropic).unwrap().unwrap();
        assert_eq!(saved.expose(), "sk-ant");
    }

    #[test]
    fn local_provider_refuses_a_key() {
        let mut store = InMemoryStore::default();
        assert_eq!(
            configure_provider(&mut store, ProviderKind::Ollama, "sk"),
            Err(ConfigureProviderError::KeyNotRequired(ProviderKind::Ollama))
        );
        assert_eq!(store.load(ProviderKind::Ollama).unwrap(), None);
    }

    #[test]
    fn invalid_key_is_not_stored() {
        let mut store = InMemoryStore::default();
        assert_eq!(
            configure_provider(&mut store, ProviderKind::OpenAi, ""),
            Err(ConfigureProviderError::InvalidKey(ApiKeyError::Empty))
        );
        assert_eq!(store.load(ProviderKind::OpenAi).unwrap(), None);
    }

    #[test]
    fn store_failure_is_propagated() {
        assert!(matches!(
            configure_provider(&mut LockedStore, ProviderKind::Mistral, "sk"),
            Err(ConfigureProviderError::Store(
                SecretStoreError::Unavailable { .. }
            ))
        ));
        assert!(LockedStore.load(ProviderKind::Mistral).is_err());
    }
}
