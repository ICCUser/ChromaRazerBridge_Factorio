"""
Client minimal pour le Chroma SDK REST (Razer Synapse).
Doc officielle : https://assets.razerzone.com/dev_portal/REST/html/index.html

IMPORTANT : les couleurs Chroma sont encodees en BGR (pas RGB !) dans un entier
32 bits : 0x00BBGGRR.
"""

import colorsys
import math
import threading
import time
import requests

CHROMA_BASE_URL = "http://localhost:54235/razer/chromasdk"


def rgb_to_chroma(r: int, g: int, b: int) -> int:
    """Convertit un triplet RGB (0-255) vers le format BGR attendu par le SDK."""
    return (b << 16) | (g << 8) | r


def breathing_color(t: float, rgb1, rgb2, cycle_seconds: float = 3.0):
    """Couleur RGB interpolee a l'instant t, oscillant en douceur entre rgb2
    (creux) et rgb1 (pic), comme CHROMA_BREATHING. Utilise pour les cellules
    du clavier qui doivent respirer alors qu'une grille CHROMA_CUSTOM est
    deja active ailleurs sur le clavier -- impossible de superposer un
    second effet natif sur le meme peripherique, donc on calcule l'effet a
    la main plutot que de laisser ces touches en noir."""
    phase = (t % cycle_seconds) / cycle_seconds
    blend = (1 - math.cos(2 * math.pi * phase)) / 2
    return tuple(round(c2 + (c1 - c2) * blend) for c1, c2 in zip(rgb1, rgb2))


def rainbow_color(t: float, cycle_seconds: float = 2.0):
    """Couleur RGB (0-255) a l'instant t sur un cycle de teinte complet toutes
    les cycle_seconds secondes. Remplace CHROMA_SPECTRUMCYCLING : cet effet
    est deprecie cote SDK Razer et ne s'applique plus de maniere fiable sur
    les versions recentes de Synapse -- ceci ne repose que sur CHROMA_STATIC,
    deja verifie fonctionnel."""
    hue = (t % cycle_seconds) / cycle_seconds
    r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return (round(r * 255), round(g * 255), round(b * 255))


class ChromaClient:
    """
    Gere le cycle de vie d'une session Chroma :
      - creation de session (POST /razer/chromasdk)
      - heartbeat periodique (obligatoire, sinon Synapse ferme la session)
      - envoi d'effets sur clavier / souris / tapis de souris
      - fermeture propre (DELETE)
    """

    def __init__(self, app_name="Factorio Chroma Bridge", author="ICCUser", contact="none@example.com"):
        self.app_name = app_name
        self.author = author
        self.contact = contact
        self.session_uri = None
        self._heartbeat_thread = None
        self._stop_event = threading.Event()

    def connect(self):
        payload = {
            "title": self.app_name,
            "description": "Bridge RGB pilote par l'etat de la partie Factorio",
            "author": {"name": self.author, "contact": self.contact},
            "device_supported": ["keyboard", "mouse", "mousepad", "headset", "chromalink"],
            "category": "application",
        }
        resp = requests.post(CHROMA_BASE_URL, json=payload, timeout=5)
        resp.raise_for_status()
        data = resp.json()

        if "uri" not in data:
            raise RuntimeError(
                "Le Chroma SDK n'a pas renvoye d'URI de session.\n"
                f"Reponse brute recue : {data}\n\n"
                "Causes les plus frequentes :\n"
                "  1) 'Chroma Apps' (ou 'Chroma Connect') n'est pas active dans "
                "les parametres de Razer Synapse.\n"
                "  2) Le service Windows 'Razer Chroma SDK Service' n'est pas "
                "demarre (services.msc).\n"
                "  3) Synapse n'est pas lance / tu n'es pas connecte a un compte "
                "Razer dans Synapse."
            )

        self.session_uri = data["uri"]
        self._start_heartbeat()
        return self.session_uri

    def _start_heartbeat(self):
        def loop():
            while not self._stop_event.is_set():
                try:
                    requests.put(f"{self.session_uri}/heartbeat", timeout=5)
                except requests.RequestException:
                    pass
                self._stop_event.wait(5)  # heartbeat toutes les 5s (limite Razer ~15s)

        self._heartbeat_thread = threading.Thread(target=loop, daemon=True)
        self._heartbeat_thread.start()

    def _put(self, device: str, body: dict):
        if not self.session_uri:
            return
        try:
            resp = requests.put(f"{self.session_uri}/{device}", json=body, timeout=5)
            if not resp.ok:
                print(f"[chroma_client] {device} <- {body.get('effect')} : HTTP {resp.status_code} : {resp.text}")
        except requests.RequestException as exc:
            print(f"[chroma_client] {device} <- {body.get('effect')} : erreur reseau : {exc}")

    # --- Effets bas niveau (par periphérique) ---

    def static(self, device: str, rgb):
        color = rgb_to_chroma(*rgb)
        self._put(device, {"effect": "CHROMA_STATIC", "param": {"color": color}})

    def breathing(self, device: str, rgb1, rgb2=None):
        color1 = rgb_to_chroma(*rgb1)
        body = {"effect": "CHROMA_BREATHING", "param": {"color1": color1}}
        if rgb2:
            body["param"]["color2"] = rgb_to_chroma(*rgb2)
        self._put(device, body)

    def custom_mousepad(self, rgb):
        """CHROMA_CUSTOM pour le tapis : tableau de 20 LEDs (doc officielle),
        toutes a la meme couleur. A tester si CHROMA_STATIC/CHROMA_BREATHING
        n'ont aucun effet visible sur ce modele de tapis (CHROMA_BREATHING
        n'est d'ailleurs pas documente comme supporte pour ce peripherique)."""
        color = rgb_to_chroma(*rgb)
        self._put("mousepad", {"effect": "CHROMA_CUSTOM", "param": [color] * 20})

    def custom_keyboard(self, grid):
        """
        grid : liste de 6 lignes x 22 colonnes d'entiers BGR (deja convertis).
        Grille "virtuelle" universelle du SDK Chroma pour clavier.
        """
        self._put("keyboard", {"effect": "CHROMA_CUSTOM", "param": grid})

    # --- Effets haut niveau (tous les peripheriques a la fois) ---

    def static_all(self, rgb):
        for device in ("keyboard", "mouse", "mousepad", "headset", "chromalink"):
            self.static(device, rgb)

    def breathing_all(self, rgb1, rgb2=None):
        for device in ("keyboard", "mouse", "mousepad", "headset", "chromalink"):
            self.breathing(device, rgb1, rgb2)

    def blink_all(self, rgb, times=8, interval=0.2):
        """Clignotement bloquant (utilise pour les alertes ponctuelles)."""
        off = (0, 0, 0)
        for _ in range(times):
            self.static_all(rgb)
            time.sleep(interval)
            self.static_all(off)
            time.sleep(interval)

    def close(self):
        self._stop_event.set()
        if self.session_uri:
            try:
                requests.delete(self.session_uri, timeout=5)
            except requests.RequestException:
                pass
