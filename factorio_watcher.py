"""
Surveille les fichiers ecrits par le mod Factorio "chroma-bridge" dans le
dossier script-output/ du profil Factorio actif (emplacement different
selon l'OS et le mode d'installation, voir default_script_output_dir) :

  chroma_status.json          -> etat partage (recherche, evolution),
                                  identique pour toute l'equipe
  chroma_player_status.json   -> etat individuel (vie, pollution locale,
                                  alertes), ecrit par Factorio UNIQUEMENT
                                  dans le sous-dossier prive du joueur local
                                  (voir find_player_output_dir)
  chroma_train_proximity.json -> alerte "train_nearby" seule, ecrite bien
                                  plus souvent que le reste du statut (voir
                                  TRAIN_SCAN_INTERVAL_TICKS cote mod) pour
                                  reagir vite -- alerte de securite
  chroma_events.jsonl         -> une ligne JSON par evenement discret
                                  PARTAGE (recherche, base attaquee, fusee,
                                  train a quai -- concernent toute l'equipe)
  chroma_player_events.jsonl  -> une ligne JSON par evenement discret PRIVE
                                  a ce joueur (ex: craft manuel), meme
                                  sous-dossier que chroma_player_status.json
"""

import json
import os
import sys
from pathlib import Path

# Candidats Linux, dans l'ordre de preference : installation native, puis
# Steam via Flatpak (le jeu ecrit dans ~/.factorio *a l'interieur* du
# sandbox, ce qui correspond a ce dossier cote hote).
_LINUX_CANDIDATES = (
    Path.home() / ".factorio",
    Path.home() / ".var/app/com.valvesoftware.Steam/.factorio",
)


def default_script_output_dir() -> Path:
    if sys.platform.startswith("linux"):
        for base in _LINUX_CANDIDATES:
            if base.is_dir():
                return base / "script-output"
        return _LINUX_CANDIDATES[0] / "script-output"
    appdata = os.environ.get("APPDATA", "")
    return Path(appdata) / "Factorio" / "script-output"


def find_player_output_dir(script_output_dir: Path) -> Path:
    """Sous-dossier prive du joueur local (ex: script-output/3/), cree par
    Factorio quand le mod ecrit un fichier avec un player_index cible (voir
    util.lua cote mod). Un seul joueur humain joue depuis cette machine,
    donc un seul sous-dossier numerique existe jamais ici -- pas besoin de
    connaitre son nom/index a l'avance. Si aucun sous-dossier n'existe
    encore (mod pas encore lance, ou pas encore mis a jour), on retombe sur
    script_output_dir lui-meme."""
    if not script_output_dir.is_dir():
        return script_output_dir
    candidates = [p for p in script_output_dir.iterdir() if p.is_dir() and p.name.isdigit()]
    if not candidates:
        return script_output_dir
    if len(candidates) == 1:
        return candidates[0]
    # Ne devrait pas arriver sur une machine de joueur (chacun n'a que son
    # propre sous-dossier prive) ; on prend le plus recemment modifie.
    return max(candidates, key=lambda p: p.stat().st_mtime)


def _read_last_json_line(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        # Le fichier peut contenir plusieurs lignes JSON si write_file a ete
        # appele plusieurs fois sans que le jeu ait tourne entre-temps. On
        # ne garde que la derniere ligne non vide.
        lines = path.read_text(encoding="utf-8").splitlines()
        for line in reversed(lines):
            if line.strip():
                return json.loads(line)
    except (json.JSONDecodeError, OSError):
        pass
    return {}


class _JsonlTail:
    """Suit la position de lecture d'un fichier .jsonl en croissance
    (ecriture "append" cote mod), sans jamais relire ce qui a deja ete
    renvoye. Partagee par le canal d'evenements partage et le canal prive
    par joueur (meme mecanique, chemin different)."""

    def __init__(self):
        self._offset = None  # None = pas encore vu ce fichier (voir poll())

    def poll(self, path: Path) -> list[dict]:
        if not path.exists():
            return []
        try:
            size = path.stat().st_size
        except OSError:
            return []

        if self._offset is None:
            # Premiere fois qu'on voit ce fichier : demarre a sa fin plutot
            # qu'a 0, sinon un bridge redemarre EN COURS de partie rejouerait
            # en rafale tout l'historique de la session (flash clavier pour
            # un train arrive il y a une heure, etc.). Le mod vide deja ce
            # fichier en debut de session (voir session_events_reset /
            # EVENTS_RESET_INTERVAL_TICKS cote control.lua).
            self._offset = size
            return []

        if size < self._offset:
            # Le fichier a retreci depuis la derniere lecture : le mod l'a
            # vide (purge de debut de session ou periodique) pendant que ce
            # watcher tournait deja. Repartir de 0 plutot que de rester
            # bloque sur un offset qui n'existe plus dans le fichier actuel.
            self._offset = 0

        events = []
        try:
            with open(path, "r", encoding="utf-8") as f:
                f.seek(self._offset)
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            events.append(json.loads(line))
                        except json.JSONDecodeError:
                            continue
                self._offset = f.tell()
        except OSError:
            pass
        return events


class FactorioWatcher:
    def __init__(self, script_output_dir: Path = None):
        self.dir = script_output_dir or default_script_output_dir()
        self.status_path = self.dir / "chroma_status.json"
        self.events_path = self.dir / "chroma_events.jsonl"
        self._shared_events = _JsonlTail()
        self._player_events = _JsonlTail()

    def _player_paths(self):
        # Recalcule a chaque appel (pas fige a l'init) : le sous-dossier
        # prive du joueur (voir find_player_output_dir) est cree par
        # Factorio de maniere paresseuse, seulement apres le premier ecrit
        # cible -- si le bridge demarre avant, il faut quand meme detecter
        # le sous-dossier des qu'il apparait plutot que de rester bloque sur
        # le dossier partage pour toute la session (meme principe que
        # MappingStore._overrides_path cote mapping_loader.py).
        player_dir = find_player_output_dir(self.dir)
        return (
            player_dir / "chroma_player_status.json",
            player_dir / "chroma_train_proximity.json",
            player_dir / "chroma_player_events.jsonl",
        )

    def read_status(self) -> dict:
        """Fusionne l'etat partage (recherche, evolution -- propriete de la
        force) et l'etat individuel (vie, pollution, alertes -- propre a ce
        joueur) en un seul dict, comme avant le passage a la config par
        joueur : le reste de main.py n'a besoin d'aucun changement."""
        player_status_path, train_proximity_path, _ = self._player_paths()
        status = _read_last_json_line(self.status_path)
        status.update(_read_last_json_line(player_status_path))
        # Ecrit a part et bien plus souvent (voir chroma_train_proximity.json
        # plus haut) : ecrase la valeur de train_nearby deja presente dans
        # alerts_by_type avec une plus fraiche, sans attendre le prochain
        # cycle (~1s) du statut general.
        train_proximity = _read_last_json_line(train_proximity_path)
        if "train_nearby" in train_proximity:
            status.setdefault("alerts_by_type", {})["train_nearby"] = train_proximity["train_nearby"]
        return status

    def poll_new_events(self) -> list[dict]:
        """Retourne les evenements ajoutes depuis le dernier appel, canal
        partage (toute l'equipe) et canal prive de ce joueur confondus."""
        _, _, player_events_path = self._player_paths()
        return self._shared_events.poll(self.events_path) + self._player_events.poll(player_events_path)
