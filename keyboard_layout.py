"""
Positions physiques (ligne, colonne) sur la grille virtuelle Chroma 6x22,
exposees par nom de touche plutot que par coordonnees brutes.

Le but : pouvoir ecrire un mapping ("F5" -> rouge, ou zone "movement" -> vert)
qui reste correct que le clavier soit AZERTY (BlackWidow V4 FR) ou QWERTY,
sans avoir a recalculer les colonnes a la main a chaque fois.

Plutot que de retaper des tuples (ligne, colonne) a la main, ce fichier
recopie telles quelles les constantes RZKEY officielles du SDK Chroma de
Razer (RzChromaSDKTypes.h) et calcule la position a partir de leur valeur
hexadecimale (encodage 0xRRCC = ligne RR, colonne CC). Une seule source de
verite, directement comparable au header Razer si besoin de re-verifier.

Colonne 0 = touches macro M1-M5 (rangees 1-5) sur les claviers qui en ont ;
confirme par calibrate.py sur un BlackWidow V4 avant de trouver cette source
officielle. Si un clavier Razer montre malgre tout un ecart, grid_overrides.json
reste le mecanisme de correction par utilisateur (voir calibrate.py).
"""

import json
from pathlib import Path

from keyboard_grid import ROWS, COLS

OVERRIDES_PATH = Path(__file__).parent / "grid_overrides.json"

# --- Constantes RZKEY (RzChromaSDKTypes.h), recopiees telles quelles ---
# Nom -> valeur hexadecimale officielle. Ne PAS retaper des (ligne, colonne)
# a la main ailleurs : tout se deduit de ces valeurs via _rzkey_to_rowcol().
_RZKEY = {
    "ESC": 0x0001,
    "F1": 0x0003, "F2": 0x0004, "F3": 0x0005, "F4": 0x0006,
    "F5": 0x0007, "F6": 0x0008, "F7": 0x0009, "F8": 0x000A,
    "F9": 0x000B, "F10": 0x000C, "F11": 0x000D, "F12": 0x000E,

    "1": 0x0102, "2": 0x0103, "3": 0x0104, "4": 0x0105, "5": 0x0106,
    "6": 0x0107, "7": 0x0108, "8": 0x0109, "9": 0x010A, "0": 0x010B,

    "A": 0x0302, "B": 0x0407, "C": 0x0405, "D": 0x0304, "E": 0x0204,
    "F": 0x0305, "G": 0x0306, "H": 0x0307, "I": 0x0209, "J": 0x0308,
    "K": 0x0309, "L": 0x030A, "M": 0x0409, "N": 0x0408, "O": 0x020A,
    "P": 0x020B, "Q": 0x0202, "R": 0x0205, "S": 0x0303, "T": 0x0206,
    "U": 0x0208, "V": 0x0406, "W": 0x0203, "X": 0x0404, "Y": 0x0207,
    "Z": 0x0403,

    "NUMLOCK": 0x0112,
    "NUM0": 0x0513, "NUM1": 0x0412, "NUM2": 0x0413, "NUM3": 0x0414,
    "NUM4": 0x0312, "NUM5": 0x0313, "NUM6": 0x0314,
    "NUM7": 0x0212, "NUM8": 0x0213, "NUM9": 0x0214,
    "NUM_DIVIDE": 0x0113, "NUM_MULTIPLY": 0x0114, "NUM_SUBTRACT": 0x0115,
    "NUM_ADD": 0x0215, "NUM_ENTER": 0x0415, "NUM_DOT": 0x0514,

    "PRINTSCREEN": 0x000F, "SCROLLLOCK": 0x0010, "PAUSE": 0x0011,
    "INSERT": 0x010F, "HOME": 0x0110, "PAGEUP": 0x0111,
    "DELETE": 0x020F, "END": 0x0210, "PAGEDOWN": 0x0211,
    "UP": 0x0410, "LEFT": 0x050F, "DOWN": 0x0510, "RIGHT": 0x0511,

    "TAB": 0x0201, "CAPSLOCK": 0x0301, "BACKSPACE": 0x010E, "ENTER": 0x030E,

    "LEFT_CTRL": 0x0501, "LEFT_WIN": 0x0502, "LEFT_ALT": 0x0503,
    "SPACE": 0x0507, "RIGHT_ALT": 0x050B, "FN": 0x050C, "RIGHT_CTRL": 0x050E,
    "LEFT_SHIFT": 0x0401, "RIGHT_SHIFT": 0x040E,

    "BACKTICK": 0x0101, "MINUS": 0x010C, "EQUALS": 0x010D,
    "OPEN_BRACKET": 0x020C, "CLOSE_BRACKET": 0x020D, "BACKSLASH": 0x020E,
    "SEMICOLON": 0x030B, "QUOTE": 0x030C,
    "COMMA": 0x040A, "PERIOD": 0x040B, "SLASH": 0x040C,

    "MACRO1": 0x0100, "MACRO2": 0x0200, "MACRO3": 0x0300,
    "MACRO4": 0x0400, "MACRO5": 0x0500,
}


