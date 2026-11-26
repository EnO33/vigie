# Roadmap

> Tenue par l'agent `product-owner`. Chaque ligne devient un epic GitHub (`type:epic`).
> L'ordre est la priorité. Dérivée de `VISION.md`.

## M1 — Coquille

1. **Spike moteur et toolkit UI** : comparer WebView2/wry, CEF (crate `cef`) et le toolkit de
   l'interface (webview chrome vs UI native). Livrable : ADR-0004 avec prototype jetable mesuré
   (démarrage, mémoire, multi-webview, contrôle de la télémétrie du moteur).
2. **Port `PageEngine` + adaptateur retenu** : ouvrir une page, naviguer, événements titre/URL.
3. **Modèle d'onglets → UI** : barre d'onglets verticale branchée sur `vigie-domain::tab`.
4. **Barre d'URL** : saisie → `WebUrl` ou recherche (moteur de recherche configurable).
5. **Historique local** : adaptateur SQLite, aucune donnée hors machine.

## M2 — IA BYOK

6. **Trousseau** : adaptateur `SecretStore` sur le trousseau OS.
7. **Port `LlmProvider`** + adaptateurs Anthropic, OpenAI, Mistral, Ollama (streaming).
8. **Panneau IA** : conversation, choix du fournisseur, gestion des erreurs (clé invalide, quota).

## M3 — Contexte

9. **Extraction de contenu** de l'onglet actif (texte lisible) traitée comme donnée non fiable.
10. **Défense injection de prompt** : séparation stricte instructions / contenu, tests adverses.
11. **Multi-onglets** et citations des sources.

## M4 — Skills · M5 — Espaces

À détailler par le PO quand M3 sera terminé.
