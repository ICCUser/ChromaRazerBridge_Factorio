"""
Empaquette le mod Lua (mod/, source de verite dans ce repo) dans un zip pret
pour le mod portal Factorio, SANS rien publier -- juste produit le fichier
dans dist/.

Le mod portal exige que le zip contienne un unique dossier de premier niveau
nomme exactement "<name>_<version>" (d'apres info.json), peu importe le nom
du dossier source sur le disque.

Pour tester en jeu, copie (ou symlink) mod/ dans %APPDATA%\\Factorio\\mods\\
(Windows) ou ~/.factorio/mods/ (Linux) -- voir README.md.

Usage :
    python package_mod.py
"""

import json
import shutil
import zipfile
from pathlib import Path

MOD_SOURCE_DIR = Path(__file__).parent / "mod"
DIST_DIR = Path(__file__).parent / "dist"

REQUIRED_INFO_FIELDS = ["name", "version", "title", "author", "factorio_version"]

# Fichiers/dossiers a ne jamais inclure dans le zip publie (fichiers de dev,
# caches, etc.)
EXCLUDE_NAMES = {"__pycache__", ".DS_Store", "thumbs.db"}


def load_info() -> dict:
    info_path = MOD_SOURCE_DIR / "info.json"
    if not info_path.exists():
        raise SystemExit(f"info.json introuvable : {info_path}")
    info = json.loads(info_path.read_text(encoding="utf-8"))
    missing = [f for f in REQUIRED_INFO_FIELDS if not info.get(f)]
    if missing:
        raise SystemExit(f"info.json incomplet, champs manquants : {missing}")
    return info


def main():
    info = load_info()
    mod_name = info["name"]
    version = info["version"]
    versioned_name = f"{mod_name}_{version}"

    DIST_DIR.mkdir(exist_ok=True)
    staging_root = DIST_DIR / "_staging"
    if staging_root.exists():
        shutil.rmtree(staging_root)
    staging_mod_dir = staging_root / versioned_name
    staging_mod_dir.mkdir(parents=True)

    copied = []
    for item in MOD_SOURCE_DIR.iterdir():
        if item.name in EXCLUDE_NAMES:
            continue
        if item.is_dir():
            shutil.copytree(item, staging_mod_dir / item.name)
        else:
            shutil.copy2(item, staging_mod_dir / item.name)
        copied.append(item.name)

    zip_path = DIST_DIR / f"{versioned_name}.zip"
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file_path in staging_mod_dir.rglob("*"):
            if file_path.is_file():
                arcname = file_path.relative_to(staging_root)
                zf.write(file_path, arcname)

    shutil.rmtree(staging_root)

    print(f"Mod : {mod_name} v{version}")
    print(f"Fichiers inclus : {', '.join(sorted(copied))}")
    print(f"Zip pret pour le mod portal : {zip_path}")
    print()
    print("Rien n'a ete publie. Pour publier sur le mod portal Factorio :")
    print("  1. https://mods.factorio.com/ -> compte -> 'Upload mod'")
    print(f"  2. Selectionner {zip_path}")
    print("  3. Ajouter une image (thumbnail.png, 144x144 ou 72x72) est recommande mais optionnel.")


if __name__ == "__main__":
    main()
