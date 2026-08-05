"""
Chroma Bridge pour Factorio.

Lance ce script pendant que Factorio tourne (avec le mod "chroma-bridge" actif).
Il lit periodiquement l'etat de la partie et pilote clavier / souris / tapis
Razer via le SDK REST Chroma de Synapse.

Fonctionne sur Windows (SDK REST Synapse, chroma_client.py) et sur Linux
(OpenRazer, chroma_client_linux.py) -- le bon client est choisi
automatiquement selon la plateforme, sans rien a changer dans ce fichier ni
dans mapping.json : les deux exposent la meme interface.

Toute la logique appareil/touche/couleur/clignotement est dans mapping.json,
rechargee a chaud -- soit editee a la main, soit ecrite par l'interface en
jeu (CONTROL+SHIFT+C dans Factorio, voir script-output/chroma_mapping.json).

Chaque evenement/alerte a un "device" ("all", "keyboard", "mouse" ou
"mousepad"). "all" est exclusif et prend la main sur tout le setup ; les
trois autres tournent independamment, et pour "keyboard" plusieurs choses
peuvent s'afficher en meme temps tant qu'elles touchent des touches
differentes (ex: barre de recherche + alerte logistique).

Prerequis (Windows) :
  pip install requests
  Synapse doit tourner et "Chroma Apps" doit etre active dans les parametres.
  Le mod chroma-bridge doit etre copie dans %APPDATA%\\Factorio\\mods\\

Prerequis (Linux) :
  pip install openrazer
  openrazer-daemon installe, lance, utilisateur dans le groupe 'plugdev'.
  Voir README.md pour le detail et les quelques details d'implementation
  non confirmes (section "Linux : details non confirmes").
"""

import signal
import sys
import time

from chroma_client import rainbow_color, breathing_color
if sys.platform.startswith("linux"):
    from chroma_client_linux import ChromaClient
else:
    from chroma_client import ChromaClient
from factorio_watcher import FactorioWatcher
from keyboard_grid import COLS, ROWS, sweep_fill_grid, blank_grid, rgb_to_chroma
from keyboard_layout import resolve_keys
from mapping_loader import MappingStore

DEVICE_HOLD_NAMES = ("mouse", "mousepad", "headset", "chromalink")
MAX_ALL_HOLD_SECONDS = 3.0  # un evenement 'all' qui se redeclenche en rafale (ex: trains
                            # frequents) ne doit pas bloquer indefiniment clavier/souris/tapis
_warned_scopes = set()


def _rgb(value, fallback=(255, 255, 255)):
    return tuple(value) if value else fallback


def effective_color(cfg: dict, now: float):
    """Couleur a afficher a cet instant precis pour ce cfg. Renvoie None si
    le clignotement est dans sa phase 'eteinte'."""
    color = _rgb(cfg.get("color"))
    if not cfg.get("blink"):
        return color
    interval = max(cfg.get("blink_interval", 0.3), 0.05)
    phase = int(now / interval) % 2
    return color if phase == 0 else None


def scope_positions(scope, layout: str):
    """Resout un 'scope' en liste de (ligne, colonne). 'scope' peut etre :
    'all'/vide (tout le clavier), 'zone:xxx', un nom de touche unique, ou une
    liste de noms de touches (groupe personnalise choisi via le clavier
    virtuel de l'interface en jeu). Une touche/zone invalide (ex: faute de
    frappe) est ignoree avec un avertissement affiche une seule fois, plutot
    que de faire planter le bridge."""
    if not scope or scope == "all":
        return [(r, c) for r in range(ROWS) for c in range(COLS)]
    names = scope if isinstance(scope, list) else [scope]
    positions = []
    for name in names:
        try:
            positions.extend(resolve_keys([name], layout))
        except KeyError as exc:
            if name not in _warned_scopes:
                print(f"[mapping] touche/zone invalide ignoree : {exc}")
                _warned_scopes.add(name)
    return positions


