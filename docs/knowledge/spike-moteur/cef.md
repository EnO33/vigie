# Spike moteur — CEF 156 (crate `cef` 156.7.0+156.0.31), Linux X11 sous Xvfb

Story #18, epic #11. Prototype jetable, jamais mergé : branche `spike/moteur-cef`, SHA **`1325dd1a5baa9bed266a15bbae841cf165934a88`**
(`spike/cef/`, captures dans `spike/cef/captures/` sur cette branche). Ce SHA ajoute à `a8ed63b` (revu) `run.sh`, le choix du style de fenêtre
`VIGIE_SPIKE_WINDOW_STYLE` et l'ordre `set_background_color` / `add_child_view` ; toutes les mesures ci-dessous ont été **refaites** avec le binaire de ce SHA.
Mesures du 2026-11-27, outil `tools/spike-moteur/measure.sh` (`main` à `1eeb836`). Chaque chiffre vient d'une commande ci-dessous, recopiée.

## Machine et conditions

| | |
|---|---|
| OS / noyau | `Debian GNU/Linux 13 (trixie)` (`/etc/os-release`), `uname -srm` : `Linux 6.6.87.2-microsoft-standard-WSL2 x86_64` (conteneur de la factory) |
| CPU / mémoire | 16 CPU, `MemTotal` 16 332 988 ko |
| CEF / Chromium | `156.0.31+ge603d97+chromium-156.0.8078.100` (archive `minimal`, `linux64`) |
| Crate | `cef = { version = "=156.7.0", default-features = false }`, profil `release`, `rustc 1.100.0` |
| Affichage | `Xvfb :99 -screen 0 1280x800x24`, X11 uniquement (pas de `--ozone-platform=headless`) |
| Lancement | `spike/cef/run.sh [--tabs N]` : prépare `/tmp/cefrun`, démarre Xvfb `:99` s'il manque, exporte `DISPLAY=:99 LD_LIBRARY_PATH=/tmp/cefrun VIGIE_SPIKE_NO_SANDBOX=1` (voir « Bac à sable ») |

Le prototype (`src/main.rs`, ~150 lignes) : une fenêtre Views en style **Alloy**, un panneau (`panel_create`) de 150 px et `--tabs N`
`BrowserView` en boîte horizontale (flex 1), page locale `data:text/html,<h1>vigie spike</h1>` (aucun réseau demandé par la page).
`VIGIE_SPIKE_READY` sort au premier `on_load_end` du cadre principal. `VIGIE_SPIKE_SWITCHES=a,b` ajoute `--a --b` dans
`on_before_command_line_processing` (processus navigateur seulement).

Reproduire : `CEF_PATH=/tmp/cefdl cargo build --release` dans `spike/cef` (archive déjà extraite dans `/tmp/cefdl/156.0.31/`), puis `spike/cef/run.sh --tabs N`
(copie le binaire, `libcef.so`, `*.pak`, `*.dat`, `*.bin`, `locales/`, `libvk_swiftshader.so`, `libvulkan.so.1`, `vk_swiftshader_icd.json` dans `/tmp/cefrun`).
Le binaire n'a pas de `rpath` : `LD_LIBRARY_PATH` est obligatoire (posé par `run.sh`). Sans `run.sh`, la commande meurt (`libcef.so` introuvable, ou code 133 sans `VIGIE_SPIKE_NO_SANDBOX`). Deux builds du même SHA (avec et sans réseau, voir critère 7) donnent des binaires identiques (`cmp`).

## Bac à sable de Chromium : `--no-sandbox` nécessaire ici

Sans `VIGIE_SPIKE_NO_SANDBOX`, `spike-cef --tabs 1` s'arrête (code 133, `SIGTRAP`) avec :

```
FATAL:content/browser/zygote_host/zygote_host_impl_linux.cc:130] No usable sandbox! If you are running on Ubuntu 23.10+ or another Linux distro
that has disabled unprivileged user namespaces with AppArmor, see https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md.
Otherwise see https://chromium.googlesource.com/chromium/src/+/main/docs/linux/suid_sandbox_development.md for more information on developing with the (older) SUID sandbox.
If you want to live dangerously and need an immediate workaround, you can try using --no-sandbox.
```

