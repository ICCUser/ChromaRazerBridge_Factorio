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

Valide sur materiel reel par Ibalek depuis la 1.4.1 (clavier/souris/tapis
s'allument et reagissent correctement). Quelques details precis n'ont
neanmoins pas ete verifies un par un -- voir README.md, section "Linux :
details non confirmes" : signature exacte de breath_dual(), correspondance
mousepad/chromalink -> mousemat, alignement touche par touche de la matrice
avancee. En cas de souci sur l'un de ces points precis, meme methode que
diagnose.py cote Windows : isoler avec un test direct plutot que deviner.
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

    def __init__(self, app_name="Factorio Chroma Bridge", author="Ibalek", contact="none@example.com"):
        # author/contact : uniquement utilises comme metadonnees de session
        # par le SDK REST Windows, ignores ici (OpenRazer n'a pas ce concept).
        self.app_name = app_name
        self._manager = None
        self._devices_by_name = {}
        self._last_effect = {}  # device -> derniere commande envoyee, pour eviter de
                                 # relancer un effet deja actif (voir static()/breathing())
        self.session_uri = None  # pas de notion de session cote OpenRazer ; presente
                                  # uniquement pour l'interface commune avec chroma_client.py
                                  # (main.py/diagnose.py l'affichent apres connect())

    def connect(self):
        self._manager = DeviceManager()
        self._manager.sync_effects = False  # sinon le daemon reprend la main sur nos effets

        for device in self._manager.devices:
            device_type = getattr(device, "type", None)
            for our_name, razer_type in _DEVICE_TYPE_MAP.items():
                if device_type == razer_type and our_name not in self._devices_by_name:
                    self._devices_by_name[our_name] = device

        found = ", ".join(self._devices_by_name.keys()) or "aucun"
        self.session_uri = f"openrazer (local dbus) : {found}"
        print(f"[chroma_client_linux] Peripheriques OpenRazer detectes : {found}")
        return self._manager

    def _device(self, name):
        return self._devices_by_name.get(name)

    def static(self, device: str, rgb):
        d = self._device(device)
        if not d:
            return
        effect = ("static", tuple(rgb))
        previous = self._last_effect.get(device)
        if previous == effect:
            return
        try:
            if previous is not None and previous[0] != "static":
                # Coupe l'effet precedent (respiration ambiante, etc.) avant
                # d'envoyer le static : certains firmwares Razer enchainent
                # les effets avec un fondu interne, "none" force une coupure
                # nette plutot qu'un crossfade visible sur l'alerte.
                d.fx.none()
            d.fx.static(*rgb)
            self._last_effect[device] = effect
        except Exception as exc:
            print(f"[chroma_client_linux] {device} <- static : erreur : {exc}")

    def breathing(self, device: str, rgb1, rgb2=None):
        d = self._device(device)
        if not d:
            return
        effect = ("breathing", tuple(rgb1), tuple(rgb2) if rgb2 else None)
        if self._last_effect.get(device) == effect:
            return
        try:
            if rgb2:
                d.fx.breath_dual(rgb1[0], rgb1[1], rgb1[2], rgb2[0], rgb2[1], rgb2[2])
            else:
                d.fx.breath_single(*rgb1)
            self._last_effect[device] = effect
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
            self._last_effect.pop("keyboard", None)  # effet matrice : le prochain
                                                       # static()/breathing() doit reprendre la main
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
        # Windows -- a la fermeture du bridge (jeu ferme, Ctrl+C...), on
        # remet chaque peripherique en vert fixe plutot que de l'eteindre :
        # ca reste un etat visuel clair (le clavier n'a pas l'air en panne).
        for device in self._devices_by_name.values():
            try:
                device.fx.static(0, 255, 0)
            except Exception:
                pass