def play_boot_animation(client: ChromaClient, boot_color):
    """Barre de chargement classique, gauche -> droite, au demarrage du bridge."""
    print("Animation de demarrage...")
    client.static("mouse", (0, 0, 0))
    client.static("mousepad", (0, 0, 0))
    for col in range(COLS):
        grid = sweep_fill_grid(col, boot_color)
        client.custom_keyboard(grid)
        time.sleep(0.04)
    time.sleep(0.4)


def find_active_alert_for_device(status: dict, alerts_cfg: dict, device: str):
    """L'alerte la plus prioritaire actuellement active pour un appareil
    donne ('all', 'mouse' ou 'mousepad'), ou None."""
    counts = status.get("alerts_by_type", {}) or {}
    candidates = [
        (name, cfg) for name, cfg in alerts_cfg.items()
        if cfg.get("enabled", True) and counts.get(name, 0) > 0 and cfg.get("device", "all") == device
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[1].get("priority", 0), reverse=True)
    return candidates[0]


def find_active_keyboard_alerts(status: dict, alerts_cfg: dict):
    """Toutes les alertes visant le clavier, triees par priorite CROISSANTE
    (la plus prioritaire est appliquee en dernier, donc gagne en cas de
    chevauchement de touches)."""
    counts = status.get("alerts_by_type", {}) or {}
    candidates = [
        (name, cfg) for name, cfg in alerts_cfg.items()
        if cfg.get("enabled", True) and counts.get(name, 0) > 0 and cfg.get("device", "all") == "keyboard"
    ]
    candidates.sort(key=lambda item: item[1].get("priority", 0))
    return candidates


def progress_bar_cells(progress: float, keys: list, color_bar, color_empty, layout: str):
    """Jauge generique : une liste ordonnee de touches, dont une partie est
    allumee en fonction de 'progress' (0.0 a 1.0). Partagee par la barre de
    recherche et la barre de vie."""
    positions = resolve_keys(keys, layout)
    progress = max(0.0, min(1.0, progress))
    lit_count = round(progress * len(positions))

    bar_color = rgb_to_chroma(*_rgb(color_bar))
    empty_color = rgb_to_chroma(*_rgb(color_empty, (20, 20, 20)))
    return [
        (row, col, bar_color if i < lit_count else empty_color)
        for i, (row, col) in enumerate(positions)
    ]


def research_bar_cells(status: dict, cfg: dict, layout: str):
    """Renvoie la liste (ligne, colonne, couleur_bgr) de la jauge de
    recherche, ou [] si aucune recherche en cours."""
    if not cfg.get("enabled", True):
        return []
    if not (status.get("current_research") and status.get("research_progress") is not None):
        return []
    return progress_bar_cells(status["research_progress"], cfg.get("keys", []), cfg.get("color_bar"), cfg.get("color_empty"), layout)


def health_bar_cells(status: dict, cfg: dict, layout: str):
    """Renvoie la liste (ligne, colonne, couleur_bgr) de la jauge de vie du
    joueur, ou [] si aucun joueur avec un personnage n'est suivi."""
    if not cfg.get("enabled", True):
        return []
    health = status.get("player_health")
    if health is None:
        return []
    return progress_bar_cells(health, cfg.get("keys", []), cfg.get("color_bar"), cfg.get("color_empty"), layout)


def build_keyboard_grid(status: dict, mapping: MappingStore, layout: str, keyboard_flash: dict, now: float):
    """Compose en une seule grille tout ce que le clavier doit afficher ce
    tick (barre de recherche + alertes clavier + flash d'evenement ponctuel).
    Renvoie None si rien de tout ca n'est actif (l'appelant doit alors
    afficher l'effet 'idle' classique a la place)."""
    layers = []

    layers.append(research_bar_cells(status, mapping["research_bar"], layout))
    layers.append(health_bar_cells(status, mapping.get("health_bar", {}), layout))

    for _, cfg in find_active_keyboard_alerts(status, mapping.get("alerts", {})):
        color = effective_color(cfg, now)
        if color is None:
            continue
        color_int = rgb_to_chroma(*color)
        layers.append([(r, c, color_int) for r, c in scope_positions(cfg.get("scope"), layout)])

    if keyboard_flash["cfg"] and now < keyboard_flash["until"]:
        cfg = keyboard_flash["cfg"]
        color = effective_color(cfg, now)
        if color is not None:
            color_int = rgb_to_chroma(*color)
            layers.append([(r, c, color_int) for r, c in scope_positions(cfg.get("scope"), layout)])

    if not any(layers):
        return None

    color1, color2 = keyboard_idle_colors(status, mapping)
    idle_rgb = breathing_color(now, color1, color2)
    grid = blank_grid(idle_rgb)
    for layer in layers:
        for row, col, color in layer:
            grid[row][col] = color
    return grid


