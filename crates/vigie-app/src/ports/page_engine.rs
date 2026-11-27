//! Port `PageEngine` : la couture derrière laquelle le moteur de rendu reste remplaçable
//! (ADR-0005). Aucun type de moteur n'apparaît ici.

use vigie_domain::{PageTitle, TabId, WebUrl};

/// Pilote les vues de pages web, une par onglet.
///
/// Tous les appels se font sur le thread principal uniquement.
pub trait PageEngine {
    /// Crée la vue d'un onglet.
    ///
    /// # Errors
    ///
    /// [`PageEngineError::ViewAlreadyExists`] si la vue existe déjà,
    /// [`PageEngineError::Engine`] si le moteur échoue.
    fn create_view(&mut self, tab: TabId) -> Result<(), PageEngineError>;

    /// Charge une adresse dans la vue d'un onglet.
    ///
    /// # Errors
    ///
    /// [`PageEngineError::UnknownView`] si la vue n'existe pas,
    /// [`PageEngineError::Engine`] si le moteur échoue.
    fn load(&mut self, tab: TabId, url: &WebUrl) -> Result<(), PageEngineError>;

    /// Navigue d'un pas dans l'historique de la vue.
    ///
    /// # Errors
    ///
    /// [`PageEngineError::UnknownView`] si la vue n'existe pas,
    /// [`PageEngineError::Engine`] si le moteur échoue.
    fn history(&mut self, tab: TabId, step: HistoryStep) -> Result<(), PageEngineError>;

    /// Recharge la page courante de la vue.
    ///
    /// # Errors
    ///
    /// [`PageEngineError::UnknownView`] si la vue n'existe pas,
    /// [`PageEngineError::Engine`] si le moteur échoue.
    fn reload(&mut self, tab: TabId) -> Result<(), PageEngineError>;

    /// Détruit la vue d'un onglet.
    ///
    /// # Errors
    ///
    /// [`PageEngineError::UnknownView`] si la vue n'existe pas,
    /// [`PageEngineError::Engine`] si le moteur échoue.
    fn close_view(&mut self, tab: TabId) -> Result<(), PageEngineError>;
}

/// Pas dans l'historique. Le rechargement n'en est pas un : voir [`PageEngine::reload`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HistoryStep {
    /// Page précédente.
    Back,
    /// Page suivante.
    Forward,
}

/// Événement émis par le moteur à propos d'une vue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageEvent {
    /// Onglet concerné.
    pub tab: TabId,
    /// Ce qui s'est passé.
    pub kind: PageEventKind,
}

/// Nature d'un [`PageEvent`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PageEventKind {
    /// Un chargement commence.
    LoadStarted,
    /// Un chargement se termine.
    LoadFinished,
    /// Le titre de la page a changé.
    TitleChanged(PageTitle),
    /// L'adresse de la page a changé.
    UrlChanged(WebUrl),
    /// Le processus de rendu a été perdu.
    RendererLost,
    /// La page demande une nouvelle fenêtre (adresse éventuelle).
    NewWindowRequested(Option<WebUrl>),
    /// La vue s'est fermée d'elle-même (`window.close()`).
    ViewClosed,
}

/// Échecs du moteur de pages.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PageEngineError {
    /// Aucune vue ne porte cet identifiant.
    #[error("vue {0:?} inconnue")]
    UnknownView(TabId),
    /// Une vue existe déjà pour cet identifiant.
    #[error("vue {0:?} déjà créée")]
    ViewAlreadyExists(TabId),
    /// Échec rapporté par le moteur.
    #[error("échec du moteur : {reason}")]
    Engine {
        /// Explication du moteur, sans donnée de page sensible.
        reason: String,
    },
}

#[cfg(test)]
mod tests {
    use vigie_domain::TabStrip;

    use super::*;
    use crate::ports::fake_page_engine::{EngineCall, FakePageEngine};

    fn url() -> WebUrl {
        WebUrl::parse("https://example.org").unwrap()
    }

    fn tab() -> TabId {
        TabStrip::new().open(url()).unwrap()
    }

    #[test]
    fn second_create_view_fails() {
        let t = tab();
        let mut fake = FakePageEngine::default();
        let engine: &mut dyn PageEngine = &mut fake;
        engine.create_view(t).unwrap();
        assert_eq!(
            engine.create_view(t),
            Err(PageEngineError::ViewAlreadyExists(t))
        );
    }

    #[test]
    fn calls_on_missing_view_fail() {
        let t = tab();
        let u = url();
        let mut fake = FakePageEngine::default();
        let unknown = Err(PageEngineError::UnknownView(t));
        assert_eq!(fake.load(t, &u), unknown);
        assert_eq!(fake.history(t, HistoryStep::Back), unknown);
        assert_eq!(fake.reload(t), unknown);
        assert_eq!(fake.close_view(t), unknown);
    }

    #[test]
    fn journal_keeps_call_order() {
        let t = tab();
        let u = url();
        let mut fake = FakePageEngine::default();
        fake.create_view(t).unwrap();
        fake.load(t, &u).unwrap();
        fake.history(t, HistoryStep::Back).unwrap();
        fake.reload(t).unwrap();
        fake.close_view(t).unwrap();
        assert_eq!(
            fake.calls,
            vec![
                EngineCall::CreateView(t),
                EngineCall::Load(t, u),
                EngineCall::History(t, HistoryStep::Back),
                EngineCall::Reload(t),
                EngineCall::CloseView(t),
            ]
        );
    }

    #[test]
    fn load_after_close_fails() {
        let t = tab();
        let u = url();
        let mut fake = FakePageEngine::default();
        fake.create_view(t).unwrap();
        fake.close_view(t).unwrap();
        assert_eq!(fake.load(t, &u), Err(PageEngineError::UnknownView(t)));
    }

    #[test]
    fn forced_error_applies_once() {
        let t = tab();
        let mut fake = FakePageEngine::default();
        fake.fail_next("boom");
        assert!(matches!(
            fake.create_view(t),
            Err(PageEngineError::Engine { .. })
        ));
        assert_eq!(fake.create_view(t), Ok(()));
    }
}
