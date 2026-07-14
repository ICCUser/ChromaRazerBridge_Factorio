"""
Surveille les fichiers ecrits par le mod Factorio "chroma-bridge" dans
%APPDATA%\\Factorio\\script-output\\ :

  chroma_status.json   -> ecrase a chaque tick de polling (etat continu)
  chroma_events.jsonl  -> une ligne JSON par evenement discret
"""

import json
import os
from pathlib import Path


def default_script_output_dir() -> Path:
    appdata = os.environ.get("APPDATA", "")
    return Path(appdata) / "Factorio" / "script-output"


class FactorioWatcher:
    def __init__(self, script_output_dir: Path = None):
        self.dir = script_output_dir or default_script_output_dir()
        self.status_path = self.dir / "chroma_status.json"
        self.events_path = self.dir / "chroma_events.jsonl"
        self._events_offset = 0

    def read_status(self) -> dict:
        if not self.status_path.exists():
            return {}
        try:
            # Le fichier peut contenir plusieurs lignes JSON si write_file a
            # ete appele plusieurs fois sans que le jeu ait tourne entre-temps.
            # On ne garde que la derniere ligne non vide.
            lines = self.status_path.read_text(encoding="utf-8").splitlines()
            for line in reversed(lines):
                if line.strip():
                    return json.loads(line)
        except (json.JSONDecodeError, OSError):
            pass
        return {}

    def poll_new_events(self) -> list[dict]:
        """Retourne les evenements ajoutes depuis le dernier appel."""
        if not self.events_path.exists():
            return []
        events = []
        try:
            with open(self.events_path, "r", encoding="utf-8") as f:
                f.seek(self._events_offset)
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            events.append(json.loads(line))
                        except json.JSONDecodeError:
                            continue
                self._events_offset = f.tell()
        except OSError:
            pass
        return events
