#!/usr/bin/env python3
"""
osm_a_godot.py — convierte un extracto de OpenStreetMap en escenario para Godot.

Genera:
  escenario_osm.glb   terreno por uso de suelo, calles, edificios, agua
  traza_osm.json      la traza del ferrocarril como polilinea, en metros

Uso:
    python3 osm_a_godot.py mapa.osm --salida ./out
    python3 osm_a_godot.py mapa.osm --salida ./out --ferrocarril Roca

Proyeccion: plano local en metros centrado en el medio del extracto.
    +X = este, -Z = norte  (norte coincide con el "adelante" de Godot)

Los datos de OpenStreetMap son ODbL: si publicas algo con esto, va la
atribucion "© colaboradores de OpenStreetMap".
"""
import argparse
import json
import math
import os
import xml.etree.ElementTree as ET

import numpy as np
import trimesh
from mapbox_earcut import triangulate_float64
from trimesh.visual.material import PBRMaterial
from trimesh.visual import TextureVisuals

# ------------------------------------------------------------------ estilos
# (color RGB, altura sobre el plano) por clase de superficie
SUPERFICIES = {
    "residential":  ((0.839, 0.827, 0.804), 0.02),
    "industrial":   ((0.800, 0.792, 0.808), 0.02),
    "commercial":   ((0.855, 0.827, 0.816), 0.02),
    "retail":       ((0.867, 0.824, 0.812), 0.02),
    "grass":        ((0.612, 0.702, 0.478), 0.03),
    "meadow":       ((0.651, 0.729, 0.502), 0.03),
    "farmland":     ((0.776, 0.745, 0.596), 0.02),
    "forest":       ((0.443, 0.573, 0.408), 0.05),
    "park":         ((0.596, 0.729, 0.518), 0.04),
    "pitch":        ((0.529, 0.706, 0.514), 0.05),
    "cemetery":     ((0.686, 0.729, 0.639), 0.03),
    "railway_land": ((0.741, 0.722, 0.694), 0.02),
    "water":        ((0.529, 0.667, 0.741), 0.01),
    "parking":      ((0.855, 0.847, 0.847), 0.03),
}

# ancho de calzada por tipo de via
CALLES = {
    "motorway": 14.0, "trunk": 12.0, "primary": 11.0, "secondary": 9.0,
    "tertiary": 8.0, "residential": 7.0, "unclassified": 6.5,
    "service": 4.5, "living_street": 6.0, "pedestrian": 5.0,
    "footway": 2.0, "path": 1.8, "track": 3.5, "cycleway": 2.2,
}
COLOR_CALLE = (0.361, 0.353, 0.349)
COLOR_VEREDA = (0.741, 0.729, 0.706)
COLOR_EDIFICIO = (0.784, 0.741, 0.702)
COLOR_TECHO = (0.596, 0.549, 0.522)
COLOR_BASE = (0.678, 0.694, 0.616)


def clase_superficie(tags):
    for clave in ("landuse", "natural", "leisure", "amenity"):
        v = tags.get(clave)
        if v in SUPERFICIES:
            return v
    if tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
        return "water"
    if tags.get("landuse") == "railway":
        return "railway_land"
    if tags.get("amenity") == "parking":
        return "parking"
    return None


# -------------------------------------------------------------------- parseo
def leer_osm(ruta):
    nodos = {}
    vias = []
    for evento, elem in ET.iterparse(ruta, events=("end",)):
        etiqueta = elem.tag
        if etiqueta == "node":
            nodos[elem.get("id")] = (float(elem.get("lat")), float(elem.get("lon")))
            elem.clear()
        elif etiqueta == "way":
            refs = [nd.get("ref") for nd in elem.findall("nd")]
            tags = {t.get("k"): t.get("v") for t in elem.findall("tag")}
            if refs:
                vias.append((refs, tags))
            elem.clear()
        elif etiqueta == "relation":
            elem.clear()
    return nodos, vias


def proyectar(nodos):
    lats = [v[0] for v in nodos.values()]
    lons = [v[1] for v in nodos.values()]
    lat0 = (min(lats) + max(lats)) / 2.0
    lon0 = (min(lons) + max(lons)) / 2.0
    kx = 111320.0 * math.cos(math.radians(lat0))
    kz = 110574.0
    xy = {i: ((lon - lon0) * kx, -(lat - lat0) * kz)
          for i, (lat, lon) in nodos.items()}
    return xy, lat0, lon0


