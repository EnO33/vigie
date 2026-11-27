//! Titre de page nettoyé et borné : il vient d'un site hostile.

use std::fmt;

/// Titre de page : sans caractère de contrôle, espaces normalisés, au plus
/// [`PageTitle::MAX_CHARS`] caractères.
///
/// Ne se construit que via [`PageTitle::parse`].
///
/// Des caractères de catégorie Cf, non `is_control`, sont **retirés** :
/// - contrôles bidirectionnels (`U+202A..=U+202E`, `U+2066..=U+2069`, `U+200E`, `U+200F`,
///   `U+061C`) : ils inversent l'affichage pour usurper un site ;
/// - invisibles (`U+00AD`, `U+180E`, `U+200B`, `U+2060..=U+2064`, `U+206A..=U+206F`,
///   `U+FEFF`, `U+FFF9..=U+FFFB`) : `Pay\u{200B}Pal` s'afficherait « `PayPal` » ;
/// - Tags (`U+E0000..=U+E007F`) : un LLM les lit comme de l'ASCII, l'utilisateur ne les voit
///   pas (injection de prompt cachée). Conséquence assumée : les drapeaux de subdivision
///   (🏴 Écosse…) perdent leur suite et s'affichent en drapeau noir simple.
///
/// `U+200C` (ZWNJ) et `U+200D` (ZWJ) sont **conservés** : ils sont nécessaires au persan
/// et aux séquences emoji.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PageTitle(String);

/// Raisons pour lesquelles une saisie n'est pas un [`PageTitle`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PageTitleError {
    /// Titre vide après nettoyage.
    #[error("titre vide après nettoyage")]
    Empty,
}

fn is_hidden_format(c: char) -> bool {
    matches!(
        c,
        '\u{00AD}'
            | '\u{061C}'
            | '\u{180E}'
            | '\u{200B}'
            | '\u{200E}'..='\u{200F}'
            | '\u{202A}'..='\u{202E}'
            | '\u{2060}'..='\u{2064}'
            | '\u{2066}'..='\u{206F}'
            | '\u{FEFF}'
            | '\u{FFF9}'..='\u{FFFB}'
            | '\u{E0000}'..='\u{E007F}'
    )
}

impl PageTitle {
    /// Longueur maximale, en `char`.
    pub const MAX_CHARS: usize = 512;

    /// Nettoie et borne un titre brut.
    ///
    /// Les blancs (dont `\n`, `\t`) deviennent un espace unique ; les autres contrôles
    /// et les invisibles (bidi, Tags, ZWSP…) sont retirés ; troncature à [`Self::MAX_CHARS`] `char`.
    ///
    /// # Errors
    ///
    /// [`PageTitleError::Empty`] si rien ne subsiste.
    pub fn parse(raw: &str) -> Result<Self, PageTitleError> {
        let kept: String = raw
            .chars()
            .filter(|c| c.is_whitespace() || !(c.is_control() || is_hidden_format(*c)))
            .collect();
        let joined = kept.split_whitespace().collect::<Vec<_>>().join(" ");
        let truncated: String = joined.chars().take(Self::MAX_CHARS).collect();
        // La coupe peut laisser un espace final.
        let title = truncated.trim_end();
        if title.is_empty() {
            return Err(PageTitleError::Empty);
        }
        Ok(Self(title.to_owned()))
    }

    /// Texte nettoyé.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for PageTitle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleans_controls_and_spaces() {
        let t = PageTitle::parse("  Exemple\u{0007}  de   page\n");
        assert_eq!(t.as_ref().map(PageTitle::as_str), Ok("Exemple de page"));
        assert_eq!(t.map(|t| t.to_string()), Ok("Exemple de page".to_owned()));
    }

    #[test]
    fn newline_separates_words() {
        let t = PageTitle::parse("a\nb\tc");
        assert_eq!(t.as_ref().map(PageTitle::as_str), Ok("a b c"));
    }

    #[test]
    fn empty_after_cleaning() {
        for raw in ["", "   ", "\u{0000}\u{001b}", "\u{202E}"] {
            assert_eq!(PageTitle::parse(raw), Err(PageTitleError::Empty), "{raw:?}");
        }
    }

    #[test]
    fn truncates_by_chars() {
        let raw = "é".repeat(600);
        let t = PageTitle::parse(&raw);
        assert_eq!(
            t.map(|t| t.as_str().chars().count()),
            Ok(PageTitle::MAX_CHARS)
        );
    }

    #[test]
    fn truncation_does_not_leave_trailing_space() {
        let raw = format!("{} b", "a".repeat(PageTitle::MAX_CHARS - 1));
        let t = PageTitle::parse(&raw);
        assert_eq!(
            t.as_ref().map(|t| t.as_str().chars().count()),
            Ok(PageTitle::MAX_CHARS - 1)
        );
    }

    #[test]
    fn bidi_override_is_removed() {
        let t = PageTitle::parse("abc\u{202E}def");
        assert_eq!(t.as_ref().map(PageTitle::as_str), Ok("abcdef"));
    }

    #[test]
    fn hidden_format_families_are_removed() {
        for (raw, want) in [
            ("Banque\u{E0069}\u{E0067}\u{E0020}", "Banque"),
            ("Pay\u{200B}Pal", "PayPal"),
            ("a\u{FEFF}\u{2060}b", "ab"),
            ("a\u{00AD}b", "ab"),
            ("x\u{FFF9}y", "xy"),
        ] {
            let t = PageTitle::parse(raw);
            assert_eq!(t.as_ref().map(PageTitle::as_str), Ok(want), "{raw:?}");
        }
        assert_eq!(PageTitle::parse("\u{E0041}"), Err(PageTitleError::Empty));
        assert_eq!(PageTitle::parse("\u{200B}"), Err(PageTitleError::Empty));
    }

    #[test]
    fn zwj_and_zwnj_are_kept() {
        let t = PageTitle::parse("a\u{200D}b\u{200C}c");
        assert_eq!(t.as_ref().map(PageTitle::as_str), Ok("a\u{200D}b\u{200C}c"));
    }

    #[test]
    fn invariants_hold_on_sample() {
        let atoms = [
            "",
            " ",
            "a",
            "é",
            "\n",
            "\t",
            "\u{0}",
            "\u{7}",
            "\u{202E}",
            "\u{2066}",
            "\u{E0041}",
            "\u{200B}",
            "\u{FEFF}",
            "\u{200D}",
            "\u{a0}",
            "\u{3000}",
            "😀",
            "x y",
        ];
        let mut samples = vec!["é".repeat(600), format!("{} b", "a".repeat(511))];
        for a in atoms {
            for b in atoms {
                for c in atoms {
                    samples.push(format!("{a}{b}{c}"));
                    samples.push(format!("{a} {b}\n{c}"));
                }
            }
        }
        for raw in &samples {
            if let Ok(t) = PageTitle::parse(raw) {
                let s = t.as_str();
                assert!(!s.chars().any(|c| c.is_control() || is_hidden_format(c)));
                // Liste de référence indépendante du prédicat.
                assert!(!s.contains(['\u{200B}', '\u{FEFF}', '\u{202E}', '\u{E0041}']));
                assert_eq!(s, s.trim());
                assert!(s.chars().count() <= PageTitle::MAX_CHARS);
                assert_eq!(PageTitle::parse(s), Ok(t.clone()));
            }
        }
    }
}
