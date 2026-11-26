# Journal de veille (tenu par `tech-watch`)

Faits vérifiés, datés, sourcés. Plus récent en haut.

## 2026-11-26 — spike moteur : toolkits d'interface (chrome webview ou UI native Rust)

Sources : `R` = `/usr/local/cargo/registry/src/index.crates.io-*/`. Versions et dates : `cargo info`
et API `crates.io/api/v1/crates/<crate>/versions` (date `created_at`, champ `yanked`). Seuil des 7 jours :
publiée au plus tard le 2026-11-19. Rien n'a été compilé ni exécuté : tout est lu.
Référence wry : **0.57.3** (2026-11-18, 8 jours), comme demandé. `cargo info wry` donne aujourd'hui
0.58.2 (publiée aujourd'hui, donc non éligible) ; 0.58.1 est yankée ; 0.57.4 date du 2026-11-25. Non évalué ici.
Licences admises (`deny.toml`, `[licenses] allow`) : MIT, Apache-2.0 (± LLVM-exception), BSD-2/3-Clause,
ISC, MPL-2.0, Unicode-3.0, Zlib. Le critère MSRV ne vaut que pour le crate de tête (`rust-version` de
son `Cargo.toml`) ; celui des dépendances transitives n'a pas été relevé.
Choix des trois candidats : egui/eframe, iced, Slint. Non examinés : gtk4 (MIT, 0.11.5, MSRV 1.92 d'après
`cargo info`), qui ajouterait GTK 4 à côté du GTK 3 imposé par wry sous Linux, Xilem, Dioxus-native, etc.

### Option (B) — UI native Rust : trois candidats

Contrainte wry (`R/wry-0.57.3/src/lib.rs` l. 1573) : `build_as_child<W: HasWindowHandle>(self, window: &'a W)`,
`raw-window-handle` **0.6** avec `std` (`Cargo.toml` l. 149-151). Sous Linux (doc l. 1558-1566) : X11
uniquement, pas Wayland ; `gtk::init` à appeler et `gtk::main_iteration_do` à faire tourner avec la boucle
d'événements ; pas de redimensionnement automatique, appeler `WebView::set_bounds` (l. 1541). Alternative Wayland+X11 citée par la doc : `build_gtk` avec `gtk::Fixed`.
Le `W` est implicitement `Sized` : un `&dyn HasWindowHandle` ne passe pas tel quel.

| | eframe 0.37.0 | iced 0.14.0 | Slint 1.19.1 |
|---|---|---|---|
| Publiée | 2026-10-15 (41 j) | 2025-12-07 (354 j) | 2026-11-24 (2 j) ; 1.19.0 : 2026-11-16 (10 j) |
| Licence | MIT OR Apache-2.0 : admise | MIT : admise | `GPL-3.0-only OR LicenseRef-Slint-Royalty-free-2.0 OR LicenseRef-Slint-Software-3.0` : **éliminé (licence)** |
| MSRV (crate de tête) | 1.95 | 1.88 | 1.95 |
| Dernière release | 2026-10-15 | 2025-12-07 | 2026-11-24 |
| `raw-window-handle` | 0.6.2, `eframe-0.37.0/Cargo.toml` l. 169-170 | 0.6, `iced_runtime-0.14.0/Cargo.toml` l. 57-58 | 0.6 derrière la feature `raw-window-handle-06`, absente de `default` (`slint-1.19.1/Cargo.toml.orig` l. 95-97) |
| `HasWindowHandle` | **implémenté directement** : `impl HasWindowHandle for Frame` (`eframe-0.37.0/src/epi.rs` l. 750) et pour `CreationContext` (l. 101) | pas sur un type de l'application : `window::run(id, f: impl FnOnce(&dyn Window) -> T + Send + 'static)` (`iced_runtime-0.14.0/src/window.rs` l. 463-466), `trait Window: HasWindowHandle + HasDisplayHandle` (l. 196) | `slint::WindowHandle: HasWindowHandle` (`i-slint-core-1.19.1/api.rs` l. 412-419) |
| X11 | feature `x11` l. 113-119 de `eframe-0.37.0/Cargo.toml`, dans `default` (`cargo info`) | `x11` et `wayland` dans `default` (`cargo info`) | non examiné (éliminé) |
| GTK initialisé | **non vérifié** (aucun code d'eframe ne touche GTK) | idem | non examiné |
| Exemple public avec vue web enfant | aucun : `emilk/egui/examples` (API GitHub) n'en contient pas : « non vérifié » | aucun dans `iced-rs/iced/examples` : « non vérifié » | aucun dans `slint-ui/slint/examples` : « non vérifié » |

Faits liés :
- Les exemples `wry-0.57.3/examples/winit.rs` (l. 22-24 `build_as_child(&window)`, l. 57-67 `gtk::main_iteration_do`,
  l. 84 `gtk::init()`) et `multiwebview.rs` (l. 29-62 : quatre `build_as_child` dans une fenêtre) montrent le schéma
  avec winit 0.30 (`wry` dev-dependency `winit = "0.30"`). `egui-winit-0.37.0` dépend de `winit` 0.30.13
  (`Cargo.toml` l. 133-134), iced_winit 0.14.1 de `winit` 0.30 avec `rwh_06` (`Cargo.toml` l. 91-93). Même
  famille de winit, mais **aucune combinaison toolkit + wry n'a été compilée** : non vérifié.
- iced : `window::run` exige `Send + 'static` et renvoie le résultat par `Task<T>` avec `T: Send`. Un
  `wry::WebView` enveloppe des objets GTK ; je n'ai pas prouvé par compilation qu'il est `!Send`
  (aucun `unsafe impl Send` pour `WebView` dans `lib.rs`, seul `RequestAsyncResponder` l. 446 en a un). Si c'est
  le cas, il faut le construire dans la closure et le ranger dans un `thread_local`, et passer par un newtype
  pour le `&dyn Window` (`Sized`). Non vérifié, mais c'est un frottement que eframe n'a pas.
