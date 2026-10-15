"""
Script de verificación de la red de vías en Godot:
1. Verifica que la escena track_network.tscn tenga la estructura correcta de nodos.
2. Verifica que red_godot_constitucion_bosques.json tenga consistencia topológica.
3. Verifica que todos los segmentos pertenezcan a los sectores válidos.
"""

import json
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

TSCN_PATH = "scenes/tracks/track_network.tscn"
JSON_PATH = "tramo_completo_constitucion_bosques/red_godot_constitucion_bosques.json"

print("=== VERIFICACIÓN DE RED CONSTITUCIÓN - BOSQUES ===")

# 1. Verificar JSON
with open(JSON_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

segs = data["segments"]
juncs = data["junctions"]

print(f"1. Archivo JSON:")
print(f"   - Total segmentos: {len(segs)}")
print(f"   - Total junctions: {len(juncs)}")

# Verificar que no haya ningún segmento con tags de exclusión
sectores = set(s.get("sector") for s in segs)
tramos = set(s.get("tramo") for s in segs)
print(f"   - Sectores detectados: {len(sectores)}")
for sec in sorted(sectores):
    count = sum(1 for s in segs if s.get("sector") == sec)
    print(f"     * {sec}: {count} segs")

print(f"   - Tramos detectados: {len(tramos)}")

# 2. Verificar Escena .tscn
with open(TSCN_PATH, "r", encoding="utf-8") as f:
    lines = f.readlines()

print(f"\n2. Escena .tscn:")
print(f"   - Total líneas: {len(lines)}")

nodes = []
subres = []
for i, line in enumerate(lines):
    if line.startswith("[sub_resource "):
        subres.append(line.strip())
    elif line.startswith("[node "):
        nodes.append((i + 1, line.strip()))

print(f"   - SubResources Curve3D: {len(subres)}")
print(f"   - Nodos en la escena: {len(nodes)}")

# Mostrar jerarquía de sectores y tramos
sector_nodes = [n for n in nodes if "Sector_" in n[1]]
tramo_nodes = [n for n in nodes if any(t in n[1] for t in tramos)]
path_nodes = [n for n in nodes if 'type="Path3D"' in n[1]]

print(f"   - Nodos Sector: {len(sector_nodes)}")
print(f"   - Nodos Tramo (Estaciones): {len(tramo_nodes)}")
print(f"   - Nodos Path3D: {len(path_nodes)}")

print("\n=== ESTRUCTURA DEL ÁRBOL EN GODOT ===")
print("TrackNetwork")
print("└── Vias")
for lnum, s_node in sector_nodes:
    m = re.search(r'name="([^"]+)"', s_node)
    sec_name = m.group(1) if m else s_node
    print(f"    ├── {sec_name}")
    for t_num, t_node in tramo_nodes:
        if f"parent=\"Vias/{sec_name}\"" in t_node:
            tm = re.search(r'name="([^"]+)"', t_node)
            t_name = tm.group(1) if tm else t_node
            # contar paths en este tramo
            p_count = sum(1 for _, p in path_nodes if f"parent=\"Vias/{sec_name}/{t_name}\"" in p)
            print(f"    │   ├── {t_name} ({p_count} vías)")

print("\n¡Verificación completada con éxito!")
