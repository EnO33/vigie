//! Onglets et barre d'onglets.

use crate::{PageTitle, WebUrl};

/// Identifiant opaque d'un onglet, unique au sein d'une [`TabStrip`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct TabId(u64);

/// Un onglet ouvert.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tab {
    id: TabId,
    url: Option<WebUrl>,
    title: Option<PageTitle>,
}

impl Tab {
    /// Identifiant de l'onglet.
    #[must_use]
    pub const fn id(&self) -> TabId {
        self.id
    }

    /// Adresse affichée par l'onglet, `None` tant qu'il est vide.
    #[must_use]
    pub const fn url(&self) -> Option<&WebUrl> {
        self.url.as_ref()
    }

    /// Titre de la page, `None` tant que le moteur n'en a pas signalé.
    #[must_use]
    pub const fn title(&self) -> Option<&PageTitle> {
        self.title.as_ref()
    }
}

/// Opérations impossibles sur une [`TabStrip`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum TabStripError {
    /// Aucun onglet ne porte cet identifiant.
    #[error("onglet {0:?} introuvable")]
    NotFound(TabId),
    /// Tous les identifiants possibles ont été attribués.
    #[error("plus aucun identifiant d'onglet disponible")]
    IdSpaceExhausted,
}

/// Barre d'onglets ordonnée, avec au plus un onglet actif.
///
/// Invariant : si `active` est `Some(id)`, un onglet `id` existe.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TabStrip {
    tabs: Vec<Tab>,
    active: Option<TabId>,
    next_id: u64,
}

impl TabStrip {
    /// Barre vide.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Ouvre un onglet en dernière position et l'active.
    ///
    /// # Errors
    ///
    /// [`TabStripError::IdSpaceExhausted`] si plus aucun identifiant n'est disponible.
    pub fn open(&mut self, url: WebUrl) -> Result<TabId, TabStripError> {
        self.push(Some(url))
    }

    /// Ouvre un onglet vide (sans URL) en dernière position et l'active.
    ///
    /// # Errors
    ///
    /// [`TabStripError::IdSpaceExhausted`] si plus aucun identifiant n'est disponible.
    pub fn open_blank(&mut self) -> Result<TabId, TabStripError> {
        self.push(None)
    }

    /// Enregistre la nouvelle URL d'un onglet et efface son titre.
    ///
    /// # Errors
    ///
    /// [`TabStripError::NotFound`] si l'onglet n'existe pas.
    pub fn set_url(&mut self, id: TabId, url: WebUrl) -> Result<(), TabStripError> {
        let tab = self.tab_mut(id)?;
        tab.url = Some(url);
        tab.title = None;
        Ok(())
    }

    /// Enregistre le titre d'un onglet.
    ///
    /// # Errors
    ///
    /// [`TabStripError::NotFound`] si l'onglet n'existe pas.
    pub fn set_title(&mut self, id: TabId, title: PageTitle) -> Result<(), TabStripError> {
        self.tab_mut(id)?.title = Some(title);
        Ok(())
    }

    /// Ferme un onglet. S'il était actif, son voisin de droite devient actif,
    /// à défaut celui de gauche.
    ///
    /// # Errors
    ///
    /// [`TabStripError::NotFound`] si l'onglet n'existe pas.
    pub fn close(&mut self, id: TabId) -> Result<Tab, TabStripError> {
        let position = self.position(id)?;
        let closed = self.tabs.remove(position);
        if self.active == Some(id) {
            self.active = self
                .tabs
                .get(position)
                .or_else(|| position.checked_sub(1).and_then(|left| self.tabs.get(left)))
                .map(Tab::id);
        }
        Ok(closed)
    }

    /// Active un onglet existant.
    ///
    /// # Errors
    ///
    /// [`TabStripError::NotFound`] si l'onglet n'existe pas.
    pub fn activate(&mut self, id: TabId) -> Result<(), TabStripError> {
        self.position(id)?;
        self.active = Some(id);
        Ok(())
    }

    /// Onglet actif, s'il y en a un.
    #[must_use]
    pub fn active(&self) -> Option<&Tab> {
        self.active
            .and_then(|id| self.tabs.iter().find(|tab| tab.id == id))
    }

    /// Onglets dans l'ordre d'affichage.
    #[must_use]
    pub fn tabs(&self) -> &[Tab] {
        &self.tabs
    }

    fn push(&mut self, url: Option<WebUrl>) -> Result<TabId, TabStripError> {
        let id = TabId(self.next_id);
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or(TabStripError::IdSpaceExhausted)?;
        self.tabs.push(Tab {
            id,
            url,
            title: None,
        });
        self.active = Some(id);
        Ok(id)
    }

    fn tab_mut(&mut self, id: TabId) -> Result<&mut Tab, TabStripError> {
        self.tabs
            .iter_mut()
            .find(|tab| tab.id == id)
            .ok_or(TabStripError::NotFound(id))
    }

