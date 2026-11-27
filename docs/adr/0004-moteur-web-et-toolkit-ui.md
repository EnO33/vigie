# ADR-0004 — Moteur web et toolkit d'interface

- Statut : proposé (accepté au merge par le board)
- Date : 2026-11-27

## Contexte

Vigie est un navigateur : il faut un moteur web embarquable et une façon de dessiner l'interface
(onglets, barre d'adresse, panneau IA) à côté des pages. Ordre de VISION.md : confidentialité >
web hostile > robustesse > performance > remplaçabilité.

Règle de décision de l'epic #11 (arbitrage du PO) : **toute option qui ne prouve pas 0 requête
non initiée (captures #17/#18) est éliminée**, quelles que soient ses performances.

Sources : trois annexes mesurées dans `docs/knowledge/spike-moteur/` (`wry-webkitgtk.md` #17,
`cef.md` #18, `ui.md` #19) et les lectures de source de #14/#15 dans `docs/knowledge/LOG.md`.
Les chiffres ci-dessous sont recopiés de ces annexes ; chaque annexe donne sa commande.

## Options comparées

| Option | Moteur | Statut |
|---|---|---|
| **wry 0.57.3 + tao 0.37.3** | WebKitGTK (Linux), WebView2 (Windows), WKWebView (macOS) | **retenue** |
| CEF 156 (crate `cef` 156.7.0) | Chromium 156.0.8078.100 embarqué | **éliminée** (règle de confidentialité) |

Toolkit d'interface, sur wry (#15, #19) : **(A)** chrome en webview (vue wry dédiée) ou **(B)**
UI native eframe 0.37.0 (egui). iced : éligible mais sans release du crate `iced` depuis 354 jours ;
Slint : éliminé pour sa licence (`LOG.md`, recommandation de #15).

## Mesures

Conteneur de la factory, identique pour les trois spikes : Debian 13 (trixie), `Linux 6.6.87.2-microsoft-standard-WSL2
x86_64`, Intel Core i9-9900K (relevé dans `wry-webkitgtk.md` seulement ; `cef.md` et `ui.md` indiquent « 16 CPU »), 16 CPU, 16 332 988 ko, `rustc 1.100.0`, Xvfb 1280×800×24 sans gestionnaire de fenêtres, X11 seul.
Outil : `tools/spike-moteur/measure.sh` (#16). Mesures faites le 2026-11-27.

| | wry 0.57.3 / WebKitGTK 2.54.3 | CEF 156.0.31 |
|---|---|---|
| SHA du prototype | `b09111ba1126add30fc92e79842ecae8c57d9414` (branche `spike/moteur-wry`) | `5c7fd0ce81d75dbc3bf6eb81f54ceb4085896c4f` (`spike/moteur-cef`) ; démarrage/mémoire/captures A mesurés avec le binaire de `1325dd1`, identique |
| Démarrage, 1 onglet (médiane) | 297 ms (variante **locale non commitée** de `b09111b`, sans pompe GTK ; 310 ms pour `b09111b` lui-même) — `measure.sh startup --runs 10 -- ./target/release/spike-wry --tabs 1` | 161-269 ms selon la session (séries 174/175/175 ms) — `measure.sh startup --runs 10 --timeout 60 -- spike/cef/run.sh --tabs 1` |
| RSS, 1 onglet | 652 Mo (2 vues) — `measure.sh memory --settle 5 -- … --tabs 1` | 779 MiB — idem avec `run.sh --tabs 1` (« Mo » et « MiB » : même unité, même `measure.sh`) |
| RSS, 10 onglets | 2599 Mo (11 vues : panneau + 10) | 1752 MiB |
| Réseau, page locale, 60 s (`strace -f`) | **`network_calls=0`**, deux captures (avec et sans réglages #14) | **26-27 appels**, 8 destinations ; 17-18 appels, 6 destinations avec neuf switches (baisse observée, attribution non établie) |
| `cargo deny` (`bans licenses sources`) | ok (cargo-deny 0.22.0) | heurte `deny.toml` (établi par l'architecte le 2026-11-26, non relancé ; voir plus bas) |

Lectures prudentes : la variance de démarrage CEF entre sessions (161-269 ms) est du même ordre que
l'écart avec wry ; la RSS additionne les pages partagées (pas de PSS) ; la RSS compare 2 vues wry (panneau + onglet)
à 1 vue CEF plus un panneau natif ; CEF a été mesuré **sans bac à sable** (`--no-sandbox`,
« No usable sandbox » dans le conteneur) : ses chiffres ne valent que pour ce mode. Aucune de ces mesures n'utilise
une vraie page web (pages locales triviales). Aucune conclusion de l'ADR ne dépend de ces écarts de mémoire. Le coût mémoire par vue
est discuté dans « Capacités » et « Limites connues ».

### Requêtes observées, par option

**wry / WebKitGTK : aucune.** 0 connexion `AF_INET`/`AF_INET6` sur les deux captures (`wry-webkitgtk.md`
critère 1). Il n'y a donc rien à supprimer : la seconde capture (avec `with_incognito(true)`,
`set_enable_dns_prefetching(false)`, `set_enable_hyperlink_auditing(false)`) donne aussi 0, mais ces
réglages n'ont **aucun effet mesurable** sur une page locale (`with_incognito` est une option du builder ;
les deux réglages `webview()` sont appliqués après le premier chargement, `wry-webkitgtk.md` l. 24). `strace -f` voit bien tout l'arbre (`WebKitNetworkProcess`, `WebKitWebProcess`, 12 `connect` tous `AF_UNIX`).
Limites : pas de `tcpdump`, un `send()` sur socket déjà connectée n'est pas tracé, page locale seulement.

**CEF : 8 destinations sans switches** (capture A1, 26 appels) :
`127.0.0.11:53` (DNS du conteneur), `142.251.156.119:443`, `142.251.209.110:443`, `142.251.39.174:80`,
`192.178.204.139:443`, `213.44.21.206:443`, `34.104.35.123:80`, `[2001:4860:4860::8888]:443`.
A2 : 27 appels, mêmes destinations (`192.178.204.113` au lieu de `.139`). **Avec** les neuf switches
`disable-background-networking`, `disable-component-update`, `disable-sync`, `no-pings`, `disable-domain-reliability`,
`disable-breakpad`, `metrics-recording-only`, `disable-default-apps`, `no-first-run` (B1 : 17 appels, B2 : 18) : 6 destinations,
`192.178.204.x:443` et `213.44.21.206:443` disparaissent ; `127.0.0.11:53`, `142.251.156.119:443`, `142.251.209.110:443`,
`142.251.39.174:80`, `34.104.35.123:80` et `[2001:4860:4860::8888]:443` restent. Cette baisse est **observée** ;
son attribution aux switches n'est **pas établie** (`cef.md`). **Le trafic n'est pas supprimé.**
Lacunes consignées telles quelles dans `cef.md`, non reconstituées : noms de domaine non relevés,
SHA et commande exacts de B1/B2 non consignés, application des switches non vérifiée, processus
à l'origine des connexions non prouvé.

## Décision

### 1. Moteur : wry + tao (WebKitGTK / WebView2 / WKWebView). CEF est éliminé.

CEF 156 n'établit pas « zéro requête non initiée » : il émet 26-27 appels réseau au démarrage sur une
page `data:`, et la baisse observée avec les neuf switches essayés (17-18 appels) laisse du trafic, et son attribution aux switches n'est pas établie (`cef.md`, « Pour l'ADR (#20) »).
Selon la règle de l'epic, il est **éliminé** sans autre critère. Aucune story « à prouver plus tard »
n'est ouverte pour le sauver. Facteurs secondaires, non décisifs : il heurte `deny.toml`
(voir « Conséquences ») et pèse 333 Mo d'archive (1,5 Go extraits) téléchargée par `build.rs` sans vérification d'intégrité hors réseau.

wry 0.57.3 est la **dernière version éligible** (≥ 7 jours) au 2026-11-27 : vérifié à l'API crates.io ce jour
(`curl https://crates.io/api/v1/crates/wry`) : 0.57.3 publiée le 2026-11-18 ; 0.57.4 et 0.58.0 (2026-11-25) et
0.58.2 (2026-11-26 ; 0.58.1 retirée) sont trop récentes. tao 0.37.3 (2026-11-18) ; 0.38.0 (2026-11-24) trop récente.
`cargo info wry` annonce 0.58.2. wry 0.57.4 et 0.58.0 deviennent éligibles le 2026-12-02, 0.58.2 le 2026-12-03, tao 0.38.0 le 2026-12-01 : les mesures de ce document valent
pour 0.57.3 seulement ; elles ne sont pas transférées à ces versions sans les rejouer.

### 2. Interface : (A) chrome en webview.

Une vue wry de 300 px, avec `with_ipc_handler`, héberge l'interface ; chaque onglet est une vue wry **sans** handler IPC.

- Isolation prouvée (`ui.md` critère 2) : `typeof window.ipc` vaut `undefined` dans la page, `postMessage` lève
  `TypeError`, aucun message de la page n'atteint l'hôte (contrôle positif : celui du panneau l'atteint).
  Cause lue en source (`wry-0.57.3/src/webkitgtk/mod.rs` l. 314-316, 351-352, 757). Prouvé sous WebKitGTK. WebView2 (lecture de #14, `LOG.md` Q5, non mesuré) : `window.ipc` n'est posé que dans `attach_ipc_handler` (`wry-0.57.3/src/webview2/mod.rs` l. 514-517, 993) ; wry ne pose jamais `IsWebMessageEnabled` (`grep -rn IsWebMessageEnabled src/` → 0) et l'exposition de `window.chrome.webview` sans handler **n'est pas vérifiée**. WKWebView : non lu.
- Même base technique que le moteur : tao pompe déjà GTK (`tao-0.37.3/src/platform_impl/linux/event_loop.rs`
  l. 226 et 1184) ; aucune bibliothèque X11 supplémentaire. Démarrage 291 ms (285-298) contre 444 ms (433-448) pour (B). Chiffres de l'UI : prototype `cd850ea09b37bfdda4f9a8fc615997ac1c41a027` (branche `spike/ui`), eframe 0.37.0, commandes de `ui.md` (`measure.sh startup --runs 10` et `memory --settle 5`, `--tabs 1`).
- (B) eframe économise ≈ 220 Mo (une vue en moins : 451 contre 674 Mo à 1 onglet, `ui.md`) mais démarre ≈ 150 ms plus tard (part du `DELAY` non isolée),
  exige `libxkbcommon-x11.so.0` et `libxcb-xkb.so.1` absentes de l'image, plante en `GLXBadWindow` si les vues sont créées
  pendant le premier `ui()` (cause non établie), impose winit à la place de tao et une pompe GTK manuelle. Sa seule vertu mesurée,
  la mémoire, passe après la robustesse et la confidentialité dans l'ordre de VISION.md. (B) reste faisable ; la décision se rouvre si
  la mémoire devient bloquante (voir « Limites connues » : le coût par vue wry en incognito est probablement le coût réel).

## Capacités pour le futur port `PageEngine`

Lignes de `wry-0.57.3/src/lib.rs` (`LOG.md`, Q6) :

- **Navigation** : `load_url` ; décision par `with_navigation_handler(Fn(String) -> bool)` l. 1309 (WebKitGTK : décisions `NavigationAction`
  seulement ; WebView2 : `NavigationStarting` seulement, `FrameNavigationStarting` non branché ; couverture des iframes **non vérifiée**).
- **Événements titre/URL** : `with_document_title_changed_handler` l. 1426, `with_on_page_load_handler(PageLoadEvent, String)` l. 1448.
- **Plusieurs vues par fenêtre** : `build_as_child` l. 1573, `with_bounds`/`set_bounds`. Mesuré : panneau + 2 vues dans une même fenêtre tao (`wry-webkitgtk.md` critère 4).
  Ordre d'empilement, focus clavier et redimensionnement **non testés**.
- **Isolation des scripts de page** : aucun pont `window.ipc` sans `with_ipc_handler` (prouvé WebKitGTK). Canaux restants à fermer dans l'adaptateur :
  `window.chrome.webview` sous WebView2 (exposition par le runtime sans handler non vérifiée, wry ne pose pas `IsWebMessageEnabled`), le titre du document (handler Rust, vu dans `ui.md`), tout `with_custom_protocol` (joignable par `fetch`), et la navigation de la vue d'interface
  (`with_navigation_handler` limité au schéma custom, `WebContext` propre non partagé avec les pages). Monde d'exécution des scripts d'initialisation : **non vérifié**.
- **Modèle de processus et crash du rendu** : WebKitGTK, un `WebKitWebProcess` et un `WebKitNetworkProcess` par `WebContext` (2 de chaque pour 2 vues
  sans contexte partagé). `kill -9` sur les `WebKitWebProcess` : **l'hôte survit** (`Sl`), reçoit `SIGCHLD`, les processus ne sont **pas relancés**, la dernière image
  reste à l'écran. wry ne connecte pas `web-process-terminated` (accès par `WebViewExtUnix::webview()` ; signal côté API **non testé**) : l'adaptateur devra le brancher
  et recharger la vue. `with_related_view` partage un processus de rendu entre vues : un crash peut toucher plusieurs vues. WebView2 : `ProcessFailed` non géré par wry (`WebViewExtWindows::webview()`), **non mesuré**.
- **Mémoire** : ≈ +216 Mo par vue (un `WebContext` par vue). Partager un `WebContext` n'a **pas** été remesuré, et sous wry 0.57.3 un contexte **éphémère** ne peut pas être partagé
  par l'API publique : voir « Limites connues ». Ce chiffre est donc probablement le coût réel en incognito, pas une simple borne haute.

## Limites connues

- **`build_as_child` : X11 seulement sous Linux** ; Wayland passe par `build_gtk` + `gtk::Fixed` (non testé). Panique si `gtk::init` n'a pas été appelé sur ce thread
  (`gdk::Display::default()`) ou si le display GDK par défaut n'est pas X11 (`.downcast_ref::<X11Display>().unwrap()`, `webkitgtk/mod.rs` l. 157-158). Autres `unwrap`/`expect` dans wry :
  `webview.uri().unwrap()` (l. 491, 494), `expect("WebView does not have UserContentManager")` (l. 735), `NewWindowResponse::Allow` (5 `unwrap`, fenêtre vide si échec) → **ne jamais répondre `Allow`**, seulement `Create` ou `Deny`.
  Avec `panic = "abort"` en release (`Cargo.toml`) et `catch_unwind` interdit (`clippy.toml`), une panique tue Vigie : l'adaptateur doit tester le display X11 et `gtk::init` avant `build_as_child`.
- **Mémoire et incognito** : avec `with_incognito(true)`, le `WebContext` fourni est ignoré (`webkitgtk/mod.rs` l. 259-263) ; `WebContext::new_ephemeral` est `pub(crate)`
  (`wry-0.57.3/src/web_context.rs` l. 54) ; `with_related_view` perd l'incognito (`LOG.md` Q1). Partager un contexte revient à persister (`WebContext::new(Some(dir))` écrit les cookies en clair,
  `LOG.md` Q1) : contraire à la confidentialité, rang 1 de VISION.md. Le coût de ≈ +216 Mo par vue est donc probablement le coût réel, et pèse sur l'arbitrage (A)/(B).
- Une vue web de 150 px de large reste noire (3 essais, cause non cherchée) ; 300 px s'affiche. Les vues de page démarrent à x = 313 au lieu de 300 (cause non cherchée).
- `Gdk-CRITICAL _gdk_frame_clock_freeze` une fois au démarrage (sans effet visible).
- **Non mesuré** (annexes) : Windows/WebView2, macOS/WKWebView, Wayland, PSS, HiDPI, accessibilité, vraie page web, trafic réseau d'une page réelle, profil persistant.
  Pour Windows/WebView2, faute de mesure, on s'en tient aux lectures de #14 (`LOG.md`, Q2) : `with_additional_browser_args` remplace tout le défaut de wry
  (`--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection`, à recopier), le proxy y est ignoré sans erreur, `with_incognito` demande le runtime ≥ 101.0.1210.39 ;
  flags de mise à jour, de crash et de télémétrie : **non vérifiés**. macOS/WKWebView : aucune source lue.
- Les réglages réseau de #14 (`WebViewExtUnix::webview()` : DNS prefetch, hyperlink auditing) s'appliquent **après** `build_as_child`, donc après le premier chargement.
  Prefetch de ressources, OCSP/CRL, rapports : aucun réglage trouvé ; le trafic d'une vraie page reste à mesurer (voir aussi « Non mesuré » ci-dessus).
- Le prototype wry utilise 6 `unwrap` et 1 `as` : tout est à réécrire pour le vrai code.

## Conséquences

- **`deny.toml`** : wry 0.57.3 + tao 0.37.3 passent `bans`, `licenses`, `sources` (`wry-webkitgtk.md` critère 6) ; `advisories` non lancé. Les avertissements `duplicate` sont des `warn`.
  Rien à changer, aucune issue `area:factory` n'est ouverte pour l'option retenue. CEF (éliminé) aurait demandé : `anyhow` en build-dependency de `cef-dll-sys`,
  licences `bzip2-1.0.6` et `CDLA-Permissive-2.0`. eframe (non retenu) exigeait `default-features = false` (polices OFL-1.1 / Ubuntu-font-1.0 refusées).
- **`unsafe`** : 0 bloc `unsafe` écrit dans le prototype wry (`grep -c unsafe src/main.rs` → 0) ; l'`unsafe` de wry (28 occurrences du mot dans `src/webkitgtk/`, FFI Xlib/GDK) reste dans la dépendance.
  Sur cette base, `unsafe_code = "forbid"` n'a **pas** à être levé pour `vigie-adapter-*` : aucune issue n'est ouverte. Non vérifié pour les adaptateurs Windows/macOS (non écrits) ; s'ils exigent `unsafe`, le board décidera dans une issue dédiée.
- **Confinement** : l'adaptateur moteur vit dans un crate `vigie-adapter-*` (nom exigé par `cargo xtask arch`, `xtask/src/rules.rs`) ; `wry`, `tao`, `gtk` n'apparaissent ni dans `vigie-domain` ni dans `vigie-app` (listes blanches `thiserror`, `url` / `thiserror`), qui ne connaissent que le port `PageEngine`.
  Les `unwrap`/paniques de wry sont désamorcés par des vérifications préalables dans l'adaptateur, qui renvoie des erreurs typées (ADR-0002).
- **Remplaçabilité** : le port `PageEngine` reste la couture ; WebView2 et WKWebView sont attendus mais non mesurés : ils demandent leur propre mesure avant d'être déclarés supportés.
- **Prochaines stories** (à créer par l'architecte, hors de cet ADR) : définition du port `PageEngine`, adaptateur wry/Linux, mesure du trafic réseau d'une vraie page, mesure Windows/macOS, remesure de la mémoire (un `WebContext` partagé n'est possible qu'en persistant : à mesurer sous cette réserve, ou avec un fork/une version exposant un contexte éphémère) avec wry 0.57.4 / 0.58.0 / 0.58.2 et tao 0.38.0 dès leur éligibilité (2026-12-01 à 2026-12-03).
- Le spike ne laisse aucun code de prototype dans `crates/` ; restent cet ADR, les annexes `docs/knowledge/spike-moteur/` et `tools/spike-moteur/`.
