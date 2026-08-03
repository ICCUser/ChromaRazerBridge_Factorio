"""
Test isole des effets Chroma de base, sans passer par mapping.json ni
Factorio. Sert a determiner si un souci (tapis, arc-en-ciel...) vient du
SDK Chroma / Synapse, ou de la logique de main.py.

Lance-le pendant que Synapse tourne (Factorio n'a pas besoin d'etre ouvert) :
    python diagnose.py
"""

import sys
import time

from chroma_client import rainbow_color
if sys.platform.startswith("linux"):
    from chroma_client_linux import ChromaClient
else:
    from chroma_client import ChromaClient

client = ChromaClient(app_name="Chroma Bridge - Diagnostic")
print("Connexion au Chroma SDK...")
client.connect()
print(f"Session ouverte : {client.session_uri}")

print("\n1a) Tapis de souris en ROUGE via CHROMA_STATIC ('mousepad') pendant 3s...")
client.static("mousepad", (255, 0, 0))
time.sleep(3)

print("1b) Tapis de souris en VIOLET via CHROMA_CUSTOM ('mousepad', 20 LEDs) pendant 3s...")
if hasattr(client, "custom_mousepad"):
    client.custom_mousepad((200, 0, 255))
else:
    print("   (custom_mousepad non supporte par ce client, teste comme 'static' a la place)")
    client.static("mousepad", (200, 0, 255))
time.sleep(3)

print("1c) Tapis de souris en JAUNE via CHROMA_STATIC ('chromalink') pendant 3s...")
client.static("chromalink", (255, 255, 0))
time.sleep(3)

print("2) Souris en BLEU fixe pendant 3s...")
client.static("mouse", (0, 0, 255))
time.sleep(3)

print("3) Clavier en VERT fixe pendant 3s...")
client.static("keyboard", (0, 255, 0))
time.sleep(3)

print("4) Cycle de teintes (arc-en-ciel maison) sur tout le setup pendant 6s...")
start = time.time()
while time.time() - start < 6:
    client.static_all(rainbow_color(time.time()))
    time.sleep(0.05)

print("5) Retour a l'ambiance normale (respiration orange, 10s -- l'effet monte/descend")
print("   lentement, laisse-lui le temps avant de conclure a un souci)...")
client.breathing("chromalink", (230, 100, 20), (20, 10, 0))
client.breathing("mouse", (230, 100, 20), (20, 10, 0))
client.breathing("keyboard", (230, 100, 20), (20, 10, 0))
time.sleep(10)

client.close()
print("\nTermine. Pour chaque etape, le bon appareil/couleur s'est-il bien affiche ?")
print("  1a) Tapis rouge (CHROMA_STATIC, device 'mousepad') ?")
print("  1b) Tapis violet (CHROMA_CUSTOM, device 'mousepad') ?")
print("  1c) Tapis jaune (CHROMA_STATIC, device 'chromalink') ?")
print("  2) Souris bleue ?")
print("  3) Clavier vert ?")
print("  4) Arc-en-ciel visible (sur les 3 appareils, y compris le tapis) ?")