    fn position(&self, id: TabId) -> Result<usize, TabStripError> {
        self.tabs
            .iter()
            .position(|tab| tab.id == id)
            .ok_or(TabStripError::NotFound(id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(path: &str) -> WebUrl {
        WebUrl::parse(&format!("https://example.com/{path}")).unwrap()
    }

    fn strip_with(paths: &[&str]) -> (TabStrip, Vec<TabId>) {
        let mut strip = TabStrip::new();
        let ids = paths.iter().map(|p| strip.open(url(p)).unwrap()).collect();
        (strip, ids)
    }

    fn active_id(strip: &TabStrip) -> Option<TabId> {
        strip.active().map(Tab::id)
    }

    #[test]
    fn new_strip_is_empty() {
        let strip = TabStrip::new();
        assert_eq!(strip.tabs(), []);
        assert_eq!(active_id(&strip), None);
    }

    #[test]
    fn open_appends_and_activates_with_unique_ids() {
        let (strip, ids) = strip_with(&["a", "b"]);
        assert_ne!(ids[0], ids[1]);
        assert_eq!(strip.tabs().len(), 2);
        assert_eq!(strip.tabs()[1].url(), Some(&url("b")));
        assert_eq!(active_id(&strip), Some(ids[1]));
    }

    #[test]
    fn closing_active_tab_activates_right_neighbour() {
        let (mut strip, ids) = strip_with(&["a", "b", "c"]);
        strip.activate(ids[1]).unwrap();
        let closed = strip.close(ids[1]).unwrap();
        assert_eq!(closed.id(), ids[1]);
        assert_eq!(active_id(&strip), Some(ids[2]));
    }

    #[test]
    fn closing_last_active_tab_activates_left_neighbour() {
        let (mut strip, ids) = strip_with(&["a", "b"]);
        strip.close(ids[1]).unwrap();
        assert_eq!(active_id(&strip), Some(ids[0]));
    }

    #[test]
    fn closing_inactive_tab_keeps_active() {
        let (mut strip, ids) = strip_with(&["a", "b"]);
        strip.close(ids[0]).unwrap();
        assert_eq!(active_id(&strip), Some(ids[1]));
        assert_eq!(strip.tabs().len(), 1);
    }

    #[test]
    fn closing_only_tab_leaves_no_active() {
        let (mut strip, ids) = strip_with(&["a"]);
        strip.close(ids[0]).unwrap();
        assert_eq!(active_id(&strip), None);
    }

    #[test]
    fn unknown_tab_is_reported() {
        let (mut strip, ids) = strip_with(&["a"]);
        strip.close(ids[0]).unwrap();
        assert_eq!(strip.close(ids[0]), Err(TabStripError::NotFound(ids[0])));
        assert_eq!(strip.activate(ids[0]), Err(TabStripError::NotFound(ids[0])));
    }

    #[test]
    fn activate_switches_active_tab() {
        let (mut strip, ids) = strip_with(&["a", "b"]);
        strip.activate(ids[0]).unwrap();
        assert_eq!(active_id(&strip), Some(ids[0]));
    }

    #[test]
    fn exhausted_id_space_is_an_error_not_a_panic() {
        let mut strip = TabStrip {
            next_id: u64::MAX,
            ..TabStrip::default()
        };
        assert_eq!(strip.open(url("a")), Err(TabStripError::IdSpaceExhausted));
        assert_eq!(strip.open_blank(), Err(TabStripError::IdSpaceExhausted));
        assert_eq!(strip.tabs(), []);
    }

    fn title(raw: &str) -> PageTitle {
        PageTitle::parse(raw).unwrap()
    }

    #[test]
    fn open_blank_is_active_last_and_empty() {
        let (mut strip, _) = strip_with(&["a"]);
        let id = strip.open_blank().unwrap();
        let tab = strip.tabs().last().unwrap();
        assert_eq!(tab.id(), id);
        assert_eq!(tab.url(), None);
        assert_eq!(tab.title(), None);
        assert_eq!(active_id(&strip), Some(id));
    }

    #[test]
    fn set_url_fills_blank_tab() {
        let mut strip = TabStrip::new();
        let id = strip.open_blank().unwrap();
        strip.set_url(id, url("a")).unwrap();
        assert_eq!(strip.tabs()[0].url(), Some(&url("a")));
    }

    #[test]
    fn set_url_clears_title() {
        let (mut strip, ids) = strip_with(&["a"]);
        strip.set_title(ids[0], title("T")).unwrap();
        strip.set_url(ids[0], url("b")).unwrap();
        assert_eq!(strip.tabs()[0].title(), None);
    }

    #[test]
    fn set_title_keeps_url() {
        let (mut strip, ids) = strip_with(&["a"]);
        strip.set_title(ids[0], title("T")).unwrap();
        assert_eq!(strip.tabs()[0].title(), Some(&title("T")));
        assert_eq!(strip.tabs()[0].url(), Some(&url("a")));
    }

    #[test]
    fn set_on_closed_tab_is_not_found() {
        let (mut strip, ids) = strip_with(&["a"]);
        strip.close(ids[0]).unwrap();
        assert_eq!(
            strip.set_url(ids[0], url("b")),
            Err(TabStripError::NotFound(ids[0]))
        );
        assert_eq!(
            strip.set_title(ids[0], title("T")),
            Err(TabStripError::NotFound(ids[0]))
        );
    }
}
