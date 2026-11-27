//! Couche application de Vigie.
//!
//! - [`ports`] : traits que les adaptateurs implémentent (trousseau, LLM, moteur web…).
//! - [`ai`] : types de configuration de l'IA en BYOK (ADR-0003).
//! - [`browse`] : cas d'usage de navigation (onglets et moteur de pages).
//! - [`configure_provider`] : premier cas d'usage, exemple de référence pour la factory.

pub mod ai;
pub mod browse;
pub mod configure_provider;
pub mod ports;
