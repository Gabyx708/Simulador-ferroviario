# Terreno real desde OpenStreetMap

`osm_a_godot.py` convierte un extracto de OSM en escenario para Godot: terreno
por uso de suelo, calles, edificios extruidos, agua, y la traza del ferrocarril
lista para el `Path3D`.

## 1. Bajar el mapa

Andá a **overpass-turbo.eu**, ubicá el mapa sobre el corredor que te interesa
(por ejemplo Bosques–Claypole) y corré esta consulta:

```
[out:xml][timeout:120];
(
  way["railway"](bbox);
  way["highway"](bbox);
  way["building"](bbox);
  way["landuse"](bbox);
  way["natural"](bbox);
  way["leisure"](bbox);
  way["waterway"](bbox);
);
(._;>;);
out body;
```

Ejecutar → **Export** → **datos sin procesar de OSM**. Te baja un `.osm`.

Un consejo de escala: el ramal entero Constitución–Bosques son unos 32 km y el
archivo se pone pesado. Empezá con un recuadro de 3 o 4 km alrededor de una
estación, mirá cómo queda, y después ampliá.

## 2. Convertir

```bash
pip install numpy trimesh mapbox_earcut
python3 osm_a_godot.py mapa.osm --salida ./salida --ferrocarril Roca
```

Salen dos archivos:

- **`escenario_osm.glb`** — la geometría, agrupada por clase (`Base`, `Calzada`,
  `Vereda`, `Edificios`, `Suelo_residential`, `Suelo_park`, `Suelo_water`…).
  Cada grupo es un nodo con su material, así que los recoloreás en Godot sin
  volver a convertir.
- **`traza_osm.json`** — la traza ferroviaria como polilínea en metros.

El filtro `--ferrocarril` compara contra el nombre, la referencia y el operador
de la vía. Sin filtro agarra todas las vías férreas y se queda con la cadena
continua más larga. Si el ramal te sale cortado, probá sin filtro o revisá que
en OSM los tramos compartan nodos en los empalmes.

Otras opciones: `--sin-edificios` para una pasada rápida de prueba.

## 3. Meterlo en Godot

Copiá `escenario_osm.glb`, `traza_osm.json` y `traza_osm.gd` a `res://`.

1. Arrastrá `escenario_osm.glb` a la escena y borrá el nodo `Terreno` (el plano
   verde) y el `Sol` seguilo usando.
2. Seleccioná el `Path3D` llamado `Traza` y asignale el script `traza_osm.gd`.
   En el Inspector tocá **Reconstruir**. La vía y los postes, que son hijos con
   `@tool`, se rehacen solos sobre el trazado nuevo.
3. Recalculá las paradas. El script trae `progreso_mas_cercano()`: poné un
   `Marker3D` en el andén y desde un script o la consola de depuración pedile
   el progreso, después cargá ese número en `Formacion → paradas`.

## Proyección y alineación

El origen del plano local queda en el centro del extracto, con **+X al este** y
**−Z al norte**. Como el `.glb` y el `.json` salen de la misma corrida, el
terreno y la traza quedan alineados sin tocar nada. Si convertís dos recuadros
distintos no van a coincidir, porque cada corrida elige su propio centro.

La proyección es equirectangular local: exacta para unos pocos kilómetros, con
un error que crece si abarcás decenas de kilómetros de este a oeste.

## Limitaciones

- **Sin relieve.** OSM no trae altimetría y todo queda a cota cero. Para el Roca
  entre Varela y Constitución eso es prácticamente correcto: es llano.
- **Multipolígonos ignorados.** Las relaciones de OSM no se procesan, así que un
  parque con un lago adentro sale relleno. Afecta a pocos casos.
- **Alturas de edificios estimadas.** Se usa `height` o `building:levels` si
  están; si no, 6,5 m. En el conurbano la mayoría de los edificios no tienen el
  dato cargado.
- **Techos planos**, sin texturas ni aberturas. Es masa urbana de fondo, no
  arquitectura.

## Licencia

Los datos son de OpenStreetMap, bajo ODbL. Si publicás el juego tenés que
acreditar "© colaboradores de OpenStreetMap". El código del conversor es tuyo,
la obligación es sobre los datos.
