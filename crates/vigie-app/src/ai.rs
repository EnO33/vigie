//! Fournisseurs d'IA et clés API (BYOK).

use std::fmt;

/// Fournisseurs d'IA supportés.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ProviderKind {
    /// API Anthropic (clé requise).
    Anthropic,
    /// API `OpenAI` (clé requise).
    OpenAi,
    /// API Mistral (clé requise).
    Mistral,
    /// Modèle local via Ollama : rien ne quitte la machine, pas de clé.
    Ollama,
}

impl ProviderKind {
    /// Le fournisseur exige-t-il une clé API ?
    #[must_use]
    pub const fn requires_api_key(self) -> bool {
        match self {
            Self::Anthropic | Self::OpenAi | Self::Mistral => true,
            Self::Ollama => false,
        }
    }
}

/// Clé API. Jamais affichée : `Debug` est masqué et `Display` n'existe pas.
#[derive(Clone, PartialEq, Eq)]
pub struct ApiKey(String);

/// Raisons pour lesquelles une saisie n'est pas une [`ApiKey`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum ApiKeyError {
    /// Saisie vide (ou uniquement des espaces).
    #[error("clé API vide")]
    Empty,
    /// Espace au milieu de la clé : probablement un copier-coller incomplet.
    #[error("la clé API contient des espaces")]
    ContainsWhitespace,
}

impl ApiKey {
    /// Analyse une saisie utilisateur (espaces de bord ignorés).
    ///
    /// # Errors
    ///
    /// [`ApiKeyError`] si la saisie est vide ou contient des espaces.
    pub fn parse(raw: &str) -> Result<Self, ApiKeyError> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err(ApiKeyError::Empty);
        }
        if trimmed.chars().any(char::is_whitespace) {
            return Err(ApiKeyError::ContainsWhitespace);
        }
        Ok(Self(trimmed.to_owned()))
    }

    /// Valeur en clair, à n'utiliser qu'au moment d'appeler le fournisseur.
    #[must_use]
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for ApiKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ApiKey(***)")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_local_provider_needs_no_key() {
        assert!(ProviderKind::Anthropic.requires_api_key());
        assert!(ProviderKind::OpenAi.requires_api_key());
        assert!(ProviderKind::Mistral.requires_api_key());
        assert!(!ProviderKind::Ollama.requires_api_key());
    }

    #[test]
    fn parses_and_trims_key() {
        assert_eq!(ApiKey::parse("  sk-abc \n").unwrap().expose(), "sk-abc");
    }

    #[test]
    fn rejects_empty_and_split_keys() {
        assert_eq!(ApiKey::parse("   "), Err(ApiKeyError::Empty));
        assert_eq!(
            ApiKey::parse("sk-a bc"),
            Err(ApiKeyError::ContainsWhitespace)
        );
    }

    #[test]
    fn debug_never_leaks_the_secret() {
        let key = ApiKey::parse("sk-secret").unwrap();
        let shown = format!("{key:?}");
        assert_eq!(shown, "ApiKey(***)");
        assert!(!shown.contains("sk-secret"));
    }
}