def compute_keyboard_idle(client: ChromaClient, status: dict, mapping: MappingStore):
    color1, color2 = keyboard_idle_colors(status, mapping)
    client.breathing("keyboard", color1, color2)


def _threshold_matches(threshold: dict, status: dict) -> bool:
    """Un seuil peut combiner plusieurs conditions (evolution/pollution/heure
    du jour) ; toutes celles presentes dans le seuil doivent etre verifiees."""
    if "min_evolution" in threshold and status.get("evolution_factor", 0.0) < threshold["min_evolution"]:
        return False
    if "min_pollution" in threshold and status.get("local_pollution", 0.0) < threshold["min_pollution"]:
        return False
    if "min_daytime" in threshold and status.get("daytime", 0.0) < threshold["min_daytime"]:
        return False
    if "max_daytime" in threshold and status.get("daytime", 0.0) > threshold["max_daytime"]:
        return False
    return True


def ambient_colors_for(cfg: dict, status: dict):
    color1 = _rgb(cfg.get("color1"))
    color2 = _rgb(cfg.get("color2"), (0, 0, 0))
    for threshold in cfg.get("thresholds", []):
        if _threshold_matches(threshold, status):
            color1 = _rgb(threshold.get("color1"), color1)
            color2 = _rgb(threshold.get("color2"), color2)
            break
    return color1, color2


def keyboard_idle_colors(status: dict, mapping: MappingStore):
    """Couleurs (color1, color2) de la respiration idle du clavier : reactives
    a l'etat de la partie (mêmes seuils que mouse/chromalink) si active soit
    depuis le jeu (case a cocher dans "Couleur par defaut", CONTROL+SHIFT+C,
    -> keyboard_idle.ambient_reactive) soit a la main en ajoutant 'keyboard'
    a ambient.devices dans mapping.json ; sinon la couleur fixe de
    keyboard_idle."""
    ambient_cfg = mapping["ambient"]
    idle_cfg = mapping["keyboard_idle"]
    reactive = idle_cfg.get("ambient_reactive", False) or "keyboard" in ambient_cfg.get("devices", [])
    if reactive:
        return ambient_colors_for(ambient_cfg, status)
    return _rgb(idle_cfg.get("color1")), _rgb(idle_cfg.get("color2"), (0, 0, 0))


def render_device_lane(client: ChromaClient, device: str, hold_state: dict, alerts_cfg: dict,
                        status: dict, ambient_cfg: dict, now: float):
    """Rendu independant pour la souris ou le tapis : evenement ponctuel en
    cours > alerte continue > respiration ambiante."""
    if hold_state["cfg"] and now < hold_state["until"]:
        color = effective_color(hold_state["cfg"], now)
        client.static(device, color if color else (0, 0, 0))
        return

    alert = find_active_alert_for_device(status, alerts_cfg, device)
    if alert:
        color = effective_color(alert[1], now)
        client.static(device, color if color else (0, 0, 0))
        return

    if device in ambient_cfg.get("devices", ["mouse", "mousepad"]):
        color1, color2 = ambient_colors_for(ambient_cfg, status)
        client.breathing(device, color1, color2)


