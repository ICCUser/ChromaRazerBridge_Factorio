# Factorio Chroma Bridge

Pilote ton clavier / souris / tapis de souris Razer Chroma en fonction de l'etat
de ta partie Factorio (recherche en cours, attaques de biters, trains, fusees,
alertes logistiques...), avec une configuration entierement personnalisable
**depuis le jeu** (raccourci `CONTROL+SHIFT+C`). Fonctionne en solo comme en
multi-joueur : chaque joueur connecte a sa propre configuration et son propre
etat (vie, pollution, alertes), independants des autres.

Deux morceaux, obligatoirement separes (voir "Pourquoi deux morceaux ?" plus bas) :
- Un **mod Factorio** (Lua) qui ecrit l'etat de la partie dans des fichiers JSON.
- Un **bridge Python** qui lit ces fichiers et pilote soit le SDK REST Chroma de
  Razer Synapse (Windows), soit OpenRazer (Linux).

## Fonctionnalites

- **Etat du jeu -> RGB** : recherche en cours (barre de progression sur les
  touches F1-F12), vie du joueur (barre sur 1-9/0), attaques de biters, trains
  a quai/sans chemin/en panne de carburant, fusees lancees, mort du joueur,
  alertes logistiques (stockage plein, manque de robots/materiaux/reparations),
  sous-alimentation electrique.
- **Alerte de securite** : un train en mouvement a proximite immediate du
  joueur declenche une alerte distincte, pensee pour reagir plus vite que le reste du
  statut (verifie ~10x/seconde).
- **Alertes personnalisees** : associe une couleur au message d'un
  haut-parleur programmable (texte libre de ton choix, ex: alerte de base
  attaquee par un mod tiers) sans toucher au code.
- **Multi-joueur** : la configuration et l'etat de chaque joueur connecte sont
  prives (stockes dans un sous-dossier separe par joueur) -- deux personnes
  sur le meme serveur peuvent avoir des reglages Chroma completement
  differents sans se marcher dessus.
- **Explorateur d'evenements** (en jeu) : liste tous les events/alertes
  disponibles, avec pour chacun quels mods l'ont declenche et combien de fois
  cette partie -- utile pour cabler un mod tiers sans lire son code source.
- **Tout se configure en jeu** (`CONTROL+SHIFT+C`) : clavier virtuel AZERTY/QWERTY
  pour choisir une touche/zone precise, barre de recherche et barre de vie
  personnalisables, couleur par defaut (fixe ou reactive a l'evolution des
  biters / la pollution / le jour-nuit).

---

## Pourquoi deux morceaux ?

Un mod Factorio tourne dans le bac a sable Lua du jeu : pas d'acces reseau, pas
d'acces au systeme de fichiers en dehors de `script-output/`, donc aucun moyen
d'appeler le SDK REST de Razer Synapse ou la bibliotheque Python OpenRazer
directement depuis `control.lua`. Le mod se contente donc d'ecrire l'etat de
la partie dans des fichiers JSON ; un script Python externe (qui, lui, a acces
au reseau/systeme) les relit et pilote le RGB. C'est aussi ce qui permet au
bridge de tourner independamment du jeu (redemarrage sans recharger la partie,
diagnostic hors Factorio via `diagnose.py`, etc.).

---

## Installation (Windows)

### Pre-requis

