"""
Outil de calibration : allume les touches une par une pour verifier que la
grille virtuelle (keyboard_layout.py) correspond bien a ton clavier physique.

Lance-le PENDANT que Synapse tourne (pas besoin que Factorio soit ouvert) :

    python calibrate.py                  # verifie le layout azerty_fr (defaut)
    python calibrate.py qwerty_us        # verifie un autre layout
    python calibrate.py azerty_fr F1 F2 W A S D   # ne teste que ces touches

Pour chaque touche testee :
  - la LED correspondante s'allume en blanc, le reste du clavier est eteint
  - si c'est la bonne touche : appuie sur Entree
  - si c'est une AUTRE touche qui s'est allumee : tape le nom de la touche qui
    s'est reellement allumee (ex: "F6") et la correction sera enregistree
  - "s" + Entree pour passer une touche sans rien enregistrer
  - "q" + Entree pour arreter la calibration

Les corrections sont sauvegardees dans grid_overrides.json et prennent
automatiquement le pas sur la grille par defaut (voir keyboard_layout.py).
"""

import json
import sys
import time

if sys.platform.startswith("linux"):
    from chroma_client_linux import ChromaClient
else:
    from chroma_client import ChromaClient
from keyboard_grid import single_key_grid
from keyboard_layout import LAYOUTS, OVERRIDES_PATH, key_to_rowcol

TEST_COLOR = (255, 255, 255)


def load_overrides() -> dict:
    if not OVERRIDES_PATH.exists():
        return {}
    try:
        return json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_overrides(overrides: dict):
    OVERRIDES_PATH.write_text(json.dumps(overrides, indent=2, ensure_ascii=False), encoding="utf-8")


def main():
    args = sys.argv[1:]
    layout = "azerty_fr"
    if args and args[0] in LAYOUTS:
        layout = args.pop(0)
    labels = args if args else sorted(LAYOUTS[layout].keys())

    print(f"Calibration du layout '{layout}' ({len(labels)} touches a tester).")
    print("Synapse doit etre lance. Ctrl+C a tout moment pour quitter sans sauvegarder ce pas.\n")

    client = ChromaClient(app_name="Chroma Bridge - Calibration")
    client.connect()

    overrides = load_overrides()
    changed = False

    try:
        for label in labels:
            row, col = key_to_rowcol(label, layout)
            # applique un eventuel override deja enregistre pour l'affichage courant
            override_key = f"{layout}:{label}"
            if override_key in overrides:
                row, col = overrides[override_key]

            grid = single_key_grid(row, col, TEST_COLOR)
            client.custom_keyboard(grid)

            answer = input(f"Touche visee  : {label:<12} (ligne {row}, col {col}) allumee, "
                           f"Entree=OK / nom reel / s=skip / q=quit -> ").strip().lower()

            if answer == "q":
                break
            if answer == "s":
                continue
            if answer == "":
                # confirme : la position par defaut/deja corrigee est la bonne
                overrides[f"{layout}:{label}"] = [row, col]
                changed = True
                continue

            # l'utilisateur indique que c'est une AUTRE touche qui s'est allumee :
            # on sait donc empiriquement que CETTE position (row, col) appartient
            # a la touche qu'il vient de nommer (pas a 'label').
            typed_label = answer.upper()
            if typed_label not in LAYOUTS[layout]:
                print(f"  Touche '{typed_label}' inconnue pour ce layout, correction ignoree.")
                continue

            overrides[f"{layout}:{typed_label}"] = [row, col]
            changed = True
            print(f"  Correction enregistree : {typed_label} -> ligne {row}, col {col}")

    except KeyboardInterrupt:
        print("\nCalibration interrompue.")
    finally:
        client.close()

    if changed:
        save_overrides(overrides)
        print(f"\n{len(overrides)} correction(s) au total, sauvegardees dans {OVERRIDES_PATH}")
    else:
        print("\nAucune nouvelle correction.")


if __name__ == "__main__":
    main()
