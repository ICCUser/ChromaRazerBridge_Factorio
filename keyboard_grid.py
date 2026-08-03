"""
Grille virtuelle universelle du clavier Chroma SDK : 6 lignes x 22 colonnes.
Primitives de rendu bas niveau uniquement (grille pleine, une touche, un
groupe de touches...). La correspondance nom-de-touche -> (ligne, colonne)
et le support AZERTY/QWERTY sont geres par keyboard_layout.py.
"""

from chroma_client import rgb_to_chroma

ROWS = 6
COLS = 22


def blank_grid(fill_rgb=(0, 0, 0)):
    color = rgb_to_chroma(*fill_rgb)
    return [[color for _ in range(COLS)] for _ in range(ROWS)]


def single_key_grid(row: int, col: int, rgb, ambient_rgb=(0, 0, 0)):
    """Grille avec une seule touche allumee (utilisee par calibrate.py)."""
    grid = blank_grid(ambient_rgb)
    grid[row][col] = rgb_to_chroma(*rgb)
    return grid


def sweep_fill_grid(up_to_column: int, base_rgb, ambient_rgb=(0, 0, 0)):
    """Grille avec toutes les colonnes jusqu'a 'up_to_column' allumees (barre qui se remplit)."""
    grid = blank_grid(ambient_rgb)
    color = rgb_to_chroma(*base_rgb)
    for r in range(ROWS):
        for c in range(0, up_to_column + 1):
            grid[r][c] = color
    return grid


