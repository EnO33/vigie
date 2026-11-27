# Spike moteur — wry 0.57.3 + tao 0.37.3 (WebKitGTK), Linux X11 sous Xvfb

Story #17, epic #11. Prototype jetable, jamais mergé : branche `spike/moteur-wry`, SHA **`b09111ba1126add30fc92e79842ecae8c57d9414`**
(`spike/wry/`, captures dans `spike/wry/captures/`, `Cargo.lock` commité). Les chiffres de ce document viennent du binaire construit à ce SHA
(`cargo build --release --locked`) ; les deux commits de la branche (`70a7fe0`, `b09111b`) diffèrent par la largeur du panneau (150 → 300 px), la position/largeur des onglets (150/850 → 300/700), la disposition `--all-visible` (425 → 350) et la couleur de fond du panneau, et `b09111b` ajoute la capture. Les mesures « sans pompe » (critères 2 et 3) viennent d'une variante locale non commitée de `b09111b` (voir « Biais du prototype »).
Outil : `tools/spike-moteur/measure.sh` (`main` à `da9b69b`). Chaque chiffre vient d'une commande recopiée ci-dessous.

## Machine et conditions

| | |
|---|---|
| OS / noyau | `Debian GNU/Linux 13 (trixie)`, `Linux 6.6.87.2-microsoft-standard-WSL2 x86_64` (conteneur de la factory) |
| CPU / mémoire | Intel Core i9-9900K, 16 CPU, `MemTotal` 16 332 988 ko |
| WebKitGTK | `pkg-config --modversion webkit2gtk-4.1` → **2.54.3** |
| Crates | `wry =0.57.3`, `tao =0.37.3`, `webkit2gtk =2.0.2` (feature `v2_38`), `gtk 0.18.2` ; profil `release`, `rustc 1.100.0` |
| Affichage | `Xvfb :98 -screen 0 1280x800x24` (`run.sh`), X11 seulement |