Toutes les mesures utilisent `Settings.no_sandbox = 1` (variable `VIGIE_SPIKE_NO_SANDBOX`), donc **sans bac à sable** : les chiffres de mémoire
et de démarrage valent pour ce mode. Je n'ai pas essayé `chrome-sandbox` en setuid (non vérifié) : ce conteneur n'a pas de privilèges.
Dans le conteneur, `unshare -rn true` échoue aussi (`Operation not permitted`). Non vérifié : le comportement sur une machine avec user namespaces.

## Critère 6 — bibliothèques, `unsafe`

- `ldd libcef.so | grep 'not found'` : **aucune ligne** (81 lignes `ldd`, dont libX11, libnss3, libatk-1.0, libatk-bridge-2.0, libcups, libgbm, libasound,
  libxkbcommon, libpango, libcairo, libdbus-1). L'image les fournit toutes. `ldd spike-cef` : seule `libcef.so => not found` sans `LD_LIBRARY_PATH`.
- Erreurs de chargement à l'exécution (stderr) : aucune erreur de `dlopen`. Bruit constant : `ERROR:dbus/bus.cc:405 Failed to connect to the bus`
  (pas de bus D-Bus dans le conteneur), `Failed to send GetTerminationStatus message to zygote` à l'arrêt.
- Blocs `unsafe` **écrits** dans le prototype : **0** (`grep -c unsafe src/main.rs`). Blocs `unsafe {` **dans le code expansé** des macros
  `wrap_*!` du crate : **16** pour 8 types enveloppés (2 par type : `Clone::clone` et `Drop`), mesurés avec
  `RUSTC_BOOTSTRAP=1 cargo rustc --release -- -Zunpretty=expanded | grep -c 'unsafe {'`. Les règles du projet interdisent `unsafe` : il faudrait
  vérifier si les lints voient du code issu d'une macro externe (non vérifié). Les pointeurs nuls passés à `execute_process`/`initialize`
  (`windows_sandbox_info`) n'exigent aucun `unsafe`.
- Le crate lui-même contient `unsafe` partout (ex. `impl Default for BoxLayoutSettings` utilise `std::mem::zeroed()`) : c'est la surface FFI, hors du code de Vigie.

## Critère 7 — archive CEF et build sans réseau

- **URL** : `https://cef-builds.spotifycdn.com` (`DEFAULT_CDN_URL`, `download-cef-3.0.1/src/lib.rs` l. 137), surchargeable par `CEF_DOWNLOAD_URL`.
  Index `index.json` de ce CDN, archive `cef_binary_156.0.31+ge603d97+chromium-156.0.8078.100_linux64_minimal.tar.bz2` (333 321 290 octets).
- **Somme de contrôle** : SHA-1 `0adb813face4ca098f17210fe471b172c2bc1950` (`archive.json` écrit par la build ; `sha1sum` de l'archive donne la même valeur).
  Une somme **SHA-1** seulement, issue de l'index du même CDN : pas de signature (non vérifié : l'index est-il authentifié ailleurs).
- `cef-dll-sys/build.rs` télécharge l'archive **pendant `cargo build`** : sans `CEF_PATH` (l. 18-41), et **aussi avec** `CEF_PATH` si ce dossier n'existe pas
  ou si son contenu n'est pas valide (l. 87-108 : `download_to_versioned`).
- **Build hors réseau : oui, seulement si `CEF_PATH` contient `156.0.31/` et un `archive.json` valide.** `build.rs` l. 13-15 ne relance que pour `FLATPAK`, `NIX_CEF_BINARY`,
  `CEF_PATH` (pas `CEF_DOWNLOAD_URL`) : la preuve est donc faite depuis un `target/` **neuf** (`rm -rf` puis `CARGO_TARGET_DIR=/tmp/target-cef-clean`) :
  `CEF_DOWNLOAD_URL=http://127.0.0.1:9 CEF_PATH=/tmp/cefdl cargo build --release --offline` réussit (« Finished `release` profile in 21.23s », `cef-dll-sys` recompilé) ;
  un téléchargement aurait échoué sur le port 9. Je n'ai pas coupé le réseau du noyau (`unshare` refusé) : preuve indirecte.
  Taille : `du -sh /tmp/cefdl/156.0.31/cef_linux_x86_64` = **1,5 Go** (archive extraite) ; `du -sh /tmp/cefdl` = 1,9 Go (extraction + `.tar.bz2` de 333 321 290 octets). `libcef.so` fait 1 480 586 408 octets.
