"""
Client Chroma pour Linux, via OpenRazer (daemon systeme + bibliotheque
Python "openrazer") -- PAS le SDK REST de Synapse, qui n'existe que sur
Windows. Voir README.md pour l'architecture (pourquoi deux clients separes).

Meme interface publique que chroma_client.ChromaClient (connect / static /
breathing / custom_keyboard / static_all / breathing_all / close), pour que
main.py n'ait besoin d'aucun changement au-dela du choix du bon module a
l'import (voir main.py, selection automatique via sys.platform).

Prerequis :
  pip install openrazer
  openrazer-daemon installe et lance (paquet de la distro, ou PPA/AUR
  officiel OpenRazer), utilisateur ajoute au groupe 'plugdev', puis
  se reconnecter (logout/login) pour que le groupe soit pris en compte.

ATTENTION : code non teste (aucune machine Linux + materiel Razer disponible
pendant le developpement). API verifiee contre les exemples officiels du
depot openrazer/openrazer (examples/advanced_effect.py,
examples/custom_zones.py, pylib/openrazer/client/fx.py) mais jamais executee
en conditions reelles. A tester avec les memes precautions que diagnose.py
cote Windows : commencer par un test isole (static rouge sur chaque
peripherique) avant de faire confiance a l'integration complete.
"""

from openrazer.client import DeviceManager

# Correspondance entre nos noms de peripherique (utilises dans mapping.json,
# identiques sur Windows et Linux) et le device_type expose par OpenRazer.
# OpenRazer n'a pas de categorie "chromalink" : les tapis de souris sont tous
# types "mousemat" cote OpenRazer.
_DEVICE_TYPE_MAP = {
    "keyboard": "keyboard",
    "mouse": "mouse",
    "mousepad": "mousemat",
    "chromalink": "mousemat",
    "headset": "headset",
}


def _chroma_to_rgb(color: int):
    """Decode un entier BGR (format chroma_client.rgb_to_chroma) en (r, g, b)."""
    r = color & 0xFF
    g = (color >> 8) & 0xFF
    b = (color >> 16) & 0xFF
    return (r, g, b)


class ChromaClient:
    """Meme interface que chroma_client.ChromaClient, implementee au-dessus
    d'OpenRazer plutot que du SDK REST Synapse (Windows uniquement)."""

    def __init__(self, app_name="Factorio Chroma Bridge", author="ICCUser", contact="none@example.com"):
        # author/contact : uniquement utilises comme metadonnees de session
        # par le SDK REST Windows, ignores ici (OpenRazer n'a pas ce concept).
        self.app_name = app_name
        self._manager = None
        self._devices_by_name = {}

    def connect(self):
        self._manager = DeviceManager()
        self._manager.sync_effects = False  # sinon le daemon reprend la main sur nos effets

        for device in self._manager.devices:
            device_type = getattr(device, "type", None)
            for our_name, razer_type in _DEVICE_TYPE_MAP.items():
                if device_type == razer_type and our_name not in self._devices_by_name:
                    self._devices_by_name[our_name] = device

        found = ", ".join(self._devices_by_name.keys()) or "aucun"
        print(f"[chroma_client_linux] Peripheriques OpenRazer detectes : {found}")
        return self._manager

    def _device(self, name):
        return self._devices_by_name.get(name)

    def static(self, device: str, rgb):
        d = self._device(device)
        if not d:
            return
        try:
            d.fx.static(*rgb)
        except Exception as exc:
            print(f"[chroma_client_linux] {device} <- static : erreur : {exc}")

    def breathing(self, device: str, rgb1, rgb2=None):
        d = self._device(device)
        if not d:
            return
        try:
            if rgb2:
                d.fx.breath_dual(rgb1[0], rgb1[1], rgb1[2], rgb2[0], rgb2[1], rgb2[2])
            else:
                d.fx.breath_single(*rgb1)
        except Exception as exc:
            print(f"[chroma_client_linux] {device} <- breathing : erreur : {exc}")

    def custom_keyboard(self, grid):
        """grid : 6 lignes x 22 colonnes d'entiers BGR (voir keyboard_grid.py).
        Convertis en (r,g,b) pour la matrice avancee OpenRazer, tronque a la
        taille reelle du clavier si plus petit que 6x22."""
        d = self._device("keyboard")
        if not d or not getattr(d.fx, "advanced", None):
            return
        try:
            adv = d.fx.advanced
            rows = min(len(grid), adv.rows)
            for row in range(rows):
                cols = min(len(grid[row]), adv.cols)
                for col in range(cols):
                    adv.matrix[row, col] = _chroma_to_rgb(grid[row][col])
            adv.draw()
        except Exception as exc:
            print(f"[chroma_client_linux] keyboard <- custom_keyboard : erreur : {exc}")

    def static_all(self, rgb):
        for device in ("keyboard", "mouse", "chromalink"):
            self.static(device, rgb)

    def breathing_all(self, rgb1, rgb2=None):
        for device in ("keyboard", "mouse", "chromalink"):
            self.breathing(device, rgb1, rgb2)

    def close(self):
        # Pas de notion de session a fermer explicitement comme le SDK REST
        # Windows -- on eteint juste chaque peripherique proprement.
        for device in self._devices_by_name.values():
            try:
                device.fx.none()
            except Exception:
                pass
