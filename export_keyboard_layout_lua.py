"""
Genere keyboard_layout_data.lua (cote mod) a partir de keyboard_layout.py, pour
que le clavier virtuel de l'interface en jeu (gui.lua) utilise EXACTEMENT la
meme correspondance touche -> (ligne, colonne) que le bridge Python, sans
dupliquer ~100 entrees a la main des deux cotes.

A relancer si keyboard_layout.py change (nouvelles touches, correction de
grille...) :
    python export_keyboard_layout_lua.py
"""

from pathlib import Path

from keyboard_layout import QWERTY_US, AZERTY_FR, ZONE_DEFINITIONS

MOD_DIR = Path(__file__).parent / "mod"
OUTPUT_PATH = MOD_DIR / "keyboard_layout_data.lua"


def lua_table_for(layout: dict) -> str:
    # Cle entre crochets ["LABEL"] partout : certains libelles ("0".."9") ne
    # sont pas des identifiants Lua valides et casseraient une syntaxe
    # LABEL = {...} nue.
    lines = []
    for label in sorted(layout.keys()):
        row, col = layout[label]
        lines.append(f'    ["{label}"] = {{{row}, {col}}},')
    return "\n".join(lines)


def lua_zone_for(zone_value) -> str:
    if isinstance(zone_value, dict):
        parts = []
        for layout_name, labels in zone_value.items():
            items = ", ".join(f'"{label}"' for label in labels)
            parts.append(f'    {layout_name} = {{{items}}},')
        return "{\n" + "\n".join(parts) + "\n  }"
    items = ", ".join(f'"{label}"' for label in zone_value)
    return f"{{{items}}}"


def main():
    zones_lines = []
    for name, value in ZONE_DEFINITIONS.items():
        zones_lines.append(f"  {name} = {lua_zone_for(value)},")

    content = f'''-- Fichier GENERE automatiquement par export_keyboard_layout_lua.py
-- depuis keyboard_layout.py (source de verite cote Python). Ne pas editer a
-- la main : relancer le script Python si la grille clavier change.

return {{
  qwerty_us = {{
{lua_table_for(QWERTY_US)}
  }},
  azerty_fr = {{
{lua_table_for(AZERTY_FR)}
  }},
  zones = {{
{chr(10).join(zones_lines)}
  }},
}}
'''
    OUTPUT_PATH.write_text(content, encoding="utf-8")
    print(f"Ecrit : {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
