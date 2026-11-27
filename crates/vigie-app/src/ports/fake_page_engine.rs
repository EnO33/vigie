//! Fake en mémoire de [`PageEngine`], partagé par les tests de la couche application.

use std::collections::{BTreeMap, HashSet};

use vigie_domain::{TabId, WebUrl};

use super::{HistoryStep, PageEngine, PageEngineError};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum EngineCall {
    CreateView(TabId),
    Load(TabId, WebUrl),
    History(TabId, HistoryStep),
    Reload(TabId),
    CloseView(TabId),
}

/// Fake en mémoire : mêmes règles d'erreur qu'un vrai moteur.
#[derive(Default)]
pub(crate) struct FakePageEngine {
    pub(crate) views: HashSet<TabId>,
    pub(crate) calls: Vec<EngineCall>,
    forced: BTreeMap<usize, PageEngineError>,
}

impl FakePageEngine {
    /// Fait échouer le prochain appel.
    pub(crate) fn fail_next(&mut self, reason: &str) {
        self.fail_call(0, reason);
    }

    /// Fait échouer le `n`-ième appel à venir (`0` = le prochain). Les appels se cumulent.
    pub(crate) fn fail_call(&mut self, n: usize, reason: &str) {
        self.forced.insert(
            self.calls.len().saturating_add(n),
            PageEngineError::Engine {
                reason: reason.to_owned(),
            },
        );
    }

    fn record(&mut self, call: EngineCall) -> Result<(), PageEngineError> {
        let forced = self.forced.remove(&self.calls.len());
        self.calls.push(call);
        forced.map_or(Ok(()), Err)
    }

    fn require(&self, tab: TabId) -> Result<(), PageEngineError> {
        if self.views.contains(&tab) {
            Ok(())
        } else {
            Err(PageEngineError::UnknownView(tab))
        }
    }
}

impl PageEngine for FakePageEngine {
    fn create_view(&mut self, tab: TabId) -> Result<(), PageEngineError> {
        if self.views.contains(&tab) {
            return Err(PageEngineError::ViewAlreadyExists(tab));
        }
        self.record(EngineCall::CreateView(tab))?;
        self.views.insert(tab);
        Ok(())
    }

    fn load(&mut self, tab: TabId, url: &WebUrl) -> Result<(), PageEngineError> {
        self.require(tab)?;
        self.record(EngineCall::Load(tab, url.clone()))
    }

    fn history(&mut self, tab: TabId, step: HistoryStep) -> Result<(), PageEngineError> {
        self.require(tab)?;
        self.record(EngineCall::History(tab, step))
    }

    fn reload(&mut self, tab: TabId) -> Result<(), PageEngineError> {
        self.require(tab)?;
        self.record(EngineCall::Reload(tab))
    }

    fn close_view(&mut self, tab: TabId) -> Result<(), PageEngineError> {
        self.require(tab)?;
        self.record(EngineCall::CloseView(tab))?;
        self.views.remove(&tab);
        Ok(())
    }
}