- [Razer Synapse](https://www.razer.com/synapse) installe et lance, connecte a un compte Razer.
- Dans Synapse : **Chroma Apps** (parfois appele "Chroma Connect") doit etre active dans les parametres.
- [Python 3.10+](https://www.python.org/downloads/) installe (coche "Add python.exe to PATH" a l'installation).
- Factorio 2.0+ (le mod utilise des events/defines specifiques a la 2.0).

### Etapes

1. **Copier le mod** : copie le dossier `mod/` de ce repo dans `%APPDATA%\Factorio\mods\`
   en le renommant `chroma-bridge_1.5.2` (le nom du dossier de developpement
   n'a pas d'importance pour Factorio, seul `info.json` compte, mais ca evite
   toute confusion). Verifie qu'il apparait et est active dans le launcher
   Factorio (liste des mods).
   Si tu comptes modifier le mod toi-meme, un lien symbolique (`mklink /J`
   sous Windows, `ln -s` sous Linux) entre ce dossier et `mod/` t'evite d'avoir
   a recopier a chaque changement.

2. **Installer les dependances Python** (dans un terminal, a la racine de ce dossier) :
   ```
   pip install requests
   ```

3. **Lancer Factorio**, charger/demarrer une partie avec le mod actif.

4. **Verifier l'alignement des touches** (recommande a la premiere installation,
   et si tu changes de clavier) : Synapse doit tourner, Factorio n'est pas
   necessaire pour cette etape.
   ```
   python calibrate.py
   ```
   Suis les instructions affichees (voir aussi les commentaires en tete de
   `calibrate.py`). Les corrections sont sauvegardees dans `grid_overrides.json`.

5. **Lancer le bridge**, en jeu ou avec Factorio ouvert a cote :
   ```
   python main.py
   ```
   Tu dois voir "Session ouverte : http://localhost:.../chromasdk" puis
   l'animation de demarrage sur le clavier.

6. **Configurer** : en jeu, `CONTROL+SHIFT+C` ouvre l'interface de configuration
   (quel event/alerte allume quelle touche/zone, quelle couleur, clignotement...).
   Les changements sont pris en compte par `main.py` sans le relancer.

### En cas de souci

- `python diagnose.py` : teste chaque appareil (clavier/souris/tapis) et l'effet
  arc-en-ciel independamment de Factorio, pour isoler un probleme materiel/Synapse
  d'un probleme de configuration.
- `python print_mapping_table.py` : affiche un tableau recapitulatif de tous les
  events/alertes disponibles et de leur configuration actuelle.
- Si "le tapis de souris ne repond a rien" : sur certaines configs Synapse, le
  tapis est en fait enregistre sous la categorie `chromalink` plutot que
  `mousepad`. Essaie `chromalink` comme peripherique pour l'evenement concerne
  dans l'interface en jeu.

---

## Installation (Linux)

**Implemente mais NON TESTE** (aucune machine Linux + materiel Razer
disponible pendant le developpement). Le code a ete ecrit contre l'API
officielle documentee/exemples du depot
[openrazer/openrazer](https://github.com/openrazer/openrazer), mais n'a
jamais tourne en conditions reelles -- attends-toi a devoir corriger deux ou
trois choses au premier essai, avec la meme methode que cote Windows
(isoler le probleme avec un test direct plutot que deviner).

### Pourquoi un client different de Windows

Sous Windows, `chroma_client.py` parle a **Razer Synapse** via son SDK REST
(`http://localhost:54235/razer/chromasdk`). Synapse n'existe pas sur Linux.
Le pilote RGB de reference pour le materiel Razer sous Linux est
[OpenRazer](https://openrazer.github.io/) (daemon systeme + bibliotheque
Python `openrazer`), avec une API completement differente. `chroma_client_linux.py`
expose exactement la meme interface que `chroma_client.py`
(`connect()`, `static()`, `breathing()`, `custom_keyboard()`, `static_all()`,
`breathing_all()`, `close()`) -- `main.py` choisit automatiquement le bon
client selon `sys.platform`, aucune autre difference entre les deux OS.

### Pre-requis

- [OpenRazer](https://openrazer.github.io/#download) installe (paquet de ta
  distro, ou PPA/AUR officiel) et le service `openrazer-daemon` lance.
- Ton utilisateur ajoute au groupe `plugdev` (`sudo usermod -aG plugdev $USER`),
  puis **deconnecte-toi/reconnecte-toi** (le groupe n'est pris en compte qu'a
  la prochaine session).
- `pip install openrazer requests`
- Factorio 2.0+ avec le mod copie dans `~/.factorio/mods/` (ou l'equivalent
  selon ton installation -- Steam vs binaire officiel changent l'emplacement).
  Le bridge detecte automatiquement `~/.factorio/` (installation native) puis
  `~/.var/app/com.valvesoftware.Steam/.factorio/` (Steam via Flatpak) ; si ton
  installation utilise un autre emplacement, indique-le explicitement en
  passant `script_output_dir` a `FactorioWatcher` (voir `factorio_watcher.py`).

### Etapes

1. Verifie d'abord qu'OpenRazer voit bien ton materiel, **avant** de toucher
   au bridge : `lsusb` doit lister tes peripheriques Razer, et un outil comme
   [Polychromatic](https://polychromatic.app/) ou une commande manuelle
   (voir doc OpenRazer) doit pouvoir changer une couleur. Si OpenRazer seul
   n'arrive pas a piloter le materiel, le bridge Python ne pourra pas non
   plus -- c'est le meme principe que verifier Synapse cote Windows avant de
   soupconner le code.
2. Lance `python3 main.py`. Le client Linux affiche au demarrage la liste des
   peripheriques detectes (`[chroma_client_linux] Peripheriques OpenRazer
   detectes : ...`) -- si cette liste est vide ou incomplete, le probleme est
   cote detection OpenRazer, pas cote bridge.
3. Le reste (configuration en jeu, calibration clavier, etc.) fonctionne
   exactement comme sur Windows -- voir la section Windows ci-dessus.

### Limites connues / a verifier en premier

- La correspondance appareil OpenRazer <-> nos noms (`mousepad`/`chromalink`
  -> `mousemat` cote OpenRazer) est faite par `device.type`, jamais verifiee
  en conditions reelles.
- La signature exacte de `breath_dual()` (couleur de respiration a deux
  teintes) est reconstruite par deduction (6 parametres, 2 couleurs RGB
  completes) a partir d'une source partiellement illisible -- a confirmer.
- `custom_keyboard()` suppose que la matrice avancee OpenRazer (`fx.advanced`)
  utilise la meme disposition de grille que le SDK Windows ; les dimensions
  reelles (`adv.rows`/`adv.cols`) peuvent differer et sont tronquees au plus
  petit des deux cote code, mais l'alignement touche par touche n'est pas
  garanti tant que non teste -- meme demarche que `calibrate.py` a prevoir.

Voir [TESTING_LINUX.md](TESTING_LINUX.md) pour une checklist detaillee de
validation sur materiel reel.

---

## Structure du projet

| Fichier | Role |
|---|---|
| `main.py` | Boucle principale : lit l'etat du jeu, pilote le Chroma SDK (choisit le client Windows/Linux) |
| `chroma_client.py` | Client REST pour le SDK Chroma Windows/Synapse |
| `chroma_client_linux.py` | Client OpenRazer pour Linux (meme interface, non teste) |
| `mapping.json` | Config par defaut (evenements/alertes -> appareil/couleur/effet) |
| `mapping_loader.py` | Charge/fusionne `mapping.json` + les overrides ecrits par le jeu |
| `keyboard_layout.py` | Correspondance touche/zone -> position sur la grille Chroma (AZERTY/QWERTY), basee sur les constantes RZKEY officielles de Razer |
| `keyboard_grid.py` | Primitives de rendu bas niveau de la grille clavier |
| `factorio_watcher.py` | Lit les fichiers ecrits par le mod (`script-output/`) |
| `calibrate.py` | Outil de calibration touche par touche |
| `diagnose.py` | Test isole des effets Chroma (hors Factorio) |
| `print_mapping_table.py` | Tableau recapitulatif events/alertes <-> configuration |
| `export_keyboard_layout_lua.py` | Regenere `keyboard_layout_data.lua` (cote mod) depuis `keyboard_layout.py` |
| `package_mod.py` | Empaquette le mod Lua en zip pret pour le mod portal Factorio |

Cote mod (`mod/`, source de verite -- a copier/symlinker dans `%APPDATA%\Factorio\mods\`) :
`control.lua` (evenements de jeu), `gui.lua` (interface CONTROL+SHIFT+C), `event_explorer.lua`
(explorateur d'evenements), `keyboard_layout_data.lua` (grille clavier, genere),
`util.lua` (ecriture JSON partagee), `data.lua` (raccourci clavier), `info.json`.

### Workflow de dev cote mod

`mod/` (ce repo) est **la seule source de verite** pour le mod Lua. Le
symlink (`mklink /J` Windows, `ln -s` Linux) vers `%APPDATA%\Factorio\mods\`
ou `~/.factorio/mods/` sert a tester en jeu -- ne modifie jamais directement
les fichiers dans le dossier de mods de Factorio sans symlink : ce dossier
n'est pas versionne, et un changement fait uniquement la-bas est perdu au
prochain `git pull` (c'est exactement ce qui s'est passe pendant le
developpement de la 1.4.1, d'ou la reconciliation manuelle qui a suivi).
Pour publier une nouvelle version :

1. Modifie `mod/`, incremente `version` dans `mod/info.json`.
2. `python package_mod.py` -> produit `dist/chroma-bridge_<version>.zip`.
3. Upload ce zip comme nouvelle release sur le [Mod Portal](https://mods.factorio.com/)
   -- le portail ne remplace pas le contenu d'une version deja publiee,
   chaque changement (meme juste une image) exige un nouveau numero.

### Fichiers echanges (mod -> bridge)

Ecrits dans `script-output/` (voir `factorio_watcher.py` pour l'emplacement
exact selon l'OS) :

| Fichier | Portee | Contenu |
|---|---|---|
| `chroma_status.json` | Partage (toute l'equipe) | Recherche en cours, evolution des biters |
| `chroma_player_status.json` | Prive (sous-dossier par joueur) | Vie, pollution locale, alertes, heure du jour |
| `chroma_train_proximity.json` | Prive (sous-dossier par joueur) | Alerte train a proximite, rafraichie ~10x/s |
| `chroma_mapping.json` | Prive (sous-dossier par joueur) | Config editee en jeu (CONTROL+SHIFT+C) |
| `chroma_events.jsonl` | Partage (toute l'equipe) | Evenements ponctuels concernant l'equipe entiere (recherche, base attaquee, fusee, train a quai, mort d'un joueur -- volontairement une alerte d'equipe), vide en debut de session puis toutes les ~10 min |
| `chroma_player_events.jsonl` | Prive (sous-dossier par joueur) | Evenements ponctuels propres a ce joueur (craft manuel), meme rythme de purge que ci-dessus |

"Prive" = ecrit par Factorio uniquement dans le sous-dossier numerique
(`script-output/<player_index>/`) de la machine du joueur concerne -- invisible
pour les autres joueurs connectes, y compris en multi-joueur.

---

## Credits

- **ICCUser** -- bridge Windows/Razer Synapse, mod Factorio, architecture initiale.
- **Ibalek** -- client Linux/OpenRazer, support multi-joueur, alertes
  personnalisees, alerte de proximite de train, explorateur d'evenements par mod.
