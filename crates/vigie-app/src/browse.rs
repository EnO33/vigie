//! Cas d'usage de navigation : ouvrir une page, naviguer, recharger et intégrer
//! les événements du moteur dans l'état des onglets (ADR-0005).

use std::collections::HashSet;

use vigie_domain::{TabId, TabStrip, TabStripError, WebUrl};

use crate::ports::{HistoryStep, PageEngine, PageEngineError, PageEvent, PageEventKind};

/// Titre de fenêtre quand aucun onglet n'a ni titre ni adresse.
const APP_TITLE: &str = "Vigie";

/// Échecs d'une action de navigation.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum BrowseError {
    /// Opération impossible sur la barre d'onglets.
    #[error(transparent)]
    Tabs(#[from] TabStripError),
    /// Le moteur de pages a échoué.
    #[error(transparent)]
    Engine(#[from] PageEngineError),
}

/// État de navigation : onglets et vues dont le rendu est perdu.
#[derive(Debug, Default)]
pub struct Browser {
    tabs: TabStrip,
    renderer_lost: HashSet<TabId>,
}

impl Browser {
    /// Navigateur sans onglet.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Ouvre un onglet et y charge `url`. L'URL de l'onglet arrive par `UrlChanged`
    /// (adresse finale après redirections).
    ///
    /// # Errors
    ///
    /// [`BrowseError`] ; l'onglet est alors retiré et sa vue fermée.
    pub fn open_page(
        &mut self,
        engine: &mut dyn PageEngine,
        url: &WebUrl,
    ) -> Result<TabId, BrowseError> {
        let previous = self.active_id();
        let tab = self.open_blank(engine)?;
        if let Err(error) = engine.load(tab, url) {
            // Le rollback est au mieux : l'erreur renvoyée reste celle du `load`.
            engine.close_view(tab).ok();
            self.rollback(tab, previous);
            return Err(error.into());
        }
        Ok(tab)
    }

    /// Ouvre un onglet vide, sans chargement.
    ///
    /// # Errors
    ///
    /// [`BrowseError`] ; l'onglet est alors retiré de la barre.
    pub fn open_blank(&mut self, engine: &mut dyn PageEngine) -> Result<TabId, BrowseError> {
        let previous = self.active_id();
        let tab = self.tabs.open_blank()?;
        if let Err(error) = engine.create_view(tab) {
            self.rollback(tab, previous);
            return Err(error.into());
        }
        Ok(tab)
    }

    /// Navigue d'un pas dans l'historique de l'onglet.
    ///
    /// # Errors
    ///
    /// [`BrowseError::Tabs`] si l'onglet n'existe pas, [`BrowseError::Engine`] si le moteur échoue.
    pub fn navigate(
        &mut self,
        engine: &mut dyn PageEngine,
        tab: TabId,
        step: HistoryStep,
    ) -> Result<(), BrowseError> {
        self.require(tab)?;
        Ok(engine.history(tab, step)?)
    }

    /// Recharge l'onglet ; efface l'état « rendu perdu » en cas de succès.
    ///
    /// # Errors
    ///
    /// [`BrowseError::Tabs`] si l'onglet n'existe pas, [`BrowseError::Engine`] si le moteur échoue.
    pub fn reload(&mut self, engine: &mut dyn PageEngine, tab: TabId) -> Result<(), BrowseError> {
        self.require(tab)?;
        engine.reload(tab)?;
        self.renderer_lost.remove(&tab);
        Ok(())
    }

    /// Intègre un événement du moteur. Un onglet inconnu (vue déjà fermée) est ignoré.
    pub fn on_page_event(&mut self, event: PageEvent) {
        let PageEvent { tab, kind } = event;
        if self.require(tab).is_err() {
            return;
        }
        match kind {
            PageEventKind::UrlChanged(url) => {
                self.tabs.set_url(tab, url).ok();
            }
            PageEventKind::TitleChanged(title) => {
                self.tabs.set_title(tab, title).ok();
            }
            PageEventKind::RendererLost => {
                self.renderer_lost.insert(tab);
            }
            PageEventKind::ViewClosed => {
                self.tabs.close(tab).ok();
                self.renderer_lost.remove(&tab);
            }
            PageEventKind::LoadStarted
            | PageEventKind::LoadFinished
            | PageEventKind::NewWindowRequested(_) => {}
        }
    }

    /// Le rendu de l'onglet a-t-il été perdu (jusqu'au prochain rechargement) ?
    #[must_use]
    pub fn renderer_lost(&self, tab: TabId) -> bool {
        self.renderer_lost.contains(&tab)
    }

    /// Titre de l'onglet actif, à défaut son adresse, à défaut « Vigie ».
    #[must_use]
    pub fn window_title(&self) -> String {
        self.tabs
            .active()
            .and_then(|tab| {
                tab.title()
                    .map(vigie_domain::PageTitle::as_str)
                    .or_else(|| tab.url().map(WebUrl::as_str))
            })
            .unwrap_or(APP_TITLE)
            .to_owned()
    }

    /// Barre d'onglets, en lecture seule.
    #[must_use]
    pub const fn tabs(&self) -> &TabStrip {
        &self.tabs
    }

    fn active_id(&self) -> Option<TabId> {
        self.tabs.active().map(vigie_domain::Tab::id)
    }

    /// Retire l'onglet ouvert et rend l'activité à l'onglet qui l'était avant.
    fn rollback(&mut self, tab: TabId, previous: Option<TabId>) {
        self.tabs.close(tab).ok();
        if let Some(previous) = previous {
            self.tabs.activate(previous).ok();
        }
    }

    fn require(&self, tab: TabId) -> Result<(), TabStripError> {
        if self.tabs.tabs().iter().any(|t| t.id() == tab) {
            Ok(())
        } else {
            Err(TabStripError::NotFound(tab))
        }
    }
}

#[cfg(test)]
mod tests {
    use vigie_domain::PageTitle;

    use super::*;
    use crate::ports::fake_page_engine::{EngineCall, FakePageEngine};

    fn url(s: &str) -> WebUrl {
        WebUrl::parse(s).unwrap()
    }

    fn title(s: &str) -> PageTitle {
        PageTitle::parse(s).unwrap()
    }

    fn event(tab: TabId, kind: PageEventKind) -> PageEvent {
        PageEvent { tab, kind }
    }

    fn engine_error(reason: &str) -> BrowseError {
        BrowseError::Engine(PageEngineError::Engine {
            reason: reason.to_owned(),
        })
    }

    fn blank() -> (Browser, FakePageEngine, TabId) {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        let tab = browser.open_blank(&mut fake).unwrap();
        (browser, fake, tab)
    }

    /// `TabId` absent du navigateur : le 3e onglet d'une autre barre (ids 0 et 1 pris ailleurs).
    fn foreign_tab() -> TabId {
        let mut other = TabStrip::new();
        other.open_blank().unwrap();
        other.open_blank().unwrap();
        other.open_blank().unwrap()
    }

    #[test]
    fn open_page_creates_view_then_loads() {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        let u = url("https://example.org");
        let t = browser.open_page(&mut fake, &u).unwrap();
        assert_eq!(
            fake.calls,
            vec![EngineCall::CreateView(t), EngineCall::Load(t, u)]
        );
        assert_eq!(browser.tabs().active().map(vigie_domain::Tab::id), Some(t));
        assert_eq!(browser.tabs().active().and_then(|x| x.url()), None);
    }

    #[test]
    fn open_blank_creates_view_only() {
        let (browser, fake, t) = blank();
        assert_eq!(fake.calls, vec![EngineCall::CreateView(t)]);
        assert_eq!(browser.tabs().active().map(vigie_domain::Tab::id), Some(t));
    }

    #[test]
    fn create_view_failure_leaves_no_tab() {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        fake.fail_next("boom");
        assert_eq!(
            browser.open_page(&mut fake, &url("https://example.org")),
            Err(engine_error("boom"))
        );
        assert_eq!(browser.tabs().tabs(), []);
        fake.fail_next("bang");
        assert_eq!(browser.open_blank(&mut fake), Err(engine_error("bang")));
        assert_eq!(browser.tabs().tabs(), []);
    }

    #[test]
    fn load_failure_closes_view_and_tab() {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        fake.fail_call(1, "boom");
        let result = browser.open_page(&mut fake, &url("https://example.org"));
        assert_eq!(result, Err(engine_error("boom")));
        let Some(&EngineCall::CreateView(t)) = fake.calls.first() else {
            panic!("create_view attendu en premier");
        };
        assert_eq!(fake.calls.last(), Some(&EngineCall::CloseView(t)));
        assert!(fake.views.is_empty());
        assert_eq!(browser.tabs().tabs(), []);
    }

    #[test]
    fn failed_open_keeps_previous_active_tab() {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        let a = browser.open_blank(&mut fake).unwrap();
        browser.open_blank(&mut fake).unwrap();
        browser.open_blank(&mut fake).unwrap();
        browser.tabs.activate(a).unwrap();
        fake.fail_next("view");
        assert!(browser.open_blank(&mut fake).is_err());
        assert_eq!(browser.active_id(), Some(a));
        fake.fail_call(1, "load");
        assert!(
            browser
                .open_page(&mut fake, &url("https://example.org"))
                .is_err()
        );
        assert_eq!(browser.active_id(), Some(a));
        assert_eq!(browser.tabs().tabs().len(), 3);
    }

    #[test]
    fn load_then_close_failure_returns_load_error() {
        let mut browser = Browser::new();
        let mut fake = FakePageEngine::default();
        fake.fail_call(1, "load");
        fake.fail_call(2, "close");
        let result = browser.open_page(&mut fake, &url("https://example.org"));
        assert_eq!(result, Err(engine_error("load")));
        assert_eq!(browser.tabs().tabs(), []);
    }

    #[test]
    fn window_title_follows_events() {
        let (mut browser, _fake, t) = blank();
        assert_eq!(browser.window_title(), "Vigie");
        browser.on_page_event(event(t, PageEventKind::UrlChanged(url("https://a.test/"))));
        assert_eq!(browser.window_title(), "https://a.test/");
        browser.on_page_event(event(t, PageEventKind::TitleChanged(title("T"))));
        assert_eq!(browser.window_title(), "T");
        browser.on_page_event(event(t, PageEventKind::UrlChanged(url("https://b.test/"))));
        assert_eq!(browser.window_title(), "https://b.test/");
    }

    #[test]
    fn empty_strip_title_is_app_name() {
        assert_eq!(Browser::new().window_title(), "Vigie");
    }

    #[test]
    fn events_on_unknown_tab_are_ignored() {
        let (mut browser, _fake, t) = blank();
        let ghost = foreign_tab();
        for kind in [
            PageEventKind::UrlChanged(url("https://a.test/")),
            PageEventKind::TitleChanged(title("T")),
            PageEventKind::RendererLost,
            PageEventKind::ViewClosed,
        ] {
            browser.on_page_event(event(ghost, kind));
        }
        assert_eq!(browser.tabs().tabs().len(), 1);
        assert_eq!(browser.window_title(), "Vigie");
        assert!(!browser.renderer_lost(ghost));
        assert!(!browser.renderer_lost(t));
    }

    #[test]
    fn reload_clears_renderer_lost() {
        let (mut browser, mut fake, t) = blank();
        browser.on_page_event(event(t, PageEventKind::RendererLost));
        assert!(browser.renderer_lost(t));
        assert_eq!(fake.calls.len(), 1, "pas de rechargement automatique");
        browser.reload(&mut fake, t).unwrap();
        assert!(!browser.renderer_lost(t));
        assert_eq!(fake.calls.last(), Some(&EngineCall::Reload(t)));
    }

    #[test]
    fn failed_reload_keeps_renderer_lost() {
        let (mut browser, mut fake, t) = blank();
        browser.on_page_event(event(t, PageEventKind::RendererLost));
        fake.fail_next("boom");
        assert_eq!(browser.reload(&mut fake, t), Err(engine_error("boom")));
        assert!(browser.renderer_lost(t));
    }

    #[test]
    fn navigate_goes_through_history() {
        let (mut browser, mut fake, t) = blank();
        browser.navigate(&mut fake, t, HistoryStep::Back).unwrap();
        assert_eq!(
            fake.calls.last(),
            Some(&EngineCall::History(t, HistoryStep::Back))
        );
        fake.fail_next("boom");
        assert_eq!(
            browser.navigate(&mut fake, t, HistoryStep::Forward),
            Err(engine_error("boom"))
        );
    }

    #[test]
    fn unknown_tab_is_rejected_without_engine_call() {
        let (mut browser, mut fake, _t) = blank();
        let ghost = foreign_tab();
        let expected = Err(BrowseError::Tabs(TabStripError::NotFound(ghost)));
        assert_eq!(
            browser.navigate(&mut fake, ghost, HistoryStep::Back),
            expected
        );
        assert_eq!(browser.reload(&mut fake, ghost), expected);
        assert_eq!(fake.calls.len(), 1);
    }

    #[test]
    fn view_closed_removes_tab_without_engine_call() {
        let (mut browser, mut fake, first) = blank();
        let second = browser.open_blank(&mut fake).unwrap();
        browser.on_page_event(event(first, PageEventKind::RendererLost));
        browser.on_page_event(event(first, PageEventKind::ViewClosed));
        let ids: Vec<_> = browser
            .tabs()
            .tabs()
            .iter()
            .map(vigie_domain::Tab::id)
            .collect();
        assert_eq!(ids, vec![second]);
        assert!(!browser.renderer_lost(first));
        assert!(
            !fake
                .calls
                .iter()
                .any(|c| matches!(c, EngineCall::CloseView(_)))
        );
    }

    #[test]
    fn passive_events_change_nothing() {
        let (mut browser, fake, t) = blank();
        for kind in [
            PageEventKind::NewWindowRequested(Some(url("https://a.test/"))),
            PageEventKind::LoadStarted,
            PageEventKind::LoadFinished,
        ] {
            browser.on_page_event(event(t, kind));
        }
        assert_eq!(fake.calls.len(), 1);
        assert_eq!(browser.tabs().tabs().len(), 1);
        assert_eq!(browser.window_title(), "Vigie");
        assert!(!browser.renderer_lost(t));
    }
}