Versions : 0.57.3 / 0.37.3 sont les dernières éligibles (≥ 7 jours), vérifié à l'API crates.io le 2026-11-27 : wry 0.57.3 publiée le 2026-11-18, 0.57.4 le 2026-11-25 (< 7 j) ; tao 0.37.3 le 2026-11-18, 0.38.0 le 2026-11-24 (< 7 j). Revue PR #33, tour 2.
Le build contre WebKitGTK 2.54.3 **réussit** (point « non vérifié » de l'arbitrage : levé).

Le prototype (`src/main.rs`, ~70 lignes) : une fenêtre tao 1000×600, `gtk::init()` avant les vues, HTML en ligne (`with_html`, aucune URL réseau),
une vue « panneau » (300 px, fond jaune) plus `--tabs N` vues enfants (`build_as_child`), `with_bounds` ; panneau et onglet 0 visibles sans `--all-visible`, onglets 1..N-1 masqués
(`set_visible(false)`). `VIGIE_SPIKE_READY` au premier `PageLoadEvent::Finished` de l'onglet 0 (`println!` + `flush`).
`--net-settings` : `with_incognito(true)` + `set_enable_dns_prefetching(false)` + `set_enable_hyperlink_auditing(false)` via `WebViewExtUnix::webview()` (réglages de #14), appliqués **après** `build_as_child` : le premier chargement se fait sans ces deux réglages.
**`--tabs N` crée N vues d'onglet plus le panneau** : « 1 onglet » = 2 vues, « 10 onglets » = 11 vues.

Lancement : `cd spike/wry && cargo build --release`, puis `DISPLAY=:98 measure.sh … -- ./target/release/spike-wry --tabs N` (Xvfb `:98` démarré avant, `run.sh` le fait).

## Critère 1 — réseau (`strace -f`, 60 s)

```
DISPLAY=:98 measure.sh network --duration 60 -- ./target/release/spike-wry --tabs 1
→ network_calls=0   (aucune ligne network_dest)
DISPLAY=:98 measure.sh network --duration 60 -- ./target/release/spike-wry --tabs 1 --net-settings
→ network_calls=0
```

**Aucune connexion AF_INET/AF_INET6 observée** : pas de seconde capture nécessaire ; je l'ai faite quand même avec les réglages de #14 : aussi 0.
Vérification que `strace -f` voit bien tout l'arbre : un essai `strace -f -e trace=connect,execve` montre l'exécution de `WebKitNetworkProcess` et `WebKitWebProcess` (2 de chaque) ; 12 `connect`, tous `AF_UNIX`.
Limites : **pas de `tcpdump` ni `CAP_NET_RAW`** (décision du board, #13) : on voit les appels `connect`/`sendto`/`sendmsg` des processus, pas les paquets ; un `send()` sur socket déjà connectée n'est pas tracé.
Page locale seulement : le résultat ne dit rien du trafic d'une vraie page web. Les réglages #14 (appliqués après le 1er chargement) n'ont donc **aucun effet mesurable ici** (rien à éteindre).

## Critère 2 — démarrage

```
DISPLAY=:98 measure.sh startup --runs 10 -- ./target/release/spike-wry --tabs 1
startup_median_ms=310  startup_min_ms=296  startup_max_ms=338
```
Xvfb déjà lancé (hors mesure). Dispersion de ce binaire : 296–338 ms, soit environ ±7 % autour de la médiane.
**Biais** : ce binaire ajoute `ControlFlow::Poll`, une seconde pompe GTK et `sleep(5 ms)` à chaque événement (`main.rs` l. 62-66). Variante sans ces lignes, même machine, même jour (`--runs 10`) :
`startup_median_ms=297  startup_min_ms=285  startup_max_ms=298`. Le même binaire `b09111b` remesuré juste après : `310 / 297 / 322`. Pour la comparaison avec CEF (ADR-0004), préférer la variante sans pompe (297 ms) ; l'écart de 13 ms reste du même ordre que la dispersion.

## Critère 3 — mémoire (RSS total de la session, `--settle 5`)

```
DISPLAY=:98 measure.sh memory --settle 5 -- ./target/release/spike-wry --tabs 1    → memory_rss_mb=652   (2 vues)
DISPLAY=:98 measure.sh memory --settle 5 -- ./target/release/spike-wry --tabs 10   → memory_rss_mb=2599  (11 vues)
```
≈ +216 Mo par vue supplémentaire (variante sans pompe : 655 puis 2616 Mo, ≈ +218 Mo par vue ; le biais de pompe est donc négligeable ici). **Biais de contexte** : le prototype ne passe pas de `with_web_context`, donc chaque vue crée son propre `WebContext` (`wry-0.57.3/src/webkitgtk/mod.rs` l. 259-269, `Default::default()` ; `new_ephemeral()` par vue en incognito) et lance son propre `WebKitNetworkProcess` (2 pour 2 vues, voir critère 1). Un navigateur réel partagerait le contexte : **ce +216 Mo par vue est une borne haute, non remesurée avec un `WebContext` partagé**. **Biais** : `measure.sh` additionne les RSS, donc compte plusieurs fois les pages partagées (bibliothèques WebKitGTK/GTK) : valeur haute, pas de PSS.
Les 10 pages étant triviales, un onglet réel pèsera plus.

## Critère 4 — plusieurs vues web à côté d'un panneau : **OUI**

Commande : `spike-wry --tabs 2 --all-visible` sous `DISPLAY=:98`, puis `import -window root captures/tabs2-panel.png` (ImageMagick `import` ; `xwd` absent de l'image).
Preuve : `spike/wry/captures/tabs2-panel.png` (branche `spike/moteur-wry`, 1280×800) : panneau jaune « panneau » (x 0-300) et deux vues « onglet 0 » (x 300-650) et « onglet 1 » (x 650-1000) dans la même fenêtre tao.
Constat : **une vue web de 150 px de large reste noire** (contenu non peint, 3 essais, y compris avec panneau créé après les onglets) ; 300 px s'affiche. Cause **non cherchée**. La capture est faite sans gestionnaire de fenêtres.
Seul `with_bounds` positionne les vues (chaque vue = une fenêtre X11 enfant, `webkitgtk/mod.rs` l. 196-225) ; l'ordre d'empilement et le focus clavier **ne sont pas testés**.

## Critère 5 — `kill -9` du processus de rendu

Commande : l'hôte (`spike-wry --tabs 1`) tourne ; `kill -9` sur les deux `WebKitWebProcess` (une vue panneau + une vue onglet) ; observation 4 s plus tard.
- **L'hôte survit** (`ps` : état `Sl`, toujours vivant), rien sur stderr, aucune fermeture de fenêtre.
- **Signal reçu par l'hôte : `SIGCHLD`.** Rejoué avec `strace -f -e trace=none -e signal=SIGCHLD` puis `kill -9` du `WebKitWebProcess` enfant de l'hôte : l'hôte (pid 39950, `Tgid` identique) reçoit `SIGCHLD {si_code=CLD_KILLED, si_status=SIGKILL}` pour le pid tué ; les `WebKit*Process` sont ses enfants directs (`ps -o ppid=`), sans processus intermédiaire. Le « pid 7374 » d'une trace antérieure était très probablement un thread de l'hôte (`strace -f` préfixe par tid) ; **non prouvé** pour ce pid, et l'hypothèse d'un bac à sable bubblewrap est abandonnée. Les autres `SIGCHLD` vus sont des enfants sortis avec le code 1.
- Les `WebKitWebProcess` **ne sont pas relancés** (plus aucun processus de ce nom) ; la dernière image reste à l'écran (pixels inchangés dans la capture). Le prototype n'enregistre pas `web-process-terminated` : le **signal côté API WebKit n'est pas testé**.

## Critère 6 — `cargo deny`

```
cd spike/wry && cargo deny --config ../../deny.toml check bans licenses sources
→ bans ok, licenses ok, sources ok   (cargo-deny 0.22.0)
```
Avertissements : 10 `duplicate` (toml_edit, syn, proc-macro-crate, winnow, windows-sys, toml_datetime, thiserror-impl, thiserror, heck, bitflags) et 2 `license-not-encountered` : conforme au constat de l'architecte.
`advisories` non demandé, non lancé.

## Critère 7 — `unsafe`

- Blocs `unsafe` **écrits** dans le prototype : **0** (`grep -c unsafe spike/wry/src/main.rs` → 0).
- Dans wry 0.57.3 (lecture de source, hors code de Vigie) : 28 occurrences du mot `unsafe` dans `src/webkitgtk/` (22 dans `mod.rs`, 4 `web_context.rs`, 2 `drag_drop.rs`) et 1 dans `src/lib.rs` (`grep -rc unsafe`), surtout FFI Xlib/GDK de la branche X11. Non classé bloc/mot-clé.
- Écart aux règles strictes : aucune ligne du prototype n'enfreint `unsafe`, mais il utilise `unwrap` (6 `unwrap()`, `grep -o` sur `main.rs`), `as` (1) et aucune erreur typée : tout est à réécrire pour le vrai shell.

## À retenir pour l'ADR-0004

- **wry sous Linux = X11 uniquement** pour `build_as_child` (doc wry l. 1558-1566, relue par #14) ; ici le test est sous X11, **Wayland non testé**.
- **tao pompe déjà GTK** : `tao-0.37.3/src/platform_impl/linux/event_loop.rs` l. 226 (`gtk::init()?`) et l. 1184 (`gtk::main_iteration_do(blocking)`). La pompe ajoutée au prototype est inutile : sans `ControlFlow::Poll`, sans pompe et sans `sleep`, la variante rend le panneau jaune et deux onglets (`--tabs 2 --all-visible`, capture `import -window root`, pixels (100,100) jaune, (400,100) et (800,300) blancs) et émet `VIGIE_SPIKE_READY`. L'exemple `winit.rs` de wry concerne winit, pas tao.
- `Gdk-CRITICAL _gdk_frame_clock_freeze` écrit une fois sur stderr au démarrage : sans effet visible, cause non cherchée.
- Non vérifié : `Gdk-CRITICAL` non reproduit à chaque run, `cargo deny` non relancé depuis la mesure.
- Non mesuré : vraie page web, trafic réseau réel, Windows/macOS, PSS mémoire, HiDPI.