- Wayland : `build_as_child` n'y fonctionne pas (doc l. 1558-1559). Les trois toolkits activent Wayland par défaut
  (eframe l. 93-98 ; iced `default`) : forcer X11 au lancement (ex. désactiver la feature `wayland`)
  n'a **pas** été vérifié.

### Option (A) — chrome en webview : isolation interface / page

API wry 0.57.3 (`src/lib.rs`) :
- `with_ipc_handler` (l. 1177) : réception des messages `window.ipc.postMessage(..)`. Sous Linux, le canal
  JS n'existe que si le handler est fourni : `src/webkitgtk/mod.rs` l. 314-316 (`ipc_enabled = ipc_handler.is_some()`,
  `attach_ipc_handler` seulement si `Some`), l. 731-769 (`register_script_message_handler("ipc")`).
  Donc : **seule la vue d'interface reçoit `with_ipc_handler`** ; les vues de page sont construites sans
  (`ipc_handler: None` par défaut, l. 865) et n'ont pas ce pont sous WebKitGTK. Vérifié pour WebKitGTK ;
  WebView2 et WKWebView : non lus.
- Événements des pages sans JS : callbacks Rust posés sur chaque vue de page, `with_navigation_handler`
  (l. 1309, `Fn(String) -> bool`, peut refuser), `with_on_page_load_handler` (l. 1448),
  `with_document_title_changed_handler` (l. 1426), `with_new_window_req_handler` (l. 1407),
  `with_download_started_handler` (l. 1362). Ils s'exécutent côté Rust, dans le processus hôte.
- Rust vers interface : `WebView::evaluate_script` (l. 2103) sur la **vue d'interface uniquement**.
  Pas de `with_initialization_script` (l. 1011) sur les vues de page : la page n'a aucun script injecté.
- Chargement de l'interface : `with_custom_protocol` (l. 1076) sert le HTML/CSS local ; pas d'URL distante.
- Schéma : page → (callbacks Rust) → état de l'application → `evaluate_script` → vue d'interface ;
  interface → `ipc_handler` → commandes typées Rust (valider chaque message : donnée non fiable) → actions
  sur les `WebView` de page (`load_url`, `set_bounds`). La page ne voit jamais `window.ipc`. Non vérifié :
  qu'un script de page ne puisse pas atteindre la vue d'interface (vues distinctes, pas d'iframe, donc pas
  de partage d'origine attendu ; non testé).
- Même limite Linux que (B) : `build_as_child` X11 seulement (doc l. 1558-1559), ou `build_gtk` + `gtk::Fixed`.
  CEF : non examiné dans ce spike.

### Recommandation

Prototyper **(B) avec eframe 0.37.0**. Raisons vérifiées : seul candidat à la fois éligible (licence admise,
MSRV 1.95 ≤ 1.100, release de 41 jours, la plus récente des deux éligibles) et dont `Frame` implémente
`HasWindowHandle` (`epi.rs` l. 750) : `build_as_child(&frame)` passe sans adaptateur. iced est éligible mais
sans release depuis 354 jours et sans type portant le handle (closure `Send`). Slint est éliminé (licence).
Le prototype doit trancher les points non vérifiés : X11 forcé sous une session Wayland, `gtk::init` +
`main_iteration_do` depuis la boucle eframe, `set_bounds` à chaque redimensionnement, entrée clavier entre
vue web enfant et egui. S'il échoue, repli : (A), dont l'isolation est décrite ci-dessus.

## 2026-11-26 — spike moteur : réglages réseau et modèle de processus (wry 0.57.3, cef 156.7.0)

Sources : `R` = `$CARGO_HOME/registry/src/index.crates.io-1949cf8c6b5b557f/` (ici
`/usr/local/cargo/registry/src/…`). Crates lus : `wry-0.57.3` (octets identiques au `.crate` téléchargé
sur static.crates.io, `diff -rq` : seul `.cargo-ok` diffère), `webkit2gtk-2.0.2` (version imposée par
`wry-0.57.3/Cargo.toml` l. 221, avec la feature `v2_38`, l. 222 ; `v2_40` seulement avec la feature wry
`linux-body`, l. 52-53, absente de `default`, l. 47-50), `cef-156.7.0+156.0.31`,
`cef-dll-sys-156.7.0+156.0.31`. Rien n'a été exécuté : tout est lu, rien n'est « mesuré ».
`tao 0.37.3` n'a pas été lu (aucune question ne l'exige).
Les doc comments de `webkit2gtk-2.0.2` sont vides : la sémantique vient de la doc officielle
WebKitGTK, page `stable` (version affichée **2.42.5**, `webkitgtk.org/reference/webkit2gtk/stable/`).
La version visée par wry est l'API `v2_38` : tout constat tiré de cette page est « doc 2.42.5, non
vérifié pour 2.38 » (CA2). Elle n'est pas forcément la version installée chez l'utilisateur : à
re-vérifier avec `pkg-config`.

