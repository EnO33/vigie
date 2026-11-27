# ADR-0005 — Port `PageEngine` : forme, événements et stratégie de test

- Statut : proposé (accepté au merge par le board)
- Date : 2026-11-27
- Epic : #40. Prérequis : ADR-0001 (hexagone), ADR-0002 (erreurs typées), ADR-0004 (wry 0.57.3 + tao 0.37.3).

## Contexte

ADR-0004 a choisi wry/WebKitGTK mais laisse ouverts la forme du port, la remontée des événements
du moteur et la façon de tester un adaptateur qui exige un display X11. L'epic #40 liste ces
points « à vérifier par l'architecte ». Ordre de VISION.md : confidentialité > web hostile >
robustesse > performance > remplaçabilité.

## Faits vérifiés à la source (2026-11-27)

Sources lues dans `/usr/local/cargo/registry/src/index.crates.io-1949cf8c6b5b557f/`.

| # | Fait | Preuve |
|---|---|---|
| F1 | wry 0.57.3 (2026-11-18, MSRV 1.85, `Apache-2.0 OR MIT`) et tao 0.37.3 (2026-11-18, MSRV 1.85, `Apache-2.0`) sont les dernières versions éligibles ; 0.57.4/0.58.x et tao 0.38.0 datent de moins de 7 jours. | `GET https://crates.io/api/v1/crates/{wry,tao}/versions` |
| F2 | wry 0.57.3 épingle `webkit2gtk = "=2.0.2"` (feature `v2_38`), `gtk = "0.18"`, `gdkx11 = "0.18"`. Résolu : gtk 0.18.2, gdkx11 0.18.2, glib 0.18.5 (MIT). | `wry-0.57.3/Cargo.toml` l. 200-227 ; `Cargo.lock` d'un projet jetable |
| F3 | Le signal `web-process-terminated` est exposé : `WebViewExt::connect_web_process_terminated(Fn(&Self, WebProcessTerminationReason))`, feature `v2_20`, incluse dans `v2_38`. L'accès passe par `WebViewExtUnix::webview() -> webkit2gtk::WebView`. Comportement à l'exécution **non testé**. | `webkit2gtk-2.0.2/src/auto/web_view.rs` l. 2850-2853 ; `Cargo.toml` l. 76, 112 ; `wry-0.57.3/src/lib.rs` l. 2430 |
| F4 | Sans `with_url` ni `with_html`, `build_as_child` ne charge rien : le chargement initial n'a lieu que si l'un des deux est fourni. On peut donc poser les réglages `set_enable_dns_prefetching(false)` et `set_enable_hyperlink_auditing(false)` **avant** le premier `load_url`. Les deux sont **dépréciés** dans WebKitGTK 2.54.3 installé (DNS prefetch depuis 2.48, hyperlink auditing depuis 2.50, défaut `TRUE`) sans remplacement documenté : leur effet réel est **non vérifié**. | `wry-0.57.3/src/webkitgtk/mod.rs` l. 384-389 ; `webkit2gtk-2.0.2/src/auto/settings.rs` l. 1485, 1549 ; `/usr/share/gir-1.0/WebKit2-4.1.gir` l. 20588-20592, 20749-20753, 22282 |
| F5 | `with_incognito(true)` remplace tout contexte fourni par `WebContext::new_ephemeral()` de webkit2gtk. Ce qui est écrit sur disque en incognito reste **non mesuré**. | `wry-0.57.3/src/webkitgtk/mod.rs` l. 259-261 ; `web_context.rs` l. 54-58 |
| F6 | Les scripts d'initialisation passent par `UserScript::new(…)` sans monde d'exécution : ils tournent dans le monde de la page (pas de `new_for_world` utilisé). Ils sont donc lisibles et modifiables par la page. | `wry-0.57.3/src/webkitgtk/mod.rs` l. 828-841 |
| F7 | `NewWindowResponse` a trois variantes : `Allow`, `Create { webview }`, `Deny`. | `wry-0.57.3/src/lib.rs` l. 458-480 |
| F8 | Navigation disponible sur `WebView` : `load_url`, `reload`, `go_back`, `go_forward` (l. 2216-2232). | `wry-0.57.3/src/lib.rs` |
| F9 | `tao::EventLoop::new()` panique sans display (`expect("Failed to initialize gtk backend!")`) et exige le thread principal (`assert_is_main_thread`). `gtk::init()` appelle `gtk_init_check` et renvoie `Err` au lieu de terminer ; il panique s'il est appelé depuis un second thread. `build_as_child` renvoie `X11DisplayNotFound` sans display GDK, mais `unwrap` le downcast en `X11Display`. | `tao-0.37.3/src/platform_impl/linux/event_loop.rs` l. 212-226 ; `gtk-0.18.2/src/rt.rs` l. 110-140 ; `wry-0.57.3/src/webkitgtk/mod.rs` l. 157-158 |
| F10 | `cargo deny --offline check` (cargo-deny 0.22.0, base d'avis locale `c5279d0` du 2026-11-27, `deny.toml` du dépôt) sur wry 0.57.3 + tao 0.37.3 + webkit2gtk 2.0.2 + gtk 0.18.2 : `advisories ok, bans ok, licenses ok, sources ok`. La base contient pourtant RUSTSEC-2024-0415 (gtk, « unmaintained ») et RUSTSEC-2024-0429 (glib < 0.20, « unsound ») ; RUSTSEC-2024-0415 porte `withdrawn = "2026-08-14"` (`advisory-db-3157b0e258782691/crates/gtk/RUSTSEC-2024-0415.md`), ce qui explique son absence ; RUSTSEC-2024-0429 ne vise que `glib::VariantStrIter::*` (`[affected.functions]`). Pourquoi cargo-deny ne remonte pas 0429 : **non vérifié**. | commande lancée dans un projet jetable |
| F11 | Les gates lancent `cargo test --workspace` sans display, puis tout `tools/**/*_test.sh` (`git ls-files -- 'tools/*_test.sh'` trouve `tools/spike-moteur/measure_test.sh`) ; l'image contient `xvfb-run` et `strace`. La couverture de lignes exigée (80 %) porte sur tout le workspace hors `xtask`. | `factory/gates.sh` l. 19, 86-95, 107-113 ; `docker/agent.Dockerfile` l. 26-36 |

## Décision

### 1. Port synchrone, mono-thread, commandes seulement

Dans `vigie-app` (`ports::page_engine`), sans aucun type wry/tao/gtk :

```rust
pub trait PageEngine {
    fn create_view(&mut self, tab: TabId) -> Result<(), PageEngineError>;
    fn load(&mut self, tab: TabId, url: &WebUrl) -> Result<(), PageEngineError>;
    fn history(&mut self, tab: TabId, step: HistoryStep) -> Result<(), PageEngineError>;
    fn close_view(&mut self, tab: TabId) -> Result<(), PageEngineError>;
}
pub enum HistoryStep { Back, Forward, Reload }
```

Tout appel a lieu sur le thread principal (GTK l'exige, F9). Pas d'async, pas de canal dans `vigie-app`.
`create_view` est séparé de `load` : une vue vide doit exister pour poser les réglages avant le
premier chargement (F4) et pour mesurer le lancement sans URL.

### 2. Événements poussés vers un puits, relayés par la boucle du shell

L'adaptateur reçoit à sa construction un puits `Rc<dyn Fn(PageEvent)>` (un clone par rappel :
les rappels wry/GTK sont `Fn + 'static` sans `Send`, `wry-0.57.3/src/lib.rs` l. 1309-1450). Les rappels y
traduisent chaque signal en `PageEvent { tab: TabId, kind: PageEventKind }` :
`LoadStarted`, `LoadFinished`, `TitleChanged(PageTitle)`, `UrlChanged(WebUrl)`, `RendererLost`,
`NewWindowRequested(Option<WebUrl>)`. Le shell branche ce puits sur `EventLoopProxy::send_event`
de tao (`Result<(), EventLoopClosed>`, `tao-0.37.3/src/event_loop.rs` l. 382 : un échec signifie que la
boucle est fermée, l'événement est abandonné et journalisé, sans panique), et c'est la boucle d'événements qui appelle le cas d'usage. Ainsi aucun cas d'usage ne
s'exécute **dans** un rappel GTK, ce qui évite qu'une commande au moteur rentre dans un rappel du moteur.

Alternative écartée : un `mpsc` interrogé par le cas d'usage. Il demande un réveil de la boucle en
plus et ne simplifie rien. Autre alternative écartée : un port qui renvoie des événements
(`poll_events`). Il force l'adaptateur à stocker des événements et cache leur ordre.

### 3. Source des événements de chargement

`with_on_page_load_handler` est **interdit** : il fait `webview.uri().unwrap()` dans un rappel GTK
(`wry-0.57.3/src/webkitgtk/mod.rs` l. 491, 494), une panique à travers la FFI abandonne le processus.
`LoadStarted`, `LoadFinished` et `UrlChanged` viennent de `connect_load_changed` et `connect_uri_notify`
posés sur `WebViewExtUnix::webview()` (`webkit2gtk-2.0.2/src/auto/web_view.rs` l. 2287, 3229), qui ne
concernent que le cadre principal ; `TitleChanged` vient de `connect_title_notify` (l. 3206).
`with_navigation_handler` ne sert qu'à refuser des schémas : il voit aussi les sous-cadres
(`webkitgtk/mod.rs` l. 563-566), donc il n'écrit jamais l'URL d'un onglet. Comportement de `pushState`
sur `connect_uri_notify` : **non vérifié**.

### 4. Une URL de page qui n'est pas une `WebUrl` n'est pas un événement

`UrlChanged` ne porte qu'une `WebUrl` (`http`/`https`). Le gestionnaire de navigation de
l'adaptateur refuse tout autre schéma, sauf `about:blank`, qui ne produit aucun `UrlChanged`.
Le titre d'une page est une donnée hostile : il passe par le newtype `PageTitle` du domaine
(caractères de contrôle retirés, longueur bornée) avant d'entrer dans l'application.

### 5. Règles de construction d'une vue de page (adaptateur `vigie-adapter-wry`)

Une **seule** fonction de construction de vue dans l'adaptateur pose chaque réglage explicitement,
et un test unitaire vérifie la configuration produite :

- `with_incognito(true)` (décision 1 du PO dans #40, F5) ;
- `with_devtools(false)` **explicite** : le défaut de wry est `true` en build debug
  (`wry-0.57.3/src/lib.rs` l. 872-875), ce qui active `set_enable_developer_extras(true)`
  (`webkitgtk/mod.rs` l. 458) dans `cargo test`, sous Xvfb et en build dev ;
- `with_download_started_handler(|_, _| false)` : le défaut de wry accepte tout
  (`lib.rs` l. 868, `webkitgtk/mod.rs` l. 681-686). Le refus est silencieux dans cet epic ; un
  événement de téléchargement refusé reviendra avec l'epic dédié. Test dans #49 ;
- jamais `with_ipc_handler`, `with_custom_protocol`, `with_initialization_script*` (F6 : un script
  d'initialisation est lisible par la page), `with_on_page_load_handler` (décision 3) ;
- construction **sans URL**, puis DNS prefetch et hyperlink auditing désactivés via
  `WebViewExtUnix::webview()`, puis `load_url` (F4). Ces deux réglages sont dépréciés : l'effet sur
  2.54.3 est à mesurer (un `<a ping>` part-il ?) dans #51 ;
- `with_new_window_req_handler` renvoie toujours `NewWindowResponse::Deny` et émet
  `NewWindowRequested` (F7 ; `Allow` contient 5 `unwrap`, ADR-0004) ;
- `connect_web_process_terminated` émet `RendererLost` (F3) ; aucun rechargement automatique
  (pas de boucle de crash), le cas d'usage expose `HistoryStep::Reload`.

Dépendances de l'adaptateur, épinglées exactement pour éviter les doublons (wry n'épingle que `webkit2gtk =2.0.2` ; `gtk` et `gdkx11` sont en `"0.18"`, F2) :
`wry = "=0.57.3"`, `webkit2gtk = { version = "=2.0.2", features = ["v2_38"] }`, `gtk = "=0.18.2"`,
`gdkx11 = "=0.18.2"`. L'adaptateur est générique sur `wry::raw_window_handle::HasWindowHandle`
(réexporté, `wry-0.57.3/src/lib.rs` l. 373) : `tao = "=0.37.3"` n'est une dépendance que de `vigie-shell`.

### 6. Vérification de l'environnement avant tao et wry

L'adaptateur expose `X11Environment::check() -> Result<X11Environment, EnvironmentError>` :
`gdk::set_allowed_backends("x11")` (`gdk-0.18.2/src/auto/functions.rs` l. 355) **avant** `gtk::init()`,
sinon une session Wayland avec XWayland (WSLg) choisit Wayland et la vérification échoue ; le choix
du backend à l'exécution est **non vérifié**. Puis `gtk::init()` (renvoie `Err` sans display) et contrôle que `gdk::Display::default()` est un
`gdkx11::X11Display`. Le shell l'appelle **avant** `EventLoop::new()` (qui panique, F9) ; il
renvoie un `ExitCode` d'échec avec un message, sans panique. `X11Environment` est le seul jeton
qui permet de construire `WryPageEngine` : on ne peut pas oublier la vérification.

### 7. Tests : logique pure hors display, intégration GTK sous Xvfb

- Toute décision (schémas autorisés, traduction des rappels en `PageEvent`, réponse aux nouvelles
  fenêtres, nettoyage du titre) est une fonction pure de l'adaptateur, testée par `cargo test` sans
  display. La colle wry/GTK reste mince pour tenir les 80 % de couverture (F11).
- Les tests qui demandent GTK (backend x11 forcé avant tout scénario) vivent dans **une** cible `tests/x11.rs` avec `harness = false` : un
  seul `main`, scénarios en séquence sur le thread principal (F9 interdit `gtk::init` depuis les
  threads du harnais). Sans `DISPLAY`, la cible vérifie seulement le chemin « pas de display →
  `EnvironmentError` » ; si `VIGIE_REQUIRE_X11=1` et pas de display, elle échoue.
- `tools/engine/x11_test.sh` lance `VIGIE_REQUIRE_X11=1 xvfb-run -a cargo test --locked --all-features -p vigie-adapter-wry --test x11`.
  Son nom le fait passer dans l'étape « outils » des gates (F11) : aucun fichier protégé à modifier.
- La mesure réseau (60 s, `strace -f`) reste un script versionné lancé à la main
  (`tools/engine/`, via `tools/spike-moteur/measure.sh network`) : 60 s par passe et l'accès au web
  réel ne conviennent pas aux gates.

## Conséquences

- `vigie-app` dépend de `vigie-domain` (autorisé, ADR-0001) ; aucune liste blanche ne change.
- Le domaine gagne `PageTitle`, et un onglet peut être vide (`Tab::url() -> Option<&WebUrl>`).
- `cargo deny` passe aujourd'hui (F10) ; si une mise à jour de la base d'avis fait remonter
  RUSTSEC-2024-0429, la levée passe par le board (`deny.toml` protégé).
- Incognito par vue = un `WebContext::new_ephemeral()` par onglet (`webkitgtk/mod.rs` l. 259-261) :
  cookies non partagés entre onglets et coût mémoire par vue.
- Le port n'affiche, ne masque ni ne redimensionne une vue : suffisant pour cet epic, à compléter avec
  l'epic onglets.
- Non vérifié, à établir par les stories : effet réel de `web-process-terminated` après `kill -9`,
  écritures disque en incognito, couverture des iframes par le gestionnaire de navigation, trafic
  d'une vraie page, effet des réglages dépréciés (F4), `pushState` (décision 3), choix du backend GDK.
- Windows/macOS/Wayland restent hors périmètre (#40) : `vigie-adapter-wry` ne compile que sous
  Linux dans cet epic.
