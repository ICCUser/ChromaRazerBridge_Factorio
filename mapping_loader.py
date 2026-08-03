"""
Chargement de la config mapping (couleurs/effets/touches par evenement
Factorio), avec rechargement a chaud depuis DEUX sources :

  1. mapping.json (a cote de ce script)          -> base editee a la main
  2. chroma_mapping.json, dans le sous-dossier    -> overrides ecrits par
     prive de CE joueur (voir find_player_output_dir) : l'interface en jeu
     (CONTROL+SHIFT+C) est desormais individuelle par joueur, Factorio
     n'ecrit ce fichier que sur la machine du joueur concerne.

Les entrees 'events'/'alerts' de la source (2) remplacent celles de (1) une
par une (pas de remplacement en bloc) : ce que tu edites en jeu prend le pas,
le reste continue de venir de mapping.json.
"""

import json
from pathlib import Path

from factorio_watcher import default_script_output_dir, find_player_output_dir

DEFAULT_MAPPING_PATH = Path(__file__).parent / "mapping.json"

DEFAULTS = {
    "layout": "azerty_fr",
    "poll_seconds": 0.2,
    "ambient": {"devices": ["mouse", "chromalink"], "color1": [230, 100, 20], "color2": [20, 10, 0], "thresholds": []},
    "keyboard_idle": {"color1": [230, 100, 20], "color2": [20, 10, 0], "ambient_reactive": False},
    "research_bar": {
        "enabled": True,
        "keys": ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
        "color_bar": [0, 255, 60],
        "color_empty": [20, 20, 20],
    },
    "health_bar": {
        "enabled": True,
        "keys": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        "color_bar": [0, 255, 0],
        "color_empty": [40, 0, 0],
    },
    "alerts": {},
    "events": {},
}


def _merge_defaults(data: dict) -> dict:
    merged = json.loads(json.dumps(DEFAULTS))  # deep copy
    for key, value in data.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key].update(value)
        else:
            merged[key] = value
    return merged


def _read_json(path: Path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        print(f"[{path.name}] erreur de lecture, ignore : {exc}")
        return None


class MappingStore:
    """Recharge automatiquement mapping.json et les overrides en jeu quand
    l'un des deux fichiers change sur disque."""

    def __init__(self, path: Path = DEFAULT_MAPPING_PATH, script_output_dir: Path = None):
        self.path = path
        self.script_output_dir = script_output_dir or default_script_output_dir()
        self._mtime = None
        self._overrides_mtime = None
        self.data = DEFAULTS
        self.reload(force=True)

    def _mtime_of(self, path: Path):
        try:
            return path.stat().st_mtime
        except OSError:
            return None

    def _overrides_path(self) -> Path:
        # Recalcule a chaque appel (pas fige a l'import) : le sous-dossier
        # prive du joueur (voir find_player_output_dir) est cree par
        # Factorio de maniere paresseuse, seulement apres le premier ecrit
        # cible -- s'il n'existe pas encore au demarrage du bridge, il faut
        # quand meme le detecter des qu'il apparait.
        return find_player_output_dir(self.script_output_dir) / "chroma_mapping.json"

    def reload(self, force: bool = False) -> bool:
        """Recharge si l'un des deux fichiers a change depuis le dernier
        chargement. Retourne True si le contenu a effectivement change."""
        overrides_path = self._overrides_path()
        mtime = self._mtime_of(self.path)
        overrides_mtime = self._mtime_of(overrides_path)

        if not force and mtime == self._mtime and overrides_mtime == self._overrides_mtime:
            return False

        base = _read_json(self.path) or {}
        merged = _merge_defaults(base)

        overrides = _read_json(overrides_path)
        if overrides:
            if "layout" in overrides:
                merged["layout"] = overrides["layout"]
            for bar in ("research_bar", "health_bar", "keyboard_idle", "ambient"):
                if bar in overrides:
                    merged[bar].update(overrides[bar])
            for section in ("events", "alerts"):
                merged.setdefault(section, {}).update(overrides.get(section, {}))

        self.data = merged
        self._mtime = mtime
        self._overrides_mtime = overrides_mtime
        return True

    def __getitem__(self, key):
        return self.data[key]

    def get(self, key, default=None):
        return self.data.get(key, default)