### Q1 — WebKitGTK (Linux)
- Accès au `WebView` WebKitGTK : `WebViewExtUnix::webview()` → `webkit2gtk::WebView`
  (`R/wry-0.57.3/src/lib.rs` : trait `WebViewExtUnix` l. 2414, `fn webview` l. 2430, impl l. 2447). Tout réglage ci-dessous passe donc par là,
  après `build_gtk`/`build_as_child`. `WebViewBuilder` n'expose aucun de ces réglages.
  Mais le build charge déjà la page : `src/webkitgtk/mod.rs` l. 385-389 (`web_context.load_uri(…)` si
  `attributes.url`, sinon `load_html`). Des réglages posés après le build peuvent laisser la première page
  aux défauts WebKit (`load_uri` peut être asynchrone : non vérifié ; non mesuré). Piste : construire sans `with_url`/`with_html`, poser les réglages via
  `webview()`, puis `load_url`. Ordre effectif : **non mesuré.**
- Ce que wry fait déjà (`src/webkitgtk/mod.rs`) : contexte éphémère si `with_incognito(true)`
  (l. 259-260, `WebContext::new_ephemeral()`), proxy via `WebsiteDataManager` (l. 271-282),
  `Settings` : webgl, webaudio, page cache, user agent, devtools, JS, `set_enable_back_forward_navigation_gestures`
  (l. 443-444) et, si `attributes.clipboard`, `set_javascript_can_access_clipboard(true)` (l. 447-449)
  (l. 439-465 au total ; l'accès presse-papiers depuis JS touche Q5).
  Piège : avec `with_incognito(true)`, le `WebContext` fourni est **ignoré sans erreur** (`mod.rs` l. 259-263 ;
  doc `lib.rs` l. 1434 « WebContext will be ignored if incognito is enabled »).
  Piège : une vue `with_related_view` n'appelle pas `builder.web_context(…)` (l. 419-423). Le
  `with_incognito` et le `with_proxy_config` de cette vue sont posés sur un contexte qui n'est pas utilisé
  (l. 259-282 puis l. 419-420) : ils sont perdus sans erreur (`register_uri_scheme`, l. 381, va aussi sur ce contexte inutilisé ; effet
  côté WebKit **non vérifié**). Ce dont la vue liée hérite vient de WebKitGTK,
  doc non lue : **non vérifié.** Compte pour « rien sur disque » et pour `PageEngine`.
  « Rien sur disque » : `WebContext::new(Some(dir))` écrit les cookies **en clair** dans `dir/cookies`
  (`src/webkitgtk/web_context.rs` l. 42-45, `CookiePersistentStorage::Text`) ; voir aussi
  `set_persistent_credential_storage_enabled` (`webkit2gtk-2.0.2/src/auto/website_data_manager.rs` l. 606).
  Sans `with_web_context` ni `with_incognito`, wry prend `WebContext::default()` = `Self::new(None)`
  (`R/wry-0.57.3/src/web_context.rs` l. 97-98) : wry ne fournit aucun `WebsiteDataManager`
  (`src/webkitgtk/web_context.rs` l. 32-50). Persistance par défaut de WebKit : **non vérifié.** **Aucun** réglage de
  préchargement DNS, d'audit de liens, de TLS ni de rapports n'est posé : les défauts WebKit s'appliquent.
- Réglages réseau existants côté `webkit2gtk-2.0.2` :
  - `SettingsExt::set_enable_dns_prefetching` (`src/auto/settings.rs` l. 1485). Doc 2.42.5 (non vérifié pour 2.38) :
    « prefetch domain names… avant que l'utilisateur suive un lien ». Défaut : non vérifié.
  - `SettingsExt::set_enable_hyperlink_auditing` (l. 1549). Doc 2.42.5 (non vérifié pour 2.38) : « hyperlink auditing is enabled ».
    Défaut : non vérifié.
  - `WebContextExt::set_tls_errors_policy` (`src/auto/web_context.rs` l. 688) : **déprécié depuis 2.32**
    (doc 2.42.5, `class.WebContext.html`, non vérifié pour 2.38 ; la source webkit2gtk porte aussi
    `#[cfg_attr(feature = "v2_32", deprecated = "Since 2.32")]`, `webkit2gtk-2.0.2/src/auto/web_context.rs`
    l. 685, `fn set_tls_errors_policy` l. 688) ; `WebsiteDataManagerExt::set_tls_errors_policy`
    (`website_data_manager.rs` l. 618) à préférer. Valeurs : `Ignore`/`Fail` (`enums.rs` l. 3616) ; elles règlent seulement le traitement des
    certificats invalides ; qu'aucun trafic ne soit coupé est déduit des noms, sans doc (`enums.rs` l. 3616-3622) : **non vérifié.** Appeler la version `WebContextExt` fait échouer le
    build : le workspace a `deprecated = "deny"` (`Cargo.toml` l. 27).
  - `WebsiteDataManager` (`website_data_manager.rs`) : `is_ephemeral` l. 566 est un **getter** en lecture
    seule (`fn is_ephemeral(&self) -> bool`), pas un interrupteur. Côté `webkit2gtk` : `WebsiteDataManager::new_ephemeral()`
    (l. 43), builder `is_ephemeral(self, bool)` (l. 157), `set_itp_enabled` (l. 577), `set_network_proxy_settings`
    (l. 589). **Hors de portée de wry 0.57.3 sans fork** : aucune API wry n'accepte un `WebsiteDataManager` ni un
    `webkit2gtk::WebContext` ; `WebContext::new_ephemeral` est `pub(crate)` (`R/wry-0.57.3/src/web_context.rs` l. 54, champ `os`
    `pub(crate)` l. 29) et `WebContextImpl::new_ephemeral` (`src/webkitgtk/web_context.rs` l. 54) est dans
    `pub(crate) mod webkitgtk` (`lib.rs` l. 371) : inatteignable. Seul point d'entrée public :
    `with_incognito(true)` (`lib.rs` l. 1442), qui appelle `new_ephemeral` en interne (`src/webkitgtk/mod.rs`
    l. 259-260). `with_related_view` perd cet incognito (voir plus haut).
- Prefetch de ressources (`<link rel=prefetch>`) : aucun réglage trouvé. **Non vérifié.**
- Vérification de certificats en ligne (OCSP/CRL) et rapports/télémétrie : aucun réglage trouvé dans la
  source lue ; le comportement vient de libsoup/GnuTLS, hors des crates lus. **Non vérifié.**
- Le seul moyen sûr de dire « aucun trafic non initié » est la mesure (stories de mesure de l'epic #11).

### Q2 — WebView2 (Windows), « non mesuré »
- `WebViewBuilderExtWindows::with_additional_browser_args` existe : `R/wry-0.57.3/src/lib.rs` l. 1794
  (déclaration), l. 1880-1881 (impl), valeur stockée l. 1753. Il vit dans `lib.rs`, pas dans
  `src/webview2/` ; il est consommé en `src/webview2/mod.rs` l. 334-367
  (`options.set_additional_browser_arguments`, l. 367).
- Défaut de wry si on ne l'appelle pas (`src/webview2/mod.rs` l. 337) :
  `--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection`, plus `--autoplay-policy=…` et
  `--proxy-server=…` selon les attributs (l. 339-359). **Appeler la méthode remplace tout le défaut**
  (doc l. 1786-1793) : il faut le recopier. Les webviews d'arguments différents exigent des dossiers
  de données différents (même doc).
- SmartScreen : `msSmartScreenProtection` est déjà dans la liste `--disable-features` de wry
  (source ci-dessus). Sémantique du flag côté Microsoft (page « WebView2 features and flags »,
  URL et version du runtime non relevées) : **non vérifié.**
- Mises à jour, rapports de crash, télémétrie : aucun flag vérifié. **Non vérifié.**
- `with_incognito` : profil InPrivate via `SetIsInPrivateModeEnabled` (`src/webview2/mod.rs` l. 449).
  Version minimale du runtime WebView2 : 101.0.1210.39, sans effet en dessous (doc `lib.rs` l. 1439).

### Q3 — CEF 156.7.0
- Point d'entrée des switches : `ImplApp::on_before_command_line_processing(&self, process_type:
  Option<&CefString>, command_line: Option<&mut CommandLine>)` —
  `R/cef-156.7.0+156.0.31/src/bindings/x86_64_unknown_linux_gnu.rs` l. 33805. API `CommandLine` :
  `append_switch` (l. 28723), `append_switch_with_value` (l. 28725), `has_switch` (l. 28717).
  Doc C (`cef-dll-sys-156.7.0+156.0.31/src/bindings/x86_64_unknown_linux_gnu.rs` l. 30666) :
  `process_type` est `NULL` pour le processus navigateur ; les valeurs de `CefSettings` équivalentes à un
  switch sont posées avant l'appel ; `command_line_args_disabled` démarre avec une ligne vide.
  Modifier les processus enfants peut provoquer « undefined behavior including crashes ».
- Autre point : `ImplBrowserProcessHandler::on_before_child_process_launch` (`cef` bindings, l. 29342).
- `Settings` (`cef::Settings`, `cef-156.7.0+156.0.31/src/bindings/x86_64_unknown_linux_gnu.rs` l. 556-589 ;
  équivalent C `_cef_settings_t`, `cef-dll-sys-…/x86_64_unknown_linux_gnu.rs` l. 17791) : `no_sandbox`, `cache_path`, `root_cache_path`,
  `persist_session_cookies`, `command_line_args_disabled`, `accept_language_list`, `disable_signal_handlers`.
  Doc C de `cache_path` (`cef-dll-sys-…` doc l. 17810, champ l. 17811) : vide → « incognito mode », caches en mémoire,
  rien de spécifique au profil sur disque, **mais** « installation-specific data will still be persisted
  in root_cache_path ». Doc de `root_cache_path` (doc l. 17812, champ l. 17813) : si les deux sont vides, répertoire par
  défaut `~/.config/cef_user_data` sous Linux ; verrou singleton basé sur cette valeur depuis CEF 120.
  Donc « rien sur disque » n'est pas acquis : des données d'installation restent écrites. Reste de la doc C de
  `root_cache_path` : défaut « not recommended in production », plusieurs instances sur le même dossier : « data corruption »,
  verrou singleton ; personnaliser `root_cache_path` et implémenter `OnAlreadyRunningAppRelaunch` (cef-dll-sys doc l. 17812) : à reprendre pour le prototype CEF.
- Préférences et policies : `cef::Settings.chrome_policy_id` (`cef` l. 584 ; doc C `cef-dll-sys-…` doc l. 17845, champ l. 17846 :
  active les policies Chrome via la plateforme/l'utilisateur OS, par ex. `/etc/opt/chrome/policies` sous
  Linux, « Only supported with Chrome style »). Préférences à l'exécution : `ImplPreferenceManager`
  (`has_preference`, `can_set_preference`, `set_preference`, l. 10822-10830 des bindings `cef`). Noms de
  préférences ou de policies utiles (mises à jour, télémétrie, Safe Browsing) : **non vérifié**, aucune
  liste lue ; la doc C de `set_preference` n'a pas été lue non plus.
- Noms de switches Chromium (mises à jour de composants, Safe Browsing, rapports de crash, domain
  reliability, préchargement, variations) : **non vérifié.** Ils ne figurent pas dans les crates `cef`
  (recherche de `disable-component-update`, `disable-background-networking`, `no-pings`,
  `disable-domain-reliability`, `disable-field-trial`… : aucune occurrence), et les sources Chromium
  de la version 156 n'ont pas pu être lues (`raw.githubusercontent.com` : HTTP 429 ;
  `chromium.googlesource.com` : 404). À établir dans une story dédiée, avec la source Chromium 156.0.8078.100 (`cef-dll-sys` bindings l. 39 : `CEF_VERSION =
  "156.0.31+ge603d97+chromium-156.0.8078.100"` ; 156.0.31 est la version de CEF, pas de Chromium).

### Q4 — Modèle de processus
- CEF : le crash du rendu est signalé au processus navigateur par
  `ImplRequestHandler::on_render_process_terminated(browser, status: TerminationStatus, error_code,
  error_string)` (`cef` l. 27024 ; doc C `cef-dll-sys` l. 28920 : « Called on the browser process UI
  thread when the render process terminates unexpectedly »). Processus de rendu séparé par défaut : **non vérifié** ;
  le mode mono-processus existe (doc C de `_cef_request_context_t`, cef-dll-sys l. 24586 : « When running in
  single-process mode there is only a single render process (the main process) »). Que l'hôte survive à un
  crash reste **non mesuré**. Aussi `on_render_process_unresponsive` (`cef` l. 27014 ; doc C cef-dll-sys
  l. 28908 : 15 s sans événement d'entrée).
- WebKitGTK : `WebViewExt::connect_web_process_terminated` (`webkit2gtk-2.0.2/src/auto/web_view.rs`
  l. 2853) ; wry 0.57.3 ne le connecte pas (`grep web_process_terminated src/` : aucun résultat),
  il faut passer par `WebViewExtUnix::webview()`. Survie de l'hôte : **non mesuré**.
  `with_related_view` : « sharing the same web process » (`lib.rs` l. 2048, appliqué `webkitgtk/mod.rs`
  l. 419-420) : un crash de rendu peut toucher plusieurs vues liées (à retenir pour `PageEngine`).
- WebView2 : wry ne gère pas l'événement `ProcessFailed` (`grep ProcessFailed src/` : aucun résultat) ;
  accessible via `WebViewExtWindows::webview() -> ICoreWebView2` (`lib.rs` l. 2351). **Non mesuré.**

### Q5 — Isolation des scripts
- WebKitGTK : sans `with_ipc_handler`, wry n'enregistre ni le message handler `ipc` ni `window.ipc`
  (`src/webkitgtk/mod.rs` l. 314-316, 351-352, 757 ; `ipc_enabled` conditionne l. 351). WebView2 :
  idem, `window.ipc` n'est posé que dans `attach_ipc_handler` (`src/webview2/mod.rs` l. 516-517, 984-993).
  Pas de pont wry sans `with_ipc_handler` ; un custom protocol enregistré (`register_uri_scheme`,
  `src/webkitgtk/mod.rs` l. 381 ; WebView2 : `add_WebResourceRequested`, `src/webview2/mod.rs` l. 1076) reste un canal page→hôte via `fetch`. Que `window.chrome.webview` soit exposé par le runtime WebView2 même
  sans handler : **non vérifié.** `grep -rn IsWebMessageEnabled R/wry-0.57.3/src` : aucun résultat,
  wry ne coupe donc pas ce canal côté runtime.
- `with_initialization_script` (`lib.rs` l. 1011) : WebKitGTK crée `UserScript::new(…, &[], &[])` à
  `UserScriptInjectionTime::Start` (`src/webkitgtk/mod.rs` l. 829-841). Monde d'exécution de
  `UserScript::new` : **non vérifié** (`user_script.rs` l. 20-37 sans doc ; conclure de l'absence de
  `world_name` serait une hypothèse). `webkit2gtk-2.0.2` offre pourtant `UserScript::for_world(…, world_name, …)`
  (`src/auto/user_script.rs` l. 44, sous `v2_22`, active via `v2_38`) et `UserStyleSheet::for_world`
  (`user_style_sheet.rs` l. 44). Accès possible : `WebViewExtUnix::webview()` (wry `lib.rs` l. 2430, trait l. 2414) puis
  `user_content_manager()` (`webkit2gtk` `web_view.rs` l. 1227). Que `world_name` crée un vrai monde
  isolé : **non vérifié** (doc WebKitGTK non lue). WebView2 : `AddScriptToExecuteOnDocumentCreated` (`src/webview2/mod.rs` l. 1444) ;
  monde de la page selon la doc Microsoft : **non vérifié** (doc non lue). Sous Windows les scripts
  vont toujours dans les sous-frames (doc `lib.rs` l. 1004 et 1029).
- CEF : absence de pont par défaut **non vérifiée** (aucune source lue ne le prouve). Point d'injection
  possible côté rendu : `ImplRenderProcessHandler::on_context_created` (`cef` l. 32690 ; doc C l. 30458 :
  « immediately after the V8 context for a frame has been created ») ; `Frame::execute_java_script`
  (`cef` l. 7599) existe aussi. Aucun script d'initialisation de CEF lu. `src/wrapper/message_router.rs` fournit un routeur de
  messages ; il n'est actif que si on l'installe. Monde isolé : **non vérifié.**

### Q6 — Capacités pour `PageEngine` (wry)
Toutes les lignes sont dans `R/wry-0.57.3/src/lib.rs` :
- Titre : `with_document_title_changed_handler(impl Fn(String))` l. 1426.
- Chargement : `with_on_page_load_handler(impl Fn(PageLoadEvent, String))` l. 1448.
- Navigation autorisée : `with_navigation_handler(impl Fn(String) -> bool)` l. 1309. Portée exacte, WebKitGTK : la WebView construite, pas les popups ; décision seulement pour
  `PolicyDecisionType::NavigationAction` (`src/webkitgtk/mod.rs` l. 563-566, sinon `return false`) ; sans URI
  dans la requête, `false` sans décision (l. 589) : défaut WebKit. WebView2 : branché sur `add_NavigationStarting`
  seul (`src/webview2/mod.rs` l. 781) ; `grep FrameNavigationStarting src/webview2/mod.rs` : 0, wry ne branche pas
  `FrameNavigationStarting`. Que `NavigationStarting` couvre les iframes : **non vérifié** (doc Microsoft non lue) ;
  que les sous-frames passent par `NavigationAction` côté WebKitGTK : **non vérifié** (écart Linux/Windows sur les iframes inconnu).
- Nouvelle fenêtre : `with_new_window_req_handler` l. 1407. Réserve `NewWindowResponse::Allow`, Linux
  (`src/webkitgtk/mod.rs` l. 518-552) : wry crée lui-même une vue liée avec `WebViewAttributes { ..Default::default() }`
  (l. 537-546) : attributs wry par défaut : ni handler de navigation, ni script d'init. Contexte (incognito, proxy)
  hérité de la vue liée côté WebKit, `builder.web_context(…)` n'étant pas appelé (l. 419-423) : **non vérifié**
  (touche « rien sur disque » et Q5) ; 5 `unwrap` : `toplevel()` l. 520, `downcast::<gtk::ApplicationWindow>()` l. 521,
  `application()` l. 523, panique si la vue n'est pas dans une `gtk::ApplicationWindow` liée à une
  application ; (et `related_webviews.lock().unwrap()` l. 534 et 550) ; l'erreur de `new_gtk` est avalée par `.ok()` l. 553
  après `window.show_all()` l. 537 : une fenêtre vide reste à l'écran. Windows : `Allow` → `SetHandled(false)` (`src/webview2/mod.rs` l. 874), popup ouverte par le
  runtime hors wry ; effet exact **non vérifié** (doc Microsoft non lue). `PageEngine` : jamais `Allow`
  (`Create` ou `Deny`). Proxy : `with_proxy_config` l. 1460 ; sous Windows, avec `with_additional_browser_args`, il est **ignoré sans erreur** :
  `--proxy-server` n'est ajouté que dans le défaut `unwrap_or_else` (`src/webview2/mod.rs` l. 334-362).
- Vues multiples : `build_as_child` l. 1573 ; Linux **X11 uniquement**, Wayland via
  `WebViewBuilderExtUnix::build_gtk` (l. 2041, 2061) avec `gtk::Fixed` ; `gtk::init` requis, boucle GTK à
  avancer avec `gtk::main_iteration_do` ; **panique** si `gtk::init` n'a pas été appelé **dans le même
  thread** (doc de `build` l. 1541-1544, doc de `build_as_child` l. 1569-1572, doc de `build_gtk` l. 2040). La doc dit aussi « panique si le
  handle est invalide » (l. 1571), mais la source Linux est différente : `build_as_child` → `new_as_child`
  (l. 1576) → `new_x11` (`src/webkitgtk/mod.rs` : appel l. 132, `fn new_x11` l. 144 ; sans la feature `x11`, l. 139 :
  `Err(Error::UnsupportedWindowHandle)`) : un handle non Xlib renvoie
  `Err(Error::UnsupportedWindowHandle)` (l. 150-152), sans panique ; deux paniques
  sous Linux : l. 157 `gdk::Display::default()` appelle `assert_initialized_main_thread!()`
  (`R/gdk-0.18.2/src/auto/display.rs` l. 301 ; macro `gdk-0.18.2/src/rt.rs` l. 16-25 : « GDK may only be used
  from the main thread » ou « GDK has not been initialized ») ; l. 158
  `gdk_display.downcast_ref::<X11Display>().unwrap()` quand le display GDK par défaut n'est pas X11.
  Réserve : wry demande `gtk = "0.18"` (`wry-0.57.3/Cargo.toml` l. 204-205), gtk-0.18.2 demande
  `gdk = "0.18"` (l. 74-75) ; gdk-0.18.2 est la seule version du registre, aucun Cargo.lock du dépôt ne
  résout wry : version effective **non vérifiée.** Panique pour handle invalide hors Linux : **non vérifié.** En marche, sous Linux : `with_on_page_load_handler` → `webview.uri().unwrap()`
  (`src/webkitgtk/mod.rs` l. 491 et 494). Au build : IPC → `.expect("WebView does not have UserContentManager")` (l. 735,
  `attach_ipc_handler` appelé l. 316 depuis `new_gtk`, `UserContentManager` toujours posé l. 408). `set_bounds` (l. 2266) n'agit que pour un enfant ou `build_gtk` + `gtk::Fixed`.
- Conséquence : le futur `PageEngine` doit vérifier que le display GDK est X11 et que `gtk::init` a été
  appelé sur ce thread avant `build_as_child` ; valider le handle ne suffit pas (la panique ne se rattrape
  pas côté Rust strict : `catch_unwind` interdit, `clippy.toml` l. 18 ; `panic = "abort"` en release, `Cargo.toml` l. 85).
- CEF : titre `on_title_change` (`cef` l. 17770), URL `on_address_change` (l. 17762), chargement
  `on_load_start` (l. 21584) / `on_load_end` (l. 21592), navigation `on_before_browse` (l. 26940).
  Vues multiples côté CEF : **non vérifié.**

### Non vérifié (récapitulatif)
- Q1 : défauts des réglages WebKit ; OCSP/CRL et rapports ; `<link rel=prefetch>` ; sens de `Ignore`/`Fail` (TLS) ;
  `load_uri` asynchrone ; ordre réglages/premier chargement ; héritage du contexte (incognito, proxy) par une vue
  `with_related_view` ; persistance par défaut sans `WebsiteDataManager` ; constats tirés de la doc 2.42.5 (non vérifiés pour 2.38).
- Q2 : flags WebView2 de mise à jour/crash/télémétrie ; sémantique de `msSmartScreenProtection` ; URL et version des pages Microsoft.
- Q3 : tous les switches Chromium de CEF ; noms de préférences/policies CEF ; doc C de `set_preference`.
- Q4 : survie de l'hôte à un crash de rendu (3 moteurs) ; processus de rendu séparé par défaut côté CEF (le mode mono-processus existe).
- Q5 : `window.chrome.webview` sans handler ; monde de `UserScript::new` et sémantique de `world_name` (`for_world`) ;
  monde d'exécution des scripts WebView2 et CEF ; pont par défaut CEF.
- Q6 : panique pour handle invalide hors Linux ; portée du handler de navigation (couverture des iframes par
  `NavigationStarting` côté WebView2 et des sous-frames par `NavigationAction` côté WebKitGTK) ; défaut WebKit appliqué
  à une requête sans URI (l'absence de décision est lue, l. 589) ; effet de `Allow` sous Windows ; vues multiples CEF.
- `tao` non lu.

## 2026-11-26 — veille hebdomadaire

Toolchain
- `rustc 1.100.0 (2026-11-09)` / `cargo 1.100.0` = stable courante : `channel-rust-stable.toml`
  (`date = "2026-11-12"`, version `1.100.0`).
- `RELEASES.md` (branche master de rust-lang/rust) annonce `1.100.1 (2026-11-27)`, correctif de
  régression `Iterator` (const). Non publié à ce jour sur le canal stable : non vérifié côté
  installation, à surveiller la semaine prochaine.
- 1.100.0 : type `!` stabilisé, `extern "custom"`, allocateurs personnalisés (`Allocator`, `Vec::new_in`),
  `bool::toggle`, `str::trim_prefix`/`trim_suffix`, `Box::map`/`Rc::map`/`Arc::map`, `core::mem::DropGuard`.
  Aucun n'est requis par le code actuel. Pas de nouvelle édition.
- Clippy 1.100 (`CHANGELOG.md` de rust-clippy) : nouveaux lints `option_zip_none` (suspicious) et
  `needless_nonzero_get` (complexity), déjà couverts par `clippy::all` = deny. `unwrap_used` :
  `allow-unwrap-in-tests` vaut aussi pour les tests d'intégration. Rien à activer.

Dépendances directes (`cargo info` + API crates.io)
- thiserror 2.0.21 (2026-09-23), serde 1.0.229 (2026-07-18), cargo_metadata 0.23.1 (2025-11-12),
  url 2.5.9 (2026-11-20), toml 1.2.3 (2026-11-25) : tous à la dernière version, aucune yankée,
  aucun écart de version majeure, aucune dépréciation constatée.
- Point d'attention : url 2.5.9 (6 jours) et toml 1.2.3 (1 jour) sont plus récents que le délai
  de 7 jours. Dernières versions éligibles : url 2.5.8, toml 1.2.1 (2026-11-06) ; toml 1.2.2 date de 5 jours.
- cargo_metadata : dernière release 2025-11-12, soit ~12 mois. Seuil d'abandon à surveiller.

Plugins (`factory/plugins.lock`, API releases GitHub)
- ponytail v5.3.3, ECC v2.2.3, mattpocock/skills v1.3.2 : toujours la dernière release.
- hallmark et security-audit : pas de release, pin sur `main` inchangé (HEAD identique au SHA épinglé).
- impeccable : pin `skill-v4.10.0` (2026-11-18). Plus récentes : `skill-v4.11.0` (2026-11-24),
  `skill-v4.11.1` (2026-11-26), toutes < 7 jours, donc notées, pas adoptées. Éligible : v4.11.0 le 2026-12-01.
- caveman : pin v4.1.0 ; `v4.2.0` publiée le 2026-11-22 (4 jours), éligible le 2026-11-29.
  Tag annoté `b32e5af2…` : à déréférencer vers le commit avant épinglage (non fait).
- Aucune release de plus de 7 jours en attente : pas d'issue `area:factory`.

## 2026-11-26 — état initial (bootstrap)

- Toolchain : `rustc 1.100.0`, `cargo 1.100.0` (image `rust:1-bookworm`).
- Édition 2024, resolver 3.
- Versions résolues via `cargo info` : thiserror 2.0.21, url 2.5.9, cargo_metadata 0.23.1,
  serde 1.0.229, toml 1.2.3.
- `cargo_metadata` 0.23 : `Package::name` est un newtype `PackageName` (plus un `String`),
  `DependencyKind` a un variant caché `Unknown`. Source : `src/lib.rs`, `src/dependency.rs`.
- Cargo signale les dépendances de workspace inutilisées (`cargo::unused_workspace_dependencies`).
- Clippy : lint `assert_is_empty` (pedantic) disponible ; `disallowed-types` signale les chemins
  introuvables sauf `allow-invalid = true`.