def _rzkey_to_rowcol(value: int):
    """Decode l'encodage officiel Razer 0xRRCC -> (ligne, colonne)."""
    return (value >> 8) & 0xFF, value & 0xFF


# --- Grille de reference, layout QWERTY (US) ---
# (ligne, colonne) pour chaque touche, calculees a partir de _RZKEY ci-dessus.
QWERTY_US = {label: _rzkey_to_rowcol(value) for label, value in _RZKEY.items()}

# --- Layout AZERTY (France) ---
# On part de QWERTY_US et on ne change QUE les touches dont le libelle
# imprime differe sur un clavier francais (la position physique reste la
# meme, seul le nom sous lequel on la designe change) :
#   rangee du haut : A et Z prennent la place de Q et W
#   rangee du milieu : Q prend la place de A, M prend la place de ;
#   rangee du bas : W prend la place de Z, , ; et : remplacent M , . /
# (approx, ponctuation FR non geree finement ici)


def _build_azerty():
    azerty = dict(QWERTY_US)
    # libelles QWERTY qui n'ont plus de sens une fois renommes en AZERTY
    # (ex: "A" en QWERTY == "Q" en AZERTY, la position physique de Q)
    for old_label in ("Q", "W", "A", "Z", "SEMICOLON", "M", "COMMA", "PERIOD", "SLASH"):
        azerty.pop(old_label, None)
    azerty.update({
        "A": QWERTY_US["Q"], "Z": QWERTY_US["W"],
        "Q": QWERTY_US["A"], "M": QWERTY_US["SEMICOLON"],
        "W": QWERTY_US["Z"],
        "COMMA": QWERTY_US["M"], "SEMICOLON": QWERTY_US["COMMA"],
        "COLON": QWERTY_US["PERIOD"], "EXCLAIM": QWERTY_US["SLASH"],
    })
    return azerty


AZERTY_FR = _build_azerty()

LAYOUTS = {
    "qwerty_us": QWERTY_US,
    "azerty_fr": AZERTY_FR,
}

# Zones semantiques : independantes du layout, resolues au moment de l'appel.
ZONE_DEFINITIONS = {
    "function_row": ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
    "digits_row": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "arrows": ["UP", "LEFT", "DOWN", "RIGHT"],
    "wasd": {"qwerty_us": ["W", "A", "S", "D"], "azerty_fr": ["Z", "Q", "S", "D"]},
}
ZONE_DEFINITIONS["movement"] = ZONE_DEFINITIONS["wasd"]


def _load_overrides() -> dict:
    if not OVERRIDES_PATH.exists():
        return {}
    try:
        return json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def key_to_rowcol(label: str, layout: str = "azerty_fr"):
    """Resout un nom de touche (ex: 'F5', 'A', 'SPACE') en (ligne, colonne).
    Les corrections de grid_overrides.json (ecrites par calibrate.py) sont
    prioritaires sur la grille de reference."""
    overrides = _load_overrides()
    key = f"{layout}:{label.upper()}"
    if key in overrides:
        return tuple(overrides[key])

    table = LAYOUTS.get(layout, AZERTY_FR)
    label = label.upper()
    if label not in table:
        raise KeyError(
            f"Touche '{label}' inconnue pour le layout '{layout}'. "
            f"Touches disponibles : {sorted(table.keys())}"
        )
    return table[label]


def resolve_keys(names, layout: str = "azerty_fr"):
    """Convertit une liste de noms de touches et/ou de zones semantiques
    (ex: ['F1', 'F2'] ou ['zone:movement']) en liste de (ligne, colonne).
    Le prefixe 'zone:' est optionnel (accepte 'movement' comme 'zone:movement')."""
    positions = []
    for name in names:
        zone_key = name.lower()
        if zone_key.startswith("zone:"):
            zone_key = zone_key[5:]
        if zone_key in ZONE_DEFINITIONS:
            zone = ZONE_DEFINITIONS[zone_key]
            zone_labels = zone[layout] if isinstance(zone, dict) else zone
            for label in zone_labels:
                positions.append(key_to_rowcol(label, layout))
        else:
            positions.append(key_to_rowcol(name.upper(), layout))
    return positions


def available_keys(layout: str = "azerty_fr"):
    """Liste triee des noms de touches valides pour ce layout (pour affichage/doc)."""
    return sorted(LAYOUTS.get(layout, AZERTY_FR).keys())


def available_zones():
    return sorted(ZONE_DEFINITIONS.keys())
