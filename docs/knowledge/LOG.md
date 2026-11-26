# Journal de veille (tenu par `tech-watch`)

Faits vérifiés, datés, sourcés. Plus récent en haut.

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
  `attributes.url`, sinon `load_html`). Des réglages posés après le build laissent donc la première page
  aux défauts WebKit. Piste : construire sans `with_url`/`with_html`, poser les réglages via
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
    certificats invalides, aucun trafic n'est coupé. Appeler la version `WebContextExt` fait échouer le
    build : le workspace a `deprecated = "deny"` (`Cargo.toml` l. 27).
  - `WebsiteDataManager` (`website_data_manager.rs`) : `is_ephemeral` l. 566 est un **getter** en lecture
    seule (`fn is_ephemeral(&self) -> bool`), pas un interrupteur. Pour régler : `WebsiteDataManager::new_ephemeral()`
    (l. 43) ou la propriété du builder `is_ephemeral(self, bool)` (l. 157) ; côté wry, `WebContext::new_ephemeral()`
    (`src/webkitgtk/web_context.rs` l. 54). Aussi `set_itp_enabled` (l. 577), `set_network_proxy_settings` (l. 589).
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
- Autre point : `ImplBrowserProcessHandler::on_before_child_process_launch` (l. 29342).
- `Settings` (`cef::Settings`, `cef-156.7.0+156.0.31/src/bindings/x86_64_unknown_linux_gnu.rs` l. 556-589 ;
  équivalent C `_cef_settings_t`, `cef-dll-sys-…/x86_64_unknown_linux_gnu.rs` l. 17791) : `no_sandbox`, `cache_path`, `root_cache_path`,
  `persist_session_cookies`, `command_line_args_disabled`, `accept_language_list`, `disable_signal_handlers`.
  Doc C de `cache_path` (`cef-dll-sys-…` doc l. 17810, champ l. 17811) : vide → « incognito mode », caches en mémoire,
  rien de spécifique au profil sur disque, **mais** « installation-specific data will still be persisted
  in root_cache_path ». Doc de `root_cache_path` (doc l. 17812, champ l. 17813) : si les deux sont vides, répertoire par
  défaut `~/.config/cef_user_data` sous Linux ; verrou singleton basé sur cette valeur depuis CEF 120.
  Donc « rien sur disque » n'est pas acquis : des données d'installation restent écrites.
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
  `chromium.googlesource.com` : 404). À établir dans une story dédiée, avec la source Chromium de 156.0.31.

### Q4 — Modèle de processus
- CEF : le crash du rendu est signalé au processus navigateur par
  `ImplRequestHandler::on_render_process_terminated(browser, status: TerminationStatus, error_code,
  error_string)` (`cef` l. 27024 ; doc C `cef-dll-sys` l. 28920 : « Called on the browser process UI
  thread when the render process terminates unexpectedly »). Le callback tourne dans le processus hôte,
  ce qui montre qu'il existe un processus séparé ; que l'hôte survive à un crash reste **non mesuré**.
  Aussi `on_render_process_unresponsive` (l. 27014, 15 s sans événement d'entrée, doc C).
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
  Pas de pont wry sans handler. Que `window.chrome.webview` soit exposé par le runtime WebView2 même
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
- Navigation autorisée : `with_navigation_handler(impl Fn(String) -> bool)` l. 1309 (`false` bloque).
- Nouvelle fenêtre : `with_new_window_req_handler` l. 1407. Proxy : `with_proxy_config` l. 1460.
- Vues multiples : `build_as_child` l. 1573 ; Linux **X11 uniquement**, Wayland via
  `WebViewBuilderExtUnix::build_gtk` (l. 2041, 2061) avec `gtk::Fixed` ; `gtk::init` requis, boucle GTK à
  avancer avec `gtk::main_iteration_do` ; **panique** si `gtk::init` n'a pas été appelé **dans le même
  thread** (doc de `build` l. 1541-1544, doc de `build_as_child` l. 1569-1572, doc de `build_gtk` l. 2040). La doc dit aussi « panique si le
  handle est invalide » (l. 1571), mais la source Linux est différente : `build_as_child` → `new_as_child`
  (l. 1576) → `new_x11` (`src/webkitgtk/mod.rs` l. 132) : un handle non Xlib renvoie
  `Err(Error::UnsupportedWindowHandle)` (l. 150-152), sans panique ; deux paniques
  sous Linux : l. 157 `gdk::Display::default()` appelle `assert_initialized_main_thread!()`
  (`R/gdk-0.18.2/src/auto/display.rs` l. 301 ; macro `gdk-0.18.2/src/rt.rs` l. 16-25 : « GDK may only be used
  from the main thread » ou « GDK has not been initialized ») ; l. 158
  `gdk_display.downcast_ref::<X11Display>().unwrap()` quand le display GDK par défaut n'est pas X11.
  Réserve : wry demande `gtk = "0.18"` (`wry-0.57.3/Cargo.toml` l. 204-205), gtk-0.18.2 demande
  `gdk = "0.18"` (l. 74-75) ; gdk-0.18.2 est la seule version du registre, aucun Cargo.lock du dépôt ne
  résout wry : version effective **non vérifiée.** Panique pour handle invalide hors Linux : **non vérifié.** `set_bounds` (l. 2266) n'agit que pour un enfant ou `build_gtk` + `gtk::Fixed`.
- Conséquence : le futur `PageEngine` doit vérifier que le display GDK est X11 et que `gtk::init` a été
  appelé sur ce thread avant `build_as_child` ; valider le handle ne suffit pas (la panique ne se rattrape
  pas côté Rust strict).
- CEF : titre `on_title_change` (`cef` l. 17770), URL `on_address_change` (l. 17762), chargement
  `on_load_start` (l. 21584) / `on_load_end` (l. 21592), navigation `on_before_browse` (l. 26940).
  Vues multiples côté CEF : **non vérifié.**

### Non vérifié (récapitulatif)
Défauts des réglages WebKit ; OCSP/CRL et rapports WebKitGTK ; flags WebView2 de mise à jour/crash/
télémétrie ; tous les switches Chromium de CEF ; survie de l'hôte à un crash de rendu (3 moteurs) ;
préférences/policies CEF (noms) ; `<link rel=prefetch>` ; `window.chrome.webview` sans handler ; sémantique de `msSmartScreenProtection` ;
panique pour handle invalide hors Linux ; doc C de `set_preference` ; héritage du contexte par une vue `with_related_view` ; persistance par défaut sans `WebsiteDataManager` ; sémantique de `world_name` (`for_world`) et monde de `UserScript::new` (WebKitGTK) ; ordre réglages/premier chargement (WebKitGTK) ; URL et version des pages Microsoft WebView2 ; constats tirés de la doc 2.42.5 (non vérifiés pour 2.38) ; monde d'exécution des scripts WebView2 et CEF ; vues multiples CEF ; pont par défaut CEF ; `tao` non lu.

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
