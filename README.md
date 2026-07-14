# Factorio Chroma Bridge

Pilote ton clavier / souris / tapis de souris Razer Chroma en fonction de l'etat
de ta partie Factorio (recherche en cours, attaques de biters, trains, fusees,
alertes logistiques...), avec une configuration entierement personnalisable
**depuis le jeu** (raccourci `CONTROL+SHIFT+C`).

Deux morceaux, obligatoirement separes (voir "Pourquoi deux morceaux ?" plus bas) :
- Un **mod Factorio** (Lua) qui ecrit l'etat de la partie dans des fichiers JSON.
- Un **bridge Python** qui lit ces fichiers et pilote le SDK REST Chroma de Razer Synapse.

---

## Installation (Windows)

### Pre-requis

- [Razer Synapse](https://www.razer.com/synapse) installe et lance, connecte a un compte Razer.
- Dans Synapse : **Chroma Apps** (parfois appele "Chroma Connect") doit etre active dans les parametres.
- [Python 3.10+](https://www.python.org/downloads/) installe (coche "Add python.exe to PATH" a l'installation).
- Factorio 2.0+ (le mod utilise des events/defines specifiques a la 2.0).

### Etapes

1. **Copier le mod** : copie le dossier `mod/` de ce repo dans `%APPDATA%\Factorio\mods\`
   en le renommant `chroma-bridge_1.1.0` (le nom du dossier de developpement
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