# ------------------------------------------------------------------ geometria
def malla_poligono(puntos, altura, extrusion=0.0):
    """Triangula un poligono simple. Si extrusion > 0 lo levanta como prisma."""
    p = np.asarray(puntos, dtype=np.float64)
    if len(p) > 2 and np.allclose(p[0], p[-1]):
        p = p[:-1]
    if len(p) < 3:
        return None
    area = 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
    if abs(area) < 1.0:
        return None
    try:
        idx = triangulate_float64(p, np.array([len(p)]))
    except Exception:
        return None
    if len(idx) < 3:
        return None
    caras = idx.reshape(-1, 3)

    if extrusion <= 0.0:
        v = np.column_stack([p[:, 0], np.full(len(p), altura), p[:, 1]])
        m = trimesh.Trimesh(vertices=v, faces=caras[:, ::-1], process=False)
        return m

    n = len(p)
    abajo = np.column_stack([p[:, 0], np.full(n, altura), p[:, 1]])
    arriba = np.column_stack([p[:, 0], np.full(n, altura + extrusion), p[:, 1]])
    v = np.vstack([abajo, arriba])
    f = [c + n for c in caras]           # tapa superior
    for i in range(n):                   # paredes
        j = (i + 1) % n
        f.append([i, j, n + j])
        f.append([i, n + j, n + i])
    m = trimesh.Trimesh(vertices=v, faces=np.array(f), process=False)
    m.fix_normals()
    return m


def cinta(puntos, ancho, altura):
    """Convierte una polilinea en una cinta plana (calzada)."""
    p = np.asarray(puntos, dtype=float)
    if len(p) < 2:
        return None
    v, f = [], []
    h = ancho / 2.0
    for i in range(len(p) - 1):
        a, b = p[i], p[i + 1]
        d = b - a
        largo = np.hypot(*d)
        if largo < 0.05:
            continue
        nrm = np.array([-d[1], d[0]]) / largo
        cuatro = [a + nrm * h, a - nrm * h, b - nrm * h, b + nrm * h]
        k = len(v)
        v += [[q[0], altura, q[1]] for q in cuatro]
        f += [[k, k + 1, k + 2], [k, k + 2, k + 3]]
    if not f:
        return None
    return trimesh.Trimesh(vertices=np.array(v), faces=np.array(f), process=False)


def altura_edificio(tags):
    for clave in ("height", "building:height"):
        if clave in tags:
            try:
                return max(2.5, float(str(tags[clave]).split()[0]))
            except ValueError:
                pass
    for clave in ("building:levels", "levels"):
        if clave in tags:
            try:
                return max(2.5, float(tags[clave]) * 3.1)
            except ValueError:
                pass
    return 6.5


# ------------------------------------------------------------------ ferrocarril
def cadena_ferrocarril(vias, xy, filtro):
    """Une los tramos de via ferrea en la polilinea continua mas larga."""
    tramos = []
    for refs, tags in vias:
        if tags.get("railway") not in ("rail", "light_rail", "narrow_gauge"):
            continue
        if filtro:
            texto = " ".join([tags.get("name", ""), tags.get("ref", ""),
                              tags.get("operator", ""), tags.get("usage", "")])
            if filtro.lower() not in texto.lower():
                continue
        if tags.get("service") in ("siding", "yard", "spur", "crossover"):
            continue
        pts = [refs[0], refs[-1]]
        if len(refs) >= 2 and all(r in xy for r in refs):
            tramos.append((pts, refs))
    if not tramos:
        return []

    usados = set()
    cadenas = []
    for i, (extremos, refs) in enumerate(tramos):
        if i in usados:
            continue
        usados.add(i)
        cadena = list(refs)
        creciendo = True
        while creciendo:
            creciendo = False
            for j, (e2, r2) in enumerate(tramos):
                if j in usados:
                    continue
                if cadena[-1] == r2[0]:
                    cadena += r2[1:]
                elif cadena[-1] == r2[-1]:
                    cadena += list(reversed(r2))[1:]
                elif cadena[0] == r2[-1]:
                    cadena = list(r2)[:-1] + cadena
                elif cadena[0] == r2[0]:
                    cadena = list(reversed(r2))[:-1] + cadena
                else:
                    continue
                usados.add(j)
                creciendo = True
        cadenas.append(cadena)

    mejor = max(cadenas, key=len)
    return [xy[r] for r in mejor if r in xy]


def simplificar(puntos, tolerancia=1.5):
    """Douglas-Peucker, para no llenar el Path3D de puntos redundantes."""
    if len(puntos) < 3:
        return puntos
    p = np.asarray(puntos, dtype=float)
    a, b = p[0], p[-1]
    d = b - a
    largo = np.hypot(*d)
    if largo < 1e-6:
        dist = np.hypot(*(p - a).T)
    else:
        rel = p - a
        dist = np.abs(d[0] * rel[:, 1] - d[1] * rel[:, 0]) / largo
    i = int(np.argmax(dist))
    if dist[i] > tolerancia:
        izq = simplificar(p[:i + 1], tolerancia)
        der = simplificar(p[i:], tolerancia)
        return list(izq[:-1]) + list(der)
    return [tuple(a), tuple(b)]


