//! Adresse web validée (« parse, don't validate »).

use std::fmt;

use url::Url;

/// URL navigable : schéma `http` ou `https` uniquement.
///
/// Ne se construit que via [`WebUrl::parse`] : une valeur existante est toujours valide.
/// Pour ces schémas, la crate `url` garantit la présence d'un hôte non vide.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct WebUrl(Url);

/// Raisons pour lesquelles une saisie n'est pas une [`WebUrl`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum WebUrlError {
    /// La saisie n'est pas une URL syntaxiquement valide.
    #[error("URL invalide : {0}")]
    Malformed(#[from] url::ParseError),
    /// Schéma non autorisé (`file:`, `javascript:`, `data:`…).
    #[error("schéma non autorisé : {scheme}")]
    ForbiddenScheme {
        /// Schéma refusé, tel que normalisé par l'analyseur.
        scheme: String,
    },
}

impl WebUrl {
    /// Analyse une saisie (espaces de bord ignorés).
    ///
    /// # Errors
    ///
    /// [`WebUrlError::Malformed`] si la saisie n'est pas une URL,
    /// [`WebUrlError::ForbiddenScheme`] si son schéma n'est ni `http` ni `https`.
    pub fn parse(input: &str) -> Result<Self, WebUrlError> {
        let url = Url::parse(input.trim())?;
        match url.scheme() {
            "http" | "https" => Ok(Self(url)),
            other => Err(WebUrlError::ForbiddenScheme {
                scheme: other.to_owned(),
            }),
        }
    }

    /// Forme textuelle normalisée.
    #[must_use]
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl fmt::Display for WebUrl {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_https_and_normalizes() {
        let url = WebUrl::parse("  https://Example.com  ").unwrap();
        assert_eq!(url.as_str(), "https://example.com/");
        assert_eq!(url.to_string(), "https://example.com/");
    }

    #[test]
    fn accepts_http() {
        assert_eq!(
            WebUrl::parse("http://localhost:8080/a").unwrap().as_str(),
            "http://localhost:8080/a"
        );
    }

    #[test]
    fn rejects_dangerous_schemes() {
        for (input, scheme) in [
            ("javascript:alert(1)", "javascript"),
            ("file:///etc/passwd", "file"),
            ("data:text/html,<b>x</b>", "data"),
        ] {
            assert_eq!(
                WebUrl::parse(input),
                Err(WebUrlError::ForbiddenScheme {
                    scheme: scheme.to_owned()
                }),
                "{input}"
            );
        }
    }

    #[test]
    fn rejects_garbage() {
        assert!(matches!(
            WebUrl::parse("pas une url"),
            Err(WebUrlError::Malformed(_))
        ));
    }
}