- Écarts `cargo deny` (établis par l'architecte le 2026-11-26, **non relancés aujourd'hui**) : `anyhow 1.0.105` interdit via la build-dependency
  de `cef-dll-sys` (`default-features = false` n'y change rien) ; licences `bzip2-1.0.6` (`libbz2-rs-sys` via `download-cef`) et `CDLA-Permissive-2.0` (`webpki-roots` via `ureq`).

## Critère 2 — démarrage

Commande (Xvfb et variables d'environnement gérés par `run.sh`) :
`bash tools/spike-moteur/measure.sh startup --runs 10 --timeout 60 -- spike/cef/run.sh --tabs N`, 10 lancements chacun, caches `/tmp/vigie-spike-cef` chauds
sauf le tout premier lancement. Mesure = spawn → `VIGIE_SPIKE_READY` (premier chargement de la page locale), pas le premier pixel visible ; elle inclut le `bash` de `run.sh` (quelques ms, non mesurés).
Trois séries de 10 lancements par cas, à la suite (charge machine = 1re valeur de `uptime`, 1 min) :

| `--tabs` | série | charge (1 min) | médiane | min | max |
|---|---|---|---|---|---|
| 1 | 1 | 1,70 | **174 ms** | 162 ms | 188 ms |
| 1 | 2 | 1,80 | **175 ms** | 161 ms | 188 ms |
| 1 | 3 | 3,10 | **175 ms** | 162 ms | 216 ms |
| 10 | 1 | 1,70 | **294 ms** | 248 ms | 345 ms |
| 10 | 2 | 2,06 | **257 ms** | 245 ms | 342 ms |
| 10 | 3 | 3,10 | **313 ms** | 244 ms | 353 ms |

Une première passe (même jour, charge ~1,3, avant ces séries) avait donné 162 ms (1 vue) et 232-244 ms (10 vues) ; elle n'est pas gardée (charge non relevée série par série).
**Écart avec la revue** : le reviewer a mesuré 203-221 ms (médianes, 1 vue) avec le binaire de `a8ed63b`, dans le même conteneur. Je n'ai pas élucidé les ~30-40 ms d'écart
(hypothèse non testée : charge ou état du cache disque à ce moment-là, dont je n'ai pas la mesure). Lecture honnête : **ordre de 160-220 ms pour 1 vue, 245-350 ms pour 10 vues**,
selon la charge de la machine ; la plage « 150-180 ms » annoncée d'abord était trop étroite.

Rejouer : `bash tools/spike-moteur/measure.sh startup --runs 10 --timeout 60 -- spike/cef/run.sh --tabs 1` (depuis la racine du dépôt, `run.sh` pris sur `spike/moteur-cef`).
Avec 10 vues, `VIGIE_SPIKE_READY` sort à la **première** page chargée : les 9 autres ne sont pas attendues.

## Critère 3 — mémoire

Commande : `measure.sh memory --settle 5 --timeout 60 -- spike/cef/run.sh --tabs N` (somme des RSS de la session, 5 s après READY ; une mesure par cas, refaite avec le binaire du SHA ci-dessus).

| `--tabs` | RSS total |
|---|---|
| 1 | **779 Mo** |
| 10 | **1752 Mo** |

Limite : le RSS additionne les pages partagées entre processus (`libcef.so` mappé par chaque processus Chromium), donc il **surestime**
la mémoire réellement consommée. Pas de PSS mesuré (non fait). Écart 1 → 10 vues : +973 Mo, soit ~108 Mo par vue supplémentaire.

## Critère 1 — réseau, page locale, sans URL

Commande : `rm -rf /tmp/vigie-spike-cef` (cache vidé avant chaque capture), puis `measure.sh network --duration 60 --timeout 90 -- spike/cef/run.sh --tabs 1` (`strace -f`, `connect/sendto/sendmsg/sendmmsg`).
Convention de comptage : **destinations = lignes `network_dest`, DNS du conteneur `127.0.0.11:53` inclus**. Deux captures par cas, la première ci-dessous.
**CEF émet du trafic réseau tout seul**, alors que la page est un `data:` :

```
network_calls=26
network_dest=127.0.0.11:53
network_dest=142.251.156.119:443
network_dest=142.251.209.110:443
network_dest=142.251.39.174:80
network_dest=192.178.204.139:443
network_dest=213.44.21.206:443
network_dest=34.104.35.123:80
network_dest=[2001:4860:4860::8888]:443
```

(`127.0.0.11:53` est le DNS du conteneur.) Seconde capture sans switches : 27 appels, mêmes 8 destinations, sauf `192.178.204.113` au lieu de `192.178.204.139`.
Les IP d'une famille changent d'une capture à l'autre (DNS, répartition de charge) ; les ports et les ensembles restent stables.

Les noms de domaine n'ont pas pu être relevés : les requêtes DNS passent par des sockets UDP déjà connectées (`send` sans adresse), limite connue de
`measure.sh`, et un `strace -e trace=send,sendmsg` n'a pas montré les noms. **Je ne les attribue pas** : `2001:4860:4860::8888` est une adresse Google Public DNS
(connaissance générale, non vérifiée ici) ; le reste est non identifié. Les `connect` observés à la seconde capture viennent d'un seul identifiant de thread/processus
(`-f` trace les threads) ; le processus exécuté de `--type=utility` (`network.mojom.NetworkService`) a un autre PID : le lien est **probable, non prouvé**.

**Seconde capture, avec switches.** #14 n'a pas établi de noms de switches (« non vérifié », `docs/knowledge/LOG.md`, Q3). J'ai donc pris des noms
connus de Chromium et vérifié seulement qu'ils sont des chaînes présentes dans `libcef.so` (`grep -c -a -F -- <nom> libcef.so` ≥ 1 pour chacun) : ce n'est **pas** une preuve de leur effet.
`VIGIE_SPIKE_SWITCHES=disable-background-networking,disable-component-update,disable-sync,no-pings,disable-domain-reliability,disable-breakpad,metrics-recording-only,disable-default-apps,no-first-run`
exportée avant `run.sh`. Présence de `--disable-background-networking` dans la ligne de commande du processus navigateur confirmée via `/proc/<pid>/cmdline` (première passe, sur `a8ed63b`) :

```
network_calls=17
network_dest=127.0.0.11:53
network_dest=142.251.156.119:443
network_dest=142.251.209.110:443
network_dest=142.251.39.174:80
network_dest=34.104.35.123:80
network_dest=[2001:4860:4860::8888]:443
```

Seconde capture avec switches : 18 appels, mêmes 6 destinations.

**Résultat : ces switches réduisent (26-27 → 17-18 appels, 8 → 6 destinations, 2 captures par cas) mais ne suppriment pas le trafic.** Les deux destinations `192.178.204.x:443` et `213.44.21.206:443` disparaissent dans les deux captures avec switches ; variance au-delà de 2 captures non mesurée. Il reste des connexions que je n'ai pas
su attribuer. Pour l'ADR (#20) : « zéro requête au démarrage » n'est **pas** acquis avec CEF 156 ; il faut une story dédiée (journaux `--log-net-log`
ou `--enable-logging=stderr --v=1` pour nommer les destinations, sur le source Chromium 156). Les connexions peuvent aussi être de simples tentatives
bloquées (`connect … = -1 ENETUNREACH` vu sur l'IPv6), le conteneur ayant un accès Internet partiel.

## Critère 4 — plusieurs vues dans une fenêtre

**Oui, avec une condition.** Capture : `DISPLAY=:99 import -window root shot.png` (ImageMagick 7.1.1-43, `xwd` absent), après 6 s, `--tabs 2` : un panneau de 150 px à gauche
(fond gris clair du panneau ; la couleur `0xFF336699` demandée par `set_background_color` n'est **pas** appliquée) et **deux vues web** côte à côte,
chacune affichant « vigie spike » (`spike/cef/captures/multiview-2tabs-panel.png` sur `spike/moteur-cef`).

Condition établie par l'essai : avec le style par défaut (Chrome) pour les **vues**, le deuxième `BrowserView` est refusé :
`ERROR:cef/libcef/browser/views/browser_view_impl.cc:324] Cannot add multiple Chrome style BrowserViews`. Il faut donc le style **Alloy pour chaque vue**
(`BrowserViewDelegate::browser_runtime_style`), ce que fait le prototype. La doc C de `cef_runtime_style_t` (`cef-dll-sys` bindings l. 17569, `x86_64_unknown_linux_gnu.rs`) dit en entier :
« Alloy style Windows with the Views framework can host only Alloy style BrowserViews but Chrome style Windows can host both style BrowserViews. Additionally, a Chrome style
Window can host at most one Chrome style BrowserView but potentially multiple Alloy style BrowserViews. »
**Le style de la fenêtre n'a donc pas besoin d'être Alloy.** Testé (`VIGIE_SPIKE_WINDOW_STYLE=chrome spike/cef/run.sh --tabs 2`, capture `spike/cef/captures/multiview-2tabs-chrome-window.png`) :
fenêtre en style Chrome + 2 vues Alloy, les deux pages s'affichent, aucune erreur `Cannot add multiple` dans la sortie. Ce que je n'ai pas observé : aucune barre d'outils Chrome n'est visible sur la capture (cause non établie ; pas de gestionnaire de fenêtres sous Xvfb) ; l'apport réel du style Chrome pour la fenêtre (UI, extensions) n'est donc pas évalué. Sans flex, les vues gardent leur taille préférée (100×100) : il faut `set_flex_for_view` et
`cross_axis_alignment = STRETCH`. Testé avec 2 vues (visuel, fenêtre Alloy et fenêtre Chrome) et 10 vues (démarrage, mémoire, fenêtre Alloy) ; pas de capture à 10 vues.

Couleur du panneau : hypothèse de la revue (`cef-dll-sys` bindings l. 32590 : « background color will be automatically reset when OnThemeChanged is called » ;
l. 32260 : `OnThemeChanged` est appelé quand la vue est ajoutée à une fenêtre). Testée : `set_background_color` déplacé **après** `add_child_view` (`main.rs` du SHA ci-dessus) :
la capture est **octet pour octet identique** (`cmp`) à celle d'avant. La cause reste donc **inconnue** ; l'hypothèse OnThemeChanged-à-l'ajout n'explique pas à elle seule l'échec
(autre piste non testée : thème rappelé plus tard, ou couleur ignorée pour un `Panel` sans fond opaque).

## Critère 5 — processus de rendu tué (`kill -9`)

`--tabs 1`, ~6 s après le lancement. Les rendus gardent la ligne de commande du zygote ; plusieurs enfants du zygote existent et seul le rendu fait sortir le callback.
Commande qui a fonctionné deux fois de suite (le rendu est le plus grand PID enfant du zygote sans `--no-zygote-sandbox` ; règle empirique, 2 essais) :
`Z=$(pgrep -f -- '--type=zygote --no-sandbo[x]' | head -1); kill -9 "$(pgrep -P "$Z" | sort -n | tail -1)"` (les crochets évitent que `pgrep` se retrouve lui-même).
Lors d'un premier essai à la main, `kill -9` sur les deux autres enfants du zygote n'a rien déclenché et l'hôte a survécu. Sortie du prototype :

```
VIGIE_SPIKE_RENDER_TERMINATED status=TerminationStatus(TS_PROCESS_WAS_KILLED) code=9 msg=9
```

**L'hôte survit** (`ps` : processus navigateur toujours `Ssl` 3 s après). Le callback est
`RequestHandler::on_render_process_terminated` (`ImplRequestHandler`, branché via `Client::request_handler`). La vue est devenue **grise unie** (fond clair de la fenêtre ; capture Xvfb 3 s
après le kill) : aucune page d'erreur ni rechargement automatique ; c'est à l'application de recharger. Un seul cas testé (1 vue, rendu tué) ; pas testé : GPU, `network service`,
plusieurs vues partageant un rendu.

## Non vérifié

- Fonctionnement avec bac à sable activé ; chiffres de démarrage et de mémoire valables seulement sans bac à sable.
- Noms de domaine contactés ; effet réel de chaque switch ; processus à l'origine des connexions.
- `cargo deny` sur le projet (repris de l'architecte, non relancé).
- Autre machine que ce conteneur WSL2 ; Wayland (CEF Views sous X11 seulement ici).
- Cause de la couleur de fond du panneau ignorée ; apport du style Chrome pour la fenêtre ; comportement avec 10 vues à l'écran ; écart de démarrage avec la revue (203-221 ms contre 162-175 ms).
