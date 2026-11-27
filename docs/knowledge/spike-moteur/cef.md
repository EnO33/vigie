# Spike moteur — CEF 156 (crate `cef` 156.7.0+156.0.31), Linux X11 sous Xvfb

Story #18, epic #11. Prototype jetable, jamais mergé : branche `spike/moteur-cef`, SHA **`a8ed63b334a4b9ddfa081a271f4a536fc648684e`**
(`spike/cef/`, la capture d'écran est dans `spike/cef/captures/multiview-2tabs-panel.png` sur cette branche).
Mesures du 2026-11-27, outil `tools/spike-moteur/measure.sh` (`main` à `1eeb836`). Chaque chiffre vient d'une commande ci-dessous, recopiée.

## Machine et conditions

| | |
|---|---|
| Noyau (`uname -srm`) | `Linux 6.6.87.2-microsoft-standard-WSL2 x86_64` (conteneur de la factory) |
| CPU / mémoire | 16 CPU, `MemTotal` 16 332 988 ko |
| CEF / Chromium | `156.0.31+ge603d97+chromium-156.0.8078.100` (archive `minimal`, `linux64`) |
| Crate | `cef = { version = "=156.7.0", default-features = false }`, profil `release`, `rustc 1.100.0` |
| Affichage | `Xvfb :99 -screen 0 1280x800x24`, X11 uniquement (pas de `--ozone-platform=headless`) |
| Environnement commun | `DISPLAY=:99 LD_LIBRARY_PATH=/tmp/cefrun VIGIE_SPIKE_NO_SANDBOX=1` (voir « Bac à sable ») |

Le prototype (`src/main.rs`, ~150 lignes) : une fenêtre Views en style **Alloy**, un panneau (`panel_create`) de 150 px et `--tabs N`
`BrowserView` en boîte horizontale (flex 1), page locale `data:text/html,<h1>vigie spike</h1>` (aucun réseau demandé par la page).
`VIGIE_SPIKE_READY` sort au premier `on_load_end` du cadre principal. `VIGIE_SPIKE_SWITCHES=a,b` ajoute `--a --b` dans
`on_before_command_line_processing` (processus navigateur seulement).

Reproduire : `CEF_PATH=/tmp/cefdl cargo build --release` dans `spike/cef`, puis copier dans un dossier `/tmp/cefrun` le binaire, `libcef.so`,
`*.pak`, `*.dat`, `*.bin`, `locales/`, `libvk_swiftshader.so`, `libvulkan.so.1`, `vk_swiftshader_icd.json` (depuis `$CEF_PATH/156.0.31/cef_linux_x86_64`).
Le binaire n'a pas de `rpath` : `LD_LIBRARY_PATH` est obligatoire. Deux builds du même SHA (avec et sans réseau, voir critère 7) donnent des binaires identiques (`cmp`).

## Bac à sable de Chromium : `--no-sandbox` nécessaire ici

Sans réglage, `./spike-cef --tabs 1` s'arrête (code 133, `SIGTRAP`) avec :

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
- `cef-dll-sys/build.rs` télécharge l'archive **pendant `cargo build`** si le dossier n'existe pas (l. 18-41, relu aujourd'hui). Sans `CEF_PATH`, il télécharge.
- **Build sans réseau : oui, avec `CEF_PATH`.** Preuve : `CEF_DOWNLOAD_URL=http://127.0.0.1:9 CEF_PATH=/tmp/cefdl cargo build --release --offline`
  réussit (« Finished `release` profile in 27.80s ») ; un téléchargement aurait échoué sur le port 9. Je n'ai pas coupé le réseau du noyau
  (`unshare` refusé), la preuve est donc indirecte. L'archive extraite occupe 1,9 Go dans `CEF_PATH`, `libcef.so` fait 1 480 586 408 octets.
- Écarts `cargo deny` (établis par l'architecte le 2026-11-26, **non relancés aujourd'hui**) : `anyhow 1.0.105` interdit via la build-dependency
  de `cef-dll-sys` (`default-features = false` n'y change rien) ; licences `bzip2-1.0.6` (`libbz2-rs-sys` via `download-cef`) et `CDLA-Permissive-2.0` (`webpki-roots` via `ureq`).

## Critère 2 — démarrage

Commande : `measure.sh startup --runs 10 --timeout 60 -- /tmp/cefrun/spike-cef --tabs N`, 10 lancements chacun, caches `/tmp/vigie-spike-cef` chauds
sauf le tout premier lancement. Mesure = spawn → `VIGIE_SPIKE_READY` (premier chargement de la page locale), pas le premier pixel visible.

| `--tabs` | médiane | min | max |
|---|---|---|---|
| 1 | **161 ms** | 150 ms | 174 ms |
| 10 | **232 ms** | 230 ms | 258 ms |

Le reviewer relance : `bash tools/spike-moteur/measure.sh startup --runs 3 --timeout 60 -- /tmp/cefrun/spike-cef --tabs 1` (attendu ordre de 150-180 ms).
Avec 10 vues, `VIGIE_SPIKE_READY` sort à la **première** page chargée : les 9 autres ne sont pas attendues.

## Critère 3 — mémoire

Commande : `measure.sh memory --settle 5 --timeout 60 -- /tmp/cefrun/spike-cef --tabs N` (somme des RSS de la session, 5 s après READY).

| `--tabs` | RSS total |
|---|---|
| 1 | **783 Mo** |
| 10 | **1750 Mo** |

Limite : le RSS additionne les pages partagées entre processus (`libcef.so` mappé par chaque processus Chromium), donc il **surestime**
la mémoire réellement consommée. Pas de PSS mesuré (non fait). Écart 1 → 10 vues : +967 Mo, soit ~107 Mo par vue supplémentaire.

## Critère 1 — réseau, page locale, sans URL

Commande : `measure.sh network --duration 60 --timeout 90 -- /tmp/cefrun/spike-cef --tabs 1` (`strace -f`, `connect/sendto/sendmsg/sendmmsg`, caches vidés avant).
**CEF émet du trafic réseau tout seul**, alors que la page est un `data:` :

```
network_calls=27
network_dest=127.0.0.11:53                 (DNS du conteneur)
network_dest=142.251.154.119:443
network_dest=142.251.209.110:443
network_dest=142.251.39.174:80
network_dest=192.178.204.138:443
network_dest=213.44.21.206:443
network_dest=34.104.35.123:80
network_dest=[2001:4860:4860::8888]:443
```

Les noms de domaine n'ont pas pu être relevés : les requêtes DNS passent par des sockets UDP déjà connectées (`send` sans adresse), limite connue de
`measure.sh`, et un `strace -e trace=send,sendmsg` n'a pas montré les noms. **Je ne les attribue pas** : `2001:4860:4860::8888` est une adresse Google Public DNS
(connaissance générale, non vérifiée ici) ; le reste est non identifié. Les `connect` observés à la seconde capture viennent d'un seul identifiant de thread/processus
(`-f` trace les threads) ; le processus exécuté de `--type=utility` (`network.mojom.NetworkService`) a un autre PID : le lien est **probable, non prouvé**.

**Seconde capture, avec switches.** #14 n'a pas établi de noms de switches (« non vérifié », `docs/knowledge/LOG.md`, Q3). J'ai donc pris des noms
connus de Chromium et vérifié seulement qu'ils sont des chaînes présentes dans `libcef.so` (`grep -c -a -F -- <nom> libcef.so` ≥ 1 pour chacun) : ce n'est **pas** une preuve de leur effet.
`VIGIE_SPIKE_SWITCHES=disable-background-networking,disable-component-update,disable-sync,no-pings,disable-domain-reliability,disable-breakpad,metrics-recording-only,disable-default-apps,no-first-run`
(présence de `--disable-background-networking` dans la ligne de commande du processus navigateur confirmée via `/proc/<pid>/cmdline`) :

```
network_calls=17
network_dest=127.0.0.11:53
network_dest=142.251.150.119:443
network_dest=142.251.209.110:443
network_dest=142.251.39.174:80
network_dest=34.104.35.123:80
network_dest=[2001:4860:4860::8888]:443
```

**Résultat : ces switches réduisent (27 → 17 appels, 8 → 6 destinations) mais ne suppriment pas le trafic.** Il reste des connexions que je n'ai pas
su attribuer. Pour l'ADR (#20) : « zéro requête au démarrage » n'est **pas** acquis avec CEF 156 ; il faut une story dédiée (journaux `--log-net-log`
ou `--enable-logging=stderr --v=1` pour nommer les destinations, sur le source Chromium 156). Les connexions peuvent aussi être de simples tentatives
bloquées (`connect … = -1 ENETUNREACH` vu sur l'IPv6), le conteneur ayant un accès Internet partiel.

## Critère 4 — plusieurs vues dans une fenêtre

**Oui, avec une condition.** Capture : `DISPLAY=:99 import -window root shot.png` (ImageMagick 7.1.1-43, `xwd` absent), après 6 s, `--tabs 2` : un panneau de 150 px à gauche
(fond gris du panneau ; la couleur `0xFF336699` demandée par `set_background_color` n'est **pas** appliquée : non élucidé) et **deux vues web** côte à côte,
chacune affichant « vigie spike » (`spike/cef/captures/multiview-2tabs-panel.png` sur `spike/moteur-cef`).

Condition établie par l'essai : avec le style par défaut (Chrome), le deuxième `BrowserView` est refusé :
`ERROR:cef/libcef/browser/views/browser_view_impl.cc:324] Cannot add multiple Chrome style BrowserViews`. Il faut le style **Alloy** pour la fenêtre
(`WindowDelegate::window_runtime_style`) **et** pour chaque vue (`BrowserViewDelegate::browser_runtime_style`), ce que fait le prototype. La doc C de
`cef_runtime_style_t` (`cef-dll-sys` bindings l. 17569) dit qu'une fenêtre Alloy n'héberge que des vues Alloy, et qu'une fenêtre Chrome n'en admet qu'une seule en style Chrome. Sans flex, les vues gardent leur taille préférée (100×100) : il faut `set_flex_for_view` et
`cross_axis_alignment = STRETCH`. Testé avec 2 vues (visuel) et 10 vues (démarrage, mémoire) ; pas de capture à 10 vues.

## Critère 5 — processus de rendu tué (`kill -9`)

`--tabs 1`, ~6 s après le lancement, `kill -9` du processus enfant de `--type=zygote` identifié par essai (les rendus gardent la ligne de commande du zygote ;
le choix s'est confirmé par le callback). Sortie du prototype :

```
VIGIE_SPIKE_RENDER_TERMINATED status=TerminationStatus(TS_PROCESS_WAS_KILLED) code=9 msg=9
```

**L'hôte survit** (`ps` : processus navigateur toujours `Ssl` 3 s après). Le callback est
`RequestHandler::on_render_process_terminated` (`ImplRequestHandler`, branché via `Client::request_handler`). La vue est devenue **blanche** (capture Xvfb
après le kill) : aucune page d'erreur ni rechargement automatique ; c'est à l'application de recharger. Un seul cas testé (1 vue, rendu tué) ; pas testé : GPU, `network service`,
plusieurs vues partageant un rendu.

## Non vérifié

- Fonctionnement avec bac à sable activé ; chiffres de démarrage et de mémoire valables seulement sans bac à sable.
- Noms de domaine contactés ; effet réel de chaque switch ; processus à l'origine des connexions.
- `cargo deny` sur le projet (repris de l'architecte, non relancé).
- Autre machine que ce conteneur WSL2 ; Wayland (CEF Views sous X11 seulement ici).
- Couleur de fond du panneau ; comportement avec 10 vues à l'écran.
