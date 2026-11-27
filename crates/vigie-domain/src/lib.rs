//! Domaine de Vigie : types métier purs.
//!
//! Aucune I/O, aucun async, aucune horloge : tout se teste en mémoire, en millisecondes.
//! Voir `docs/adr/0001-architecture-hexagonale.md`.

pub mod page_title;
pub mod tab;
pub mod web_url;

pub use page_title::{PageTitle, PageTitleError};
pub use tab::{Tab, TabId, TabStrip, TabStripError};
pub use web_url::{WebUrl, WebUrlError};
