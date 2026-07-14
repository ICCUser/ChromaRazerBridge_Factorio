"""
Affiche un tableau recapitulatif : chaque evenement/alerte Factorio dispo
cote mod Lua, en face de sa configuration actuelle dans mapping.json
(touches/zone, couleur, effet) -- ou "non configure" si absent.

Usage :
    python print_mapping_table.py [azerty_fr|qwerty_us]
"""

import sys

from keyboard_layout import ZONE_DEFINITIONS
from main import scope_positions
from mapping_loader import MappingStore

# Evenements ponctuels emis par control.lua (chroma_events.jsonl)
EVENTS_CATALOG = [
    ("research_finished", "Une recherche vient de se terminer"),
    ("base_under_attack", "Une entite du joueur est attaquee par des biters"),
    ("rocket_launched", "Une fusee vient d'etre lancee"),
    ("player_died", "Le joueur vient de mourir"),
    ("train_arrived", "Un train vient de s'arreter a quai"),
    ("item_crafted", "Le joueur vient de finir un craft manuel"),
]

# Types d'alerte Factorio (defines.alert_type) rapportes en continu dans
# chroma_status.json -> alerts_by_type. Liste complete a titre indicatif ;
# seuls ceux ajoutes dans mapping.json['alerts'] declenchent un effet.
ALERTS_CATALOG = [
    ("entity_under_attack", "Une entite du joueur subit des degats"),
    ("turret_fire", "Une tourelle du joueur tire"),
    ("no_power", "[Synthetique] Entite(s) sans courant du tout, autour du joueur"),
    ("low_power", "[Synthetique] Entite(s) en sous-alimentation electrique, autour du joueur"),
    ("entity_destroyed", "Une entite du joueur a ete detruite"),
    ("train_no_path", "Un train n'a plus de chemin possible"),
    ("train_out_of_fuel", "Un train est a court de carburant"),
    ("no_material_for_construction", "Manque de materiaux pour une construction"),
    ("not_enough_construction_robots", "Pas assez de robots de construction"),
    ("not_enough_repair_packs", "Pas assez de kits de reparation"),
    ("no_storage", "Aucun espace de stockage disponible pour le reseau logistique"),
    ("no_roboport_storage", "Roboport plein"),
    ("no_platform_storage", "Plateforme (espace) pleine"),
    ("unclaimed_cargo", "Cargaison spatiale non reclamee"),
    ("pipeline_overextended", "Reseau de fluide trop etendu"),
    ("fluid_mixing", "Melange de fluides incompatibles"),
    ("collector_path_blocked", "Chemin d'un collecteur bloque"),
    ("platform_tile_building_blocked", "Construction bloquee sur une plateforme"),
    ("custom", "Alerte personnalisee (mod tiers)"),
]


def describe(cfg: dict, layout: str) -> str:
    if not cfg:
        return "-- non configure --"
    device = cfg.get("device", "all")
    parts = [f"device={device}"]

    if cfg.get("style") == "spectrum":
        parts.append("style=spectrum (arc-en-ciel)")
    elif cfg.get("color"):
        parts.append(f"couleur={tuple(cfg['color'])}")

    if device == "keyboard":
        scope = cfg.get("scope", "all")
        count = len(scope_positions(scope, layout))
        scope_label = ", ".join(scope) if isinstance(scope, list) else scope
        parts.append(f"scope={scope_label} ({count} LEDs)")

    if cfg.get("blink"):
        parts.append(f"clignote toutes les {cfg.get('blink_interval', 0.3)}s")
    if cfg.get("hold"):
        parts.append(f"hold={cfg['hold']}s")
    if cfg.get("priority"):
        parts.append(f"priorite={cfg['priority']}")
    return ", ".join(parts)


def print_table(title: str, catalog, configured: dict, layout: str):
    print(f"\n=== {title} ===")
    name_width = max(len(name) for name, _ in catalog) + 2
    for name, description in catalog:
        cfg = configured.get(name)
        marker = "OK " if cfg else "   "
        print(f"{marker}{name:<{name_width}} {description}")
        print(f"    -> {describe(cfg, layout)}")


def main():
    layout = sys.argv[1] if len(sys.argv) > 1 else None
    mapping = MappingStore()
    layout = layout or mapping.get("layout", "azerty_fr")

    print(f"Layout actif : {layout}")
    print(f"Zones disponibles pour 'keys': {', '.join(sorted(ZONE_DEFINITIONS.keys()))}")

    print_table("Evenements ponctuels (chroma_events.jsonl)", EVENTS_CATALOG, mapping.get("events", {}), layout)
    print_table("Alertes continues (chroma_status.json / alerts_by_type)", ALERTS_CATALOG, mapping.get("alerts", {}), layout)

    unknown_events = set(mapping.get("events", {})) - {n for n, _ in EVENTS_CATALOG}
    unknown_alerts = set(mapping.get("alerts", {})) - {n for n, _ in ALERTS_CATALOG}
    if unknown_events:
        print(f"\nAttention : evenements configures mais inconnus du mod : {sorted(unknown_events)}")
    if unknown_alerts:
        print(f"Attention : alertes configurees mais inconnues de Factorio : {sorted(unknown_alerts)}")


if __name__ == "__main__":
    main()