# --------------------------------------------------------------------- salida
def exportar(grupos, ruta):
    sc = trimesh.Scene()
    for nombre, (mallas, color, met, rough) in grupos.items():
        mallas = [m for m in mallas if m is not None and len(m.faces)]
        if not mallas:
            continue
        m = trimesh.util.concatenate(mallas)
        m.unmerge_vertices()
        v, f, n = m.vertices, m.faces, m.face_normals
        uv = np.zeros((len(v), 2))
        ax = np.argmax(np.abs(n), axis=1)
        pick = {0: (2, 1), 1: (0, 2), 2: (0, 1)}
        for i, cara in enumerate(f):
            a, b = pick[ax[i]]
            uv[cara, 0] = v[cara, a]
            uv[cara, 1] = v[cara, b]
        m.visual = TextureVisuals(uv=uv, material=PBRMaterial(
            name=nombre, baseColorFactor=[*color, 1.0],
            metallicFactor=met, roughnessFactor=rough, doubleSided=True))
        sc.add_geometry(m, node_name=nombre, geom_name=nombre)
        print(f"  {nombre:16s} {len(m.faces):7d} tris")
    sc.export(ruta)


def main():
    ap = argparse.ArgumentParser(description="OpenStreetMap -> escenario Godot")
    ap.add_argument("osm", help="archivo .osm (XML) exportado de Overpass o OSM")
    ap.add_argument("--salida", default=".", help="carpeta de salida")
    ap.add_argument("--ferrocarril", default="",
                    help="filtro por nombre/ref/operador de la linea, ej: Roca")
    ap.add_argument("--sin-edificios", action="store_true")
    args = ap.parse_args()

    os.makedirs(args.salida, exist_ok=True)
    print("leyendo", args.osm)
    nodos, vias = leer_osm(args.osm)
    print(f"  {len(nodos)} nodos, {len(vias)} vias")
    xy, lat0, lon0 = proyectar(nodos)
    print(f"  origen: lat {lat0:.6f}, lon {lon0:.6f}")

    coords = np.array(list(xy.values()))
    minx, minz = coords.min(axis=0)
    maxx, maxz = coords.max(axis=0)
    margen = 150.0
    print(f"  extension: {maxx-minx:.0f} x {maxz-minz:.0f} m")

    base = malla_poligono([(minx - margen, minz - margen), (maxx + margen, minz - margen),
                           (maxx + margen, maxz + margen), (minx - margen, maxz + margen)],
                          altura=0.0)

    grupos = {
        "Base":      ([base], COLOR_BASE, 0.0, 1.0),
        "Calzada":   ([], COLOR_CALLE, 0.0, 0.95),
        "Vereda":    ([], COLOR_VEREDA, 0.0, 0.95),
        "Edificios": ([], COLOR_EDIFICIO, 0.05, 0.85),
    }
    for clase, (color, _) in SUPERFICIES.items():
        grupos["Suelo_" + clase] = ([], color, 0.0, 1.0)

    n_sup = n_calle = n_edif = 0
    for refs, tags in vias:
        if not all(r in xy for r in refs):
            continue
        pts = [xy[r] for r in refs]
        cerrado = len(refs) >= 4 and (
            refs[0] == refs[-1] or math.dist(pts[0], pts[-1]) < 0.5)

        if "building" in tags or "building:part" in tags:
            # un tag de edificio implica area aunque el trazado no cierre
            if args.sin_edificios or len(refs) < 4:
                continue
            m = malla_poligono(pts, 0.04, extrusion=altura_edificio(tags))
            if m is not None:
                grupos["Edificios"][0].append(m)
                n_edif += 1
            continue

        clase = clase_superficie(tags)
        if clase and (cerrado or len(refs) >= 4):
            color, alt = SUPERFICIES[clase]
            m = malla_poligono(pts, alt)
            if m is not None:
                grupos["Suelo_" + clase][0].append(m)
                n_sup += 1
            continue

        via = tags.get("highway")
        if via in CALLES:
            peatonal = via in ("footway", "path", "pedestrian", "cycleway")
            destino = "Vereda" if peatonal else "Calzada"
            m = cinta(pts, CALLES[via], 0.09 if peatonal else 0.07)
            if m is not None:
                grupos[destino][0].append(m)
                n_calle += 1

    print(f"  {n_sup} superficies, {n_calle} calles, {n_edif} edificios")
    print("exportando geometria:")
    exportar(grupos, os.path.join(args.salida, "escenario_osm.glb"))

    # -------------------------------------------------------------- la traza
    linea = cadena_ferrocarril(vias, xy, args.ferrocarril)
    if linea:
        linea = simplificar(linea, 1.5)
        largo = sum(math.dist(linea[i], linea[i + 1]) for i in range(len(linea) - 1))
        datos = {
            "origen": {"lat": lat0, "lon": lon0},
            "largo_m": round(largo, 1),
            "puntos": [[round(x, 3), 0.0, round(z, 3)] for x, z in linea],
        }
        ruta = os.path.join(args.salida, "traza_osm.json")
        json.dump(datos, open(ruta, "w"), indent=1)
        print(f"traza: {len(linea)} puntos, {largo:.0f} m -> {ruta}")
    else:
        print("traza: no encontre vias ferreas con ese filtro")


if __name__ == "__main__":
    main()
