# Spike UI — chrome en webview (A) contre UI native Rust (B), sur wry 0.57.3

Story #19, epic #11. Prototype jetable, jamais mergé : branche `spike/ui`, SHA **`cd850ea09b37bfdda4f9a8fc615997ac1c41a027`**
(`spike/ui-a/`, `spike/ui-b/`, captures dans `spike/captures/`, `Cargo.lock` commités). Binaires : `cargo build --release` dans chaque crate.
Partie de `spike/moteur-wry` (`b09111b`, #17). Outil : `tools/spike-moteur/measure.sh` (`main`). Chiffres recopiés des commandes ci-dessous.

## Machine et conditions

Même conteneur que #17 : Debian 13, `Linux 6.6.87.2-microsoft-standard-WSL2 x86_64`, 16 CPU, `MemTotal` 16 332 988 ko, WebKitGTK 2.54.3, `rustc 1.100.0`, `Xvfb :98 -screen 0 1280x800x24`, sans gestionnaire de fenêtres.
Versions : `wry =0.57.3`, `tao =0.37.3` (A), `eframe =0.37.0` avec `default-features = false, features = ["x11", "glow", "system_fonts", "accesskit"]` (B, config de l'arbitrage de l'architecte). wry 0.57.3 gardée pour rester comparable à #17.

**Écart d'environnement (à traiter par le board)** : l'image n'a pas `libxkbcommon-x11.so.0` ni `libxcb-xkb.so.1`, que winit charge à l'exécution : (B) panique sans elles (`Library libxkbcommon-x11.so could not be loaded.`). Contournement local, rien d'installé dans le système : `.deb` Debian trixie `libxkbcommon-x11-0 1.7.0-2` et `libxcb-xkb1 1.17.0-2+b1`, SHA256 vérifié contre l'index `Packages` du dépôt (non vérifié : signature de l'index), extraits par `dpkg -x` dans `/tmp/xkb/root`, puis `LD_LIBRARY_PATH=/tmp/xkb/root/usr/lib/x86_64-linux-gnu`. (A) n'en a pas besoin.

## Variantes

- **(A)** `spike/ui-a/src/main.rs` : fenêtre tao, **panneau = vue wry de 300 px avec `with_ipc_handler`**, vues de page (`--tabs N`) **sans** `with_ipc_handler`, comme #17 mais sans pompe GTK (tao la pompe déjà). « 1 onglet » = 2 vues, « 10 onglets » = 11 vues.
- **(B)** `spike/ui-b/src/main.rs` : fenêtre **winit d'eframe**, panneau natif egui (`Panel::left(..).exact_size(300.0)`), vues de page = vues wry enfants de la fenêtre (`build_as_child(frame)`), **sans** `ipc_handler`. « 1 onglet » = 1 vue, « 10 onglets » = 10 vues. GTK est pompée à la main à chaque `ui()` (winit ne le fait pas). **tao n'est pas utilisé : eframe fournit la boucle winit** ; wry et eframe cohabitent.
- Même réglage que #17 : pas de `with_web_context` partagé, donc chaque vue a son `WebContext` : les RSS sont des **bornes hautes** (voir #17).

## Critère 1 — démarrage et mémoire

```
DISPLAY=:98 measure.sh startup --runs 10 -- ./ui-a/target/release/spike-ui-a --tabs 1
→ startup_median_ms=291  startup_min_ms=285  startup_max_ms=298
DISPLAY=:98 measure.sh startup --runs 10 -- ./ui-b/target/release/spike-ui-b --tabs 1
→ startup_median_ms=444  startup_min_ms=433  startup_max_ms=448
DISPLAY=:98 measure.sh memory --settle 5 -- … --tabs 1 / --tabs 10
→ A : memory_rss_mb=674 / 2637      B : memory_rss_mb=451 / 2415
```

| | (A) chrome webview | (B) eframe natif | Réf. #17 (sans pompe) |
|---|---|---|---|
| démarrage médian (min–max) | 291 ms (285–298) | 444 ms (433–448) | 297 ms |
| RSS, 1 onglet | 674 Mo (2 vues) | 451 Mo (1 vue) | 655 Mo |
| RSS, 10 onglets | 2637 Mo (11 vues) | 2415 Mo (10 vues) | 2616 Mo |

Lecture : (B) économise une vue web, soit **≈ 220 Mo** (2637 − 2415 = 222 ; 674 − 451 = 223), c.-à-d. le coût d'une vue de #17 (≈ 216-218 Mo) : le panneau egui + eframe/glow coûte **≈ rien en RSS mesurée** à côté. Mais (B) démarre **≈ 150 ms plus tard** (444 contre 291).
**Biais** : (1) `DELAY` : (B) ne crée les vues qu'au 6ᵉ frame (voir critère 3), avec `request_repaint_after(16 ms)` ; cela pèse environ 80-100 ms du retard, **non isolé** (non mesuré avec un délai différent). (2) Le READY de (A) vient de l'onglet 0, créé après le panneau ; celui de (B) de la seule vue. (3) Les RSS comptent plusieurs fois les pages partagées (pas de PSS). Pages triviales. Dispersion : ±2-3 % sur 10 runs.

## Critère 2 — isolation IPC (variante A) : **le message n'atteint pas l'hôte**

```
DISPLAY=:98 ./ui-a/target/release/spike-ui-a --tabs 1 --ipc-test   (stderr de l'hôte)
HOST_IPC_PANEL body="panel-x"
PAGE_PROBE tab=0 title="ipc:undefined:TypeError mh:undefined"
```
La page de test exécute `window.ipc.postMessage('x')` : `typeof window.ipc` = `undefined`, l'appel lève `TypeError`, et `window.webkit.messageHandlers.ipc` est aussi `undefined`. **Le journal de l'hôte ne contient aucune ligne `body="x"`** : seul le panneau (contrôle positif, `panel-x`) est reçu. Le constat de la page remonte par le titre du document (`with_document_title_changed_handler`, instrument de test, pas un pont).
Cause, lue dans la source (`wry-0.57.3/src/webkitgtk/mod.rs` l. 314-316, 351-352 et 757) : `window.ipc` et le `script_message_handler` « ipc » ne sont installés que si `ipc_handler` est `Some` pour cette vue. Chaque vue est séparée : un handler sur le panneau n'expose rien aux vues de page.
Limite : le pont **titre → hôte** existe (le handler de titre), et c'est un canal à ne pas laisser dans le vrai shell. Seul `ipc` est testé ; pas de `custom_protocol`, pas de navigation vers un autre schéma. Le reviewer relance : la commande ci-dessus.

## Critère 3 — variante B sous Xvfb : panneau natif et vue de page **visibles ensemble**

Capture : `spike/captures/ui-b.png` (`import -window root`, 1280×800) : panneau egui gris foncé « panneau / 1 onglet(s) » (x 0-300) et vue « onglet 0 » blanche. La capture de (A) : `spike/captures/ui-a.png`.
Ce qui a échoué d'abord (**à retenir pour ADR-0004**) :
1. `libxkbcommon-x11` / `libxcb-xkb` absentes de l'image (voir plus haut).
2. **`GLXBadWindow` (`XMapRaised`) si les vues wry sont créées pendant le premier `ui()`** : winit panique (`Failed to call XMapRaised: XError { description: "GLXBadWindow", error_code: 170, … }`). Le même binaire sans vues (`--no-views`) s'affiche ; les vues créées après 5 frames (`DELAY=5`) marchent. Cause (ordre de création GLX/`XCreateSimpleWindow` ou mappage retardé par eframe) **non établie**. `LIBGL_ALWAYS_SOFTWARE=1` et un Xvfb `+extension GLX` n'y changent rien. Le fallback `wgpu` de l'arbitrage n'a pas été nécessaire : `glow` rend sous Xvfb.
3. Une bande noire d'environ 13 px sépare le panneau de la vue (la vue démarre à x = 313 dans la capture alors que `with_bounds` demande 300) : cause **non cherchée** (marge de page, ou décalage du fond non repeint).
Non testés : ordre d'empilement avec un menu egui qui déborde sur la vue, focus clavier, redimensionnement, Wayland.

## Critère 4 — réseau (`strace -f`, 60 s)

```
DISPLAY=:98 measure.sh network --duration 60 -- ./ui-a/target/release/spike-ui-a --tabs 1   → network_calls=0
DISPLAY=:98 measure.sh network --duration 60 -- ./ui-b/target/release/spike-ui-b --tabs 1   → network_calls=0
```
Aucune connexion AF_INET/AF_INET6, comme la variante wry de #17 (`network_calls=0`, valeur du document #17, **non remesurée ici**). `system_fonts` n'ajoute aucune connexion observée. Mêmes limites que #17 : pas de paquets, `send()` sans adresse non vu, page locale.

## Critère 5 — `cargo deny` (variante B)

```
cd spike/ui-b && cargo deny --config ../../deny.toml check bans licenses sources
→ bans ok, licenses ok, sources ok
```
Config d'eframe sans les features par défaut : conforme à la décision 2 de l'architecte (les polices par défaut OFL-1.1 / Ubuntu-font-1.0 sont refusées par `deny.toml`). Avertissements : des `duplicate` (bitflags, objc2*, rustix, thiserror, windows-*, …). `advisories` non lancé.

## À retenir pour l'ADR-0004

- Chiffres : (B) −220 Mo (une vue en moins) mais +150 ms au démarrage ; (A) a la même base que #17.
- (A) : isolation IPC **prouvée** (`window.ipc` n'existe que sur le panneau). (B) n'a aucun pont par construction.
- (B) a un coût d'intégration : winit (eframe) au lieu de tao, GTK à pomper à la main, `GLXBadWindow` à contourner (vues créées après quelques frames), deux bibliothèques X11 supplémentaires à l'exécution, ~400 crates de plus (`cargo tree` non compté : non vérifié).
- Non mesuré : vraie page web, PSS, HiDPI, Wayland, Windows/macOS, accessibilité (`accesskit` compilé, non testé), rendu des polices système, `wgpu`.