def _on_sigterm(signum, frame):
    # chroma_bridge_watcher.sh arrete le bridge avec un simple `kill` (SIGTERM)
    # quand Factorio se ferme. Sans ce handler, Python termine le processus
    # au niveau OS sans jamais executer le `finally` plus bas -- le clavier
    # ne repasserait jamais en vert fixe.
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, _on_sigterm)
    mapping = MappingStore()

    client = ChromaClient()
    print("Connexion au Chroma SDK...")
    client.connect()
    print(f"Session ouverte : {client.session_uri}")

    play_boot_animation(client, _rgb(mapping["ambient"].get("color1"), (230, 100, 20)))

    watcher = FactorioWatcher()
    print(f"Surveillance de : {watcher.dir}")
    print(f"Config de mapping : {mapping.path} (modifiable a chaud, ou depuis le jeu)")

    all_hold = {"until": 0.0, "cfg": None}
    all_hold_started_at = 0.0
    keyboard_flash = {"until": 0.0, "cfg": None}
    device_hold = {name: {"until": 0.0, "cfg": None} for name in DEVICE_HOLD_NAMES}
    _last_debug_alerts = None
    _last_debug_tick = 0.0

    try:
        while True:
            now = time.time()
            if mapping.reload():
                print("Config rechargee (mapping.json et/ou overrides du jeu).")

            layout = mapping.get("layout", "azerty_fr")
            events_cfg = mapping.get("events", {})
            alerts_cfg = mapping.get("alerts", {})

            for event in watcher.poll_new_events():
                etype = event.get("type")
                print(f"Evenement : {event}")
                cfg = events_cfg.get(etype)
                if not cfg:
                    print(f"  (non mappe dans mapping.json['events'] : {etype!r})")
                    continue
                if not cfg.get("enabled", True):
                    continue

                device = cfg.get("device", "all")
                until = now + max(cfg.get("hold", 0) or 0, 0.05)
                if device == "all":
                    if not (all_hold["cfg"] and now < all_hold["until"]):
                        all_hold_started_at = now  # nouvelle rafale
                    until = min(until, all_hold_started_at + MAX_ALL_HOLD_SECONDS)
                    all_hold = {"until": until, "cfg": cfg}
                elif device == "keyboard":
                    keyboard_flash = {"until": until, "cfg": cfg}
                elif device in device_hold:
                    device_hold[device] = {"until": until, "cfg": cfg}
                else:
                    print(f"[mapping] device inconnu ignore : {device!r}")

            status = watcher.read_status()

            current_alerts = status.get("alerts_by_type", {})
            if current_alerts != _last_debug_alerts:
                print(f"[debug {now:.1f}] alerts_by_type = {current_alerts}")
                _last_debug_alerts = current_alerts
            elif now - _last_debug_tick > 5.0:
                print(f"[debug {now:.1f}] (boucle active, aucun changement d'alerte depuis {int(now - _last_debug_tick)}s)")
                _last_debug_tick = now

            active_all_cfg = None
            if all_hold["cfg"] and now < all_hold["until"]:
                active_all_cfg = all_hold["cfg"]
            else:
                alert = find_active_alert_for_device(status, alerts_cfg, "all")
                if alert:
                    active_all_cfg = alert[1]

            if active_all_cfg:
                if active_all_cfg.get("style") == "spectrum":
                    client.static_all(rainbow_color(now))
                else:
                    color = effective_color(active_all_cfg, now)
                    client.static_all(color if color else (0, 0, 0))
            else:
                for device_name in DEVICE_HOLD_NAMES:
                    render_device_lane(client, device_name, device_hold[device_name], alerts_cfg,
                                        status, mapping["ambient"], now)

                grid = build_keyboard_grid(status, mapping, layout, keyboard_flash, now)
                if grid is not None:
                    client.custom_keyboard(grid)
                else:
                    compute_keyboard_idle(client, status, mapping)

            time.sleep(mapping.get("poll_seconds", 0.2))
    except (KeyboardInterrupt, SystemExit):
        print("Arret demande, fermeture de la session Chroma...")
    finally:
        client.close()


if __name__ == "__main__":
    main()
