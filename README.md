# Factorio Chroma Bridge

Pilote ton clavier / souris / tapis de souris Razer Chroma en fonction de l'etat
de ta partie Factorio (recherche en cours, attaques de biters, trains, fusees,
alertes logistiques...), avec une configuration entierement personnalisable
**depuis le jeu** (raccourci `CONTROL+SHIFT+C`). Fonctionne en solo comme en
multi-joueur : chaque joueur connecte a sa propre configuration et son propre
etat (vie, pollution, alertes), independants des autres.

Le mod seul n'allume rien : il te faut **aussi** un petit programme a lancer a
cote du jeu (le "bridge"). Voir [Comment ca marche ?](#comment-ca-marche-) si
tu veux savoir pourquoi ; sinon, va directement a
[Installation](#installation-joueurs).

## Fonctionnalites

- **Etat du jeu -> RGB** : recherche en cours (barre de progression sur les
  touches F1-F12), vie du joueur (barre sur 1-9/0), attaques de biters, trains
  a quai/sans chemin/en panne de carburant, fusees lancees, mort du joueur,
  alertes logistiques (stockage plein, manque de robots/materiaux/reparations),
  sous-alimentation electrique.
- **Alerte de securite** : un train en mouvement a proximite immediate du
  joueur declenche une alerte distincte, pensee pour reagir plus vite que le
  reste du statut (verifie ~10x/seconde).
- **Alertes personnalisees** : associe une couleur au message d'un
  haut-parleur programmable (texte libre de ton choix, ex: alerte de base
  attaquee par un mod tiers) sans toucher au code.
- **Multi-joueur** : la configuration et l'etat de chaque joueur connecte sont
  prives -- deux personnes sur le meme serveur peuvent avoir des reglages
  Chroma completement differents sans se marcher dessus.
- **Explorateur d'evenements** (en jeu) : liste tous les events/alertes
  disponibles, avec pour chacun quels mods l'ont declenche et combien de fois
  cette partie -- utile pour cabler un mod tiers sans lire son code source.
- **Tout se configure en jeu** (`CONTROL+SHIFT+C`, ou la commande `/chroma-bridge`
  si ce raccourci est en conflit avec un autre mod) : clavier virtuel AZERTY/QWERTY
  pour choisir une touche/zone precise, barre de recherche et barre de vie
  personnalisables, couleur par defaut (fixe ou reactive a l'evolution des
  biters / la pollution / le jour-nuit).
- **Export / import de ta config** : depuis l'interface, copie toute ta
  configuration en JSON (un clic) pour la sauvegarder ou la partager, et
  colle-en une pour la restaurer -- pratique pour ne pas tout re-cliquer a la
  main apres une reinstallation, ou pour recopier la config d'un coequipier.

---

## Installation (joueurs)

Deux choses a installer, dans cet ordre : **le mod** (dans Factorio) puis
**le bridge** (le programme qui pilote vraiment les lumieres). Compte 10-15
minutes la premiere fois.

### Windows

**1. Prerequis**

- [Razer Synapse](https://www.razer.com/synapse) installe, lance, connecte a
  ton compte Razer. Dans ses parametres, active **Chroma Apps** (parfois
  appele "Chroma Connect").
- [Python](https://www.python.org/downloads/) installe -- **pendant
  l'installation, coche bien la case "Add python.exe to PATH"**. C'est
  l'etape qui coince le plus souvent : si tu l'as oubliee, desinstalle et
  relance l'installateur en la cochant cette fois.

**2. Installer le mod dans Factorio** -- choisis l'une des deux methodes :

- *Depuis le jeu (le plus simple)* : menu principal de Factorio -> **Mods**
  -> **Parcourir en ligne** (ou l'icone de recherche selon la version),
  cherche "Chroma Bridge", clique **Installer**.
- *En telechargeant le zip* : va sur la
  [page du mod](https://mods.factorio.com/mod/chroma-bridge), bouton
  telecharger, puis depose le fichier `.zip` obtenu (sans le decompresser)
  dans `%APPDATA%\Factorio\mods\`. Relance Factorio et verifie dans la liste
  des mods que "Chroma Bridge" apparait et est coche/actif.

**3. Telecharger le bridge** -- c'est un programme separe, disponible sur
GitHub (pas sur le Mod Portal, qui ne distribue que le mod Factorio) :
[telecharge le zip ici](https://github.com/ICCUser/ChromaRazerBridge_Factorio/archive/refs/heads/master.zip),
puis decompresse-le ou tu veux (ton dossier Documents par exemple).

**4. Installer une dependance Python** -- ouvre un terminal dans le dossier
que tu viens de decompresser (clic droit dans le dossier -> *Ouvrir dans le
terminal*, ou Maj+clic droit -> *Ouvrir la fenetre PowerShell ici* selon ta
version de Windows), puis :
```
pip install requests
```

**5. Lancer Factorio**, charger/demarrer une partie avec le mod actif.

**6. Lancer le bridge** (dans le meme terminal qu'a l'etape 4) :
```
python main.py
```
Tu dois voir "Session ouverte : http://localhost:.../chromasdk" puis une
animation sur le clavier. **Laisse cette fenetre ouverte** tant que tu veux
les effets lumineux -- ferme-la (ou Ctrl+C) quand tu as fini de jouer.

**7. Configurer** : en jeu, `CONTROL+SHIFT+C` ouvre l'interface pour choisir
quel evenement allume quelle touche, quelle couleur, etc. Les changements
sont pris en compte immediatement, pas besoin de relancer le bridge.

*(Optionnel mais recommande la premiere fois)* Si les touches qui s'allument
ne correspondent pas a celles annoncees, lance `python calibrate.py` --
Synapse doit tourner, Factorio n'est pas necessaire pour cette etape.

### Linux

Fonctionne via [OpenRazer](https://openrazer.github.io/). Memes grandes
etapes que sous Windows :

1. Installe [OpenRazer](https://openrazer.github.io/#download) (paquet de ta
   distro, ou PPA/AUR) et verifie que le service `openrazer-daemon` tourne.
   Ajoute ton utilisateur au groupe `plugdev`
   (`sudo usermod -aG plugdev $USER`), puis **deconnecte-toi/reconnecte-toi**.
2. Installe le mod : depuis le jeu (Mods -> Parcourir en ligne, cherche
   "Chroma Bridge") ou en deposant le zip telecharge depuis la
   [page du mod](https://mods.factorio.com/mod/chroma-bridge) dans
   `~/.factorio/mods/`.
3. Telecharge le bridge :
   [zip GitHub](https://github.com/ICCUser/ChromaRazerBridge_Factorio/archive/refs/heads/master.zip),
   decompresse-le ou tu veux, puis dans un terminal a cet endroit :
   ```
   pip install openrazer requests
   ```
4. Lance Factorio avec le mod actif, puis `python3 main.py`. Le client
   Linux affiche au demarrage la liste des peripheriques detectes -- si
   elle est vide, le probleme est cote detection OpenRazer, pas cote bridge.
5. Meme configuration en jeu que sous Windows (`CONTROL+SHIFT+C`).

---

## En cas de souci

- `python diagnose.py` : teste chaque appareil (clavier/souris/tapis) et
  l'effet arc-en-ciel independamment de Factorio, pour isoler un probleme
  materiel/Synapse d'un probleme de configuration.
- `python print_mapping_table.py` : affiche un tableau recapitulatif de tous
  les events/alertes disponibles et de leur configuration actuelle.
- Si "le tapis de souris ne repond a rien" : sur certaines configs Synapse, le
  tapis est en fait enregistre sous la categorie `chromalink` plutot que
  `mousepad`. Essaie `chromalink` comme peripherique pour l'evenement concerne
  dans l'interface en jeu.
- Si `CONTROL+SHIFT+C` ne fait rien : un autre mod actif peut utiliser le
  meme raccourci (Factorio ne previent pas toujours clairement en cas de
  conflit), ou le raccourci a pu etre change/desactive par erreur. Verifie
  et reassigne-le dans **Parametres > Commandes**, cherche "Chroma Bridge" ;
  en attendant, la commande console `/chroma-bridge` (touche `` ` `` ou `~`
  pour ouvrir la console) ouvre la meme interface, sans dependre d'aucun
  raccourci clavier.
- Rien ne s'allume du tout : verifie dans l'ordre -- (1) le bridge
  (`python main.py`) tourne bien et affiche "Session ouverte", (2) Synapse
  (Windows) ou `openrazer-daemon` (Linux) tourne, (3) le mod est bien coche
  actif dans la liste des mods Factorio.
- Autre probleme : ouvre un ticket sur
  [GitHub](https://github.com/ICCUser/ChromaRazerBridge_Factorio/issues) ou
  laisse un commentaire sur la
  [page du mod](https://mods.factorio.com/mod/chroma-bridge).

---

## Développement

Cette section s'adresse a quelqu'un qui veut modifier le mod ou le bridge,
pas juste jouer avec. Si tu es juste joueur, tu peux t'arreter ici.

### Comment ca marche ?

Un mod Factorio tourne dans le bac a sable Lua du jeu : pas d'acces reseau, pas
d'acces au systeme de fichiers en dehors de `script-output/`, donc aucun moyen
d'appeler le SDK REST de Razer Synapse ou la bibliotheque Python OpenRazer
directement depuis `control.lua`. Le mod se contente donc d'ecrire l'etat de
la partie dans des fichiers JSON ; un script Python externe (qui, lui, a acces
au reseau/systeme) les relit et pilote le RGB. C'est aussi ce qui permet au
bridge de tourner independamment du jeu (redemarrage sans recharger la partie,
diagnostic hors Factorio via `diagnose.py`, etc.)

Sous Windows, `chroma_client.py` parle a **Razer Synapse** via son SDK REST
(`http://localhost:54235/razer/chromasdk`). Synapse n'existe pas sur Linux.
Le pilote RGB de reference pour le materiel Razer sous Linux est
[OpenRazer](https://openrazer.github.io/) (daemon systeme + bibliotheque
Python `openrazer`), avec une API completement differente. `chroma_client_linux.py`
expose exactement la meme interface que `chroma_client.py`
(`connect()`, `static()`, `breathing()`, `custom_keyboard()`, `static_all()`,
`breathing_all()`, `close()`) -- `main.py` choisit automatiquement le bon
client selon `sys.platform`, aucune autre difference entre les deux OS.

### Mettre en place un environnement de dev

1. Clone le depot (`git clone https://github.com/ICCUser/ChromaRazerBridge_Factorio.git`)
   plutot que de telecharger le zip.
2. `pip install requests` (+ `openrazer` sur Linux).
3. Symlink le dossier `mod/` du repo vers l'emplacement des mods Factorio,
   pour tester tes changements sans avoir a recopier des fichiers a chaque
   fois :
   - Windows : `mklink /J %APPDATA%\Factorio\mods\chroma-bridge_dev C:\chemin\vers\le\repo\mod`
   - Linux : `ln -s /chemin/vers/le/repo/mod ~/.factorio/mods/chroma-bridge_dev`

### Workflow de dev cote mod

`mod/` (ce repo) est **la seule source de verite** pour le mod Lua. Ne modifie
jamais directement les fichiers dans le dossier de mods de Factorio sans
symlink (voir ci-dessus) : ce dossier n'est pas versionne, et un changement
fait uniquement la-bas est perdu au prochain `git pull` (c'est exactement ce
qui s'est passe pendant le developpement de la 1.4.1, d'ou la reconciliation
manuelle qui a suivi). Pour publier une nouvelle version :

1. Modifie `mod/`, incremente `version` dans `mod/info.json`.
2. `python package_mod.py` -> produit `dist/chroma-bridge_<version>.zip`.
3. Upload ce zip comme nouvelle release sur le [Mod Portal](https://mods.factorio.com/)
   -- le portail ne remplace pas le contenu d'une version deja publiee,
   chaque changement (meme juste une image ou un texte de description) exige
   un nouveau numero.

### Linux : details non confirmes

Le client Linux (`chroma_client_linux.py`) fonctionne, mais trois details
d'implementation precis n'ont pas ete verifies un par un -- utile a savoir
si un bug tres specifique remonte un jour sur l'un de ces points :

- La correspondance appareil OpenRazer <-> nos noms (`mousepad`/`chromalink`
  -> `mousemat` cote OpenRazer) est faite par `device.type`.
- La signature exacte de `breath_dual()` (couleur de respiration a deux
  teintes) est reconstruite par deduction (6 parametres, 2 couleurs RGB
  completes) a partir d'une source partiellement illisible.
- `custom_keyboard()` suppose que la matrice avancee OpenRazer (`fx.advanced`)
  utilise la meme disposition de grille que le SDK Windows ; les dimensions
  reelles (`adv.rows`/`adv.cols`) peuvent differer et sont tronquees au plus
  petit des deux cote code.

Voir [TESTING_LINUX.md](TESTING_LINUX.md) pour une methode pour isoler un
souci sur l'un de ces points precis.

### Structure du projet

| Fichier | Role |
|---|---|
| `main.py` | Boucle principale : lit l'etat du jeu, pilote le Chroma SDK (choisit le client Windows/Linux) |
| `chroma_client.py` | Client REST pour le SDK Chroma Windows/Synapse |
| `chroma_client_linux.py` | Client OpenRazer pour Linux (meme interface) |
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

Cote mod (`mod/`, source de verite) :
`control.lua` (evenements de jeu), `gui.lua` (interface CONTROL+SHIFT+C), `event_explorer.lua`
(explorateur d'evenements), `keyboard_layout_data.lua` (grille clavier, genere),
`util.lua` (ecriture JSON partagee), `data.lua` (raccourci clavier), `info.json`.

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
