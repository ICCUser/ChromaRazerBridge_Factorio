# Checklist de validation Linux/OpenRazer

Pour Ibalek, des que du temps/materiel est disponible. Objectif : lever les
3 inconnues listees dans le README (section "Limites connues") et corriger
ce qui casse -- pas besoin de tout faire d'un coup, chaque etape est
independante et peut etre testee/corrigee separement.

## 0. Avant de toucher au bridge

- `lsusb` liste bien le clavier/souris/tapis Razer.
- Un outil comme [Polychromatic](https://polychromatic.app/) ou une commande
  OpenRazer manuelle arrive a changer une couleur sur chaque peripherique.

Si cette etape echoue, le probleme est cote OpenRazer/pilote, pas cote
bridge -- inutile d'aller plus loin avant que ce soit resolu.

## 1. Test isole (`python3 diagnose.py`)

Lance `diagnose.py` (fonctionne hors Factorio). Pour chaque etape affichee,
verifie que le bon peripherique/couleur/effet apparait reellement :

| Etape testee | Question a se poser |
|---|---|
| `static` clavier/souris | Couleur correcte, pas de clignotement parasite ? |
| `custom_mousepad` / fallback `static` tapis | `chroma_client_linux.py` n'implemente pas `custom_mousepad` -- verifie que le fallback `static` sur `mousepad` fonctionne quand meme |
| `custom_keyboard` (grille complete) | **Point le plus a risque** : verifie que chaque touche allumee correspond bien a la bonne position physique, pas juste "le clavier s'allume". Si la grille est decalee/deformee, voir point 3 plus bas |
| `breathing` (rgb1 + rgb2) | La couleur oscille bien entre les deux teintes demandees, pas une seule ou une couleur intermediaire fixe -- voir point 2 |
| `rainbow_color` (`static_all` en boucle) | Cycle de teinte complet, pas de a-coups |

## 2. Signature de `breath_dual()`

`chroma_client_linux.py:breathing()` appelle
`d.fx.breath_dual(rgb1[0], rgb1[1], rgb1[2], rgb2[0], rgb2[1], rgb2[2])`
(6 parametres, 2 couleurs RGB completes) -- reconstruit par deduction, jamais
confirme. Si le test de l'etape 1 montre une couleur fausse/un plantage :
inspecter `pylib/openrazer/client/fx.py` du paquet `openrazer` installe
localement (`python3 -c "import openrazer.client.fx as m; import inspect; print(inspect.getsource(m.FX.breath_dual))"`)
pour confirmer l'ordre exact des parametres, corriger si besoin.

## 3. Mapping appareil OpenRazer

`_DEVICE_TYPE_MAP` (`chroma_client_linux.py`) suppose `mousepad` ET
`chromalink` -> `mousemat` cote OpenRazer (OpenRazer n'a pas de categorie
"chromalink" separee). A l'etape 1, si le tapis de souris ne reagit pas :
`python3 -c "from openrazer.client import DeviceManager; [print(d.name, d.type) for d in DeviceManager().devices]"`
pour voir le `device.type` reel renvoye par ton materiel, comparer a la table.

## 4. Dimensions de la matrice avancee (`custom_keyboard`)

`adv.rows`/`adv.cols` (matrice `fx.advanced` d'OpenRazer) sont tronques a la
plus petite dimension entre la grille du bridge (6x22) et celle reellement
rapportee par le clavier. Si l'etape 1 montre un decalage touche par touche
(pas juste "rien ne s'allume") : meme demarche que `calibrate.py` cote
Windows -- lancer `python3 calibrate.py`, suivre les instructions, corriger
`grid_overrides.json` en consequence pour TON clavier (ne pas committer tes
propres valeurs de calibration -- elles sont propres a un modele de
clavier precis, `grid_overrides.json` doit rester `{}` dans le depot).

## 5. Test en conditions reelles

Une fois les points ci-dessus corriges/valides : charger une partie
Factorio avec le mod actif, lancer `python3 main.py`, jouer normalement
quelques minutes (recherche en cours, degats, un train qui passe pres du
joueur) et verifier que le clavier/souris/tapis reagit comme attendu.

## Une fois tout valide

Retirer l'avertissement "NON TESTE" du README (section "Installation
(Linux)") et mettre a jour la section "Limites connues" pour refleter ce qui
a ete confirme vs ce qui reste incertain.
