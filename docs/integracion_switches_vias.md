# Integración Aparatos de Vía ↔ Vías (ramal_roca_switches)

Documento de diagnóstico, cambios aplicados y **propuesta de mejora** para la
escena `levels/ramal_roca_switches/ramal_roca_switches.tscn`
(Godot 4.7, tipado estático GDScript).

---

## 1. Resumen ejecutivo

La escena estaba **rota de forma crítica** y la edición manual **no se persistía**.
La causa no era una sola: había un error de tipado que abortaba toda la
integración, una lista de "tramos eliminados" contaminada que **borraba la red
completa al abrir la escena**, y un journal de ediciones que se escribía pero
nunca se leía.

Se corrigieron los defectos de comportamiento y persistencia, y se dejó un
instrumento de medición (`tools/audit_integracion_switches.gd`) para verificar la
calidad del empalme con números en vez de a ojo.

### Métricas medidas (headless, Godot 4.7.2)

| Métrica | Antes | Ahora |
| :-- | :-- | :-- |
| Tramos presentes al abrir la escena | **0 / 569** (se purgaban todos) | 569 / 569 |
| Puertos sin unión | 294 / 620 | 16 huecos reales + 69 uniones naturales |
| Leads con ángulo forzado > 60° | 200 / 620 | **0 / 620** |
| Extremos con codo lateral (proyección/largo < 0.85) | 24 | **1** (peor 0.75) |
| Desvío lateral máx. de la unión | sin medir | **0.48 m** en 7 m (radio ≥ 2 m) |
| Separación extremo flexible ↔ vía real | sin medir | **0.000 m** (máx., 514/514 conexiones) |
| Quiebre tangencial en el empalme | sin medir | **≤ 0.02°** |
| Tramos absorbidos por los cortes de aparatos | 279 / 569 (corte 120 m) | **107 / 566** |
| Bajas falsas al descargar/recargar la escena | **+569** | **0** |
| Botón *Guardar todas las ediciones* | error en runtime (propiedad inexistente) | funciona |

> **Nota sobre las métricas**: se midieron sobre la escena con sus 569 tramos. La
> escena guardada después (07:22 del 09/10) tiene **566** tramos porque su lista de
> exclusiones incluye 5 ids (`seg_181, seg_185, seg_193, seg_194, seg_198`). Esos
> tramos se pueden reincorporar con el pulsador `boton_restaurar_todos_los_tramos`.

---

## 2. Diagnóstico (con evidencia)

Reproducción base:

```bash
godot --headless --path . -s res://tools/test_editable_tracks.gd
```

### B1 — El rebuild de conexiones nunca se ejecutaba (P0)

```
SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[int]".
   at: TrackNetwork._reconstruir_conexiones_adaptativas (track_network.gd:2231)
```

`var ids: Array[int] = junctions_por_aparato.get(instance_id, []) as Array[int]`
devuelve `null`: no se puede castear con `as Array[int]` un `Array` sin tipar.
La función abortaba en la primera línea del bucle, así que **ningún** switch
re-cortaba la vía ni re-anclaba sus extremos flexibles: los aparatos quedaban
apoyados sobre la vía plena, sin recortes ni empalmes.

### B2 — Purga destructiva de la escena al abrirla (P0)

`tramo_completo_constitucion_bosques/red_godot_constitucion_bosques_edits.json`
contenía **571 entradas en `_eliminados`**, es decir *todos* los ids de la red
filtrada:

```
segmentos en la escena: 569   |   ids marcados como eliminados: 571   |   intersección: 569
```

`TrackNetwork._ready()` fusionaba esa lista dentro de `tramos_excluidos` y luego
llamaba a `_purgar_tramos_excluidos_del_arbol()`, que **borraba los 569 tramos
del árbol**. Resultado observable: al abrir la escena quedaba vacía y, si se
guardaba (Ctrl+S), la red entera se perdía. Ésta es la razón principal de que
"no se persista la edición manual".

### B3 — La baja de un tramo se deducía de `_exit_tree()` (P0, origen de B2)

`EditableTrackSegment._exit_tree()` trataba *cualquier* salida del árbol como un
borrado del usuario: recarga de escena, cierre del nivel, recarga de scripts `@tool`,
etc. Por eso `_eliminados` terminó conteniendo la red completa.

### B4 — El journal de ediciones era "sólo escritura" (P1)

- `_switches` se escribía en el JSON pero **nunca se leía**.
- `guardar_todas_las_ediciones()` accedía a `sw.desviada` y `sw.largo_turnout`,
  propiedades que no existen en `BaseTurnout` (`desviada` no existe en ninguna
  clase; `largo_turnout` no existe en el Tipo C) → error en runtime al guardar.
- No existía forma de persistir el **movimiento** ni el **borrado** de un switch.

### B5 — El recorte de vía era un valor fijo de 120 m (P1)

`_calcular_distancia_adaptativa()` devolvía `DISTANCIA_MINIMA_ADAPTACION_SWITCH = 120.0`
para *todos* los puertos. Con el crash de B1 corregido, eso absorbía tramos
enteros: **279 de 569 tramos desaparecían** (49 % de la traza real de OSM).

### B6 — Direcciones "hardcodeadas" en los ramales cortos (P2)

Cuando un tramo es más corto que el largo nominal del flexible, el generador
conectaba con direcciones constantes (`Vector3.BACK`, `Vector3(0.15, 0, 0.98)`, …)
en lugar de la tangente real de la vía en el otro nodo: hasta **22°** de quiebre
en el empalme (y 200 leads con ángulo forzado > 60° según la auditoría previa
`tools/audit.log`).

---

## 3. Cambios aplicados

### 3.1 `scenes/tracks/track_network.gd`

1. **Tipado (B1)**: `junctions_por_aparato` se reconstruye con listas tipadas
   (`Array[int]`) en lugar de castear con `as Array[int]`.
2. **Fuente de verdad (B2)**: la **escena manda**. `_ready()` ya no vuelca
   `_eliminados` sobre `tramos_excluidos`; se guarda aparte en
   `_eliminados_persistentes` y se usa **sólo** al regenerar desde el JSON base.
3. **Auto-sanado (B2)**: `_reconciliar_eliminados_con_escena()` descarta del
   journal cualquier baja de un tramo que sí existe como nodo en la escena
   (el archivo contaminado quedó reducido a `["seg_181", "seg_185"]`, que son
   las exclusiones explícitas reales).
4. **Bajas confiables (B3)**: `solicitar_baja_segmento()` + confirmación diferida
   (`_confirmar_bajas_pendientes()`): la baja se persiste **sólo** si el nodo
   desapareció de verdad y la escena sigue viva, y se descarta si el lote es
   masivo (desmontaje) o si el nodo reapareció (undo).
5. **Persistencia completa (B4)**:
   - `_persistir_diccionario_switches()` escribe pose (`transform`), tipo, largos
     y estado — sin tocar propiedades inexistentes.
   - `_aplicar_switches_guardados()` **lee** el journal al regenerar desde JSON.
   - `eliminar_switch()` da de baja un aparato y lo registra en
     `_switches_eliminados`; `_aplicar_bajas_switches_persistentes()` evita que
     se regenere.
   - `_quitar_aparato_del_registro()` limpia **todas** las claves de un aparato
     compuesto (tijeras/escapes registran varios `node_id` por instancia).
6. **Recorte proporcional (B5)**: `_calcular_distancia_adaptativa()` usa el largo
   real del puerto (`longitud_extension`) y
   `_ajustar_distancia_para_transicion_valida()` garantiza que la transición
   tenga al menos `LONGITUD_MINIMA_TRANSICION` (6 m) de avance; si el tramo es
   más corto, el flexible cubre el tramo hasta la unión opuesta.
7. **Tangentes reales (B6)**: todas las conexiones de ramal corto usan
   `_dir_local_hacia_extremo_opuesto()` (tangente real de la vía) en vez de
   direcciones constantes.
8. **Asignación puerto ↔ vía**: `_seleccionar_lead_para_conexion()` prioriza la
   **alineación** sobre la distancia (un puerto mal asignado generaba un flexible
   apuntando al lado contrario → hueco).
9. **Seguimiento en el editor (mover/borrar switches)**: `_process()` (sólo en
   editor) detecta cambios de pose/estado por *huella* y, tras un debounce de
   0.35 s, re-ancla los extremos flexibles y actualiza el journal
   (`reintegrar_switches_editados()`); `_detectar_switches_removidos()` registra
   la baja si el aparato se quitó del contenedor.
10. **Métricas de empalme**: cada conexión registra `gap` y `kink_deg` en
    `_conexiones_switch_segmento` (base del script de auditoría).
11. **Depuración defensiva**: `_depurar_tramos_invalidos()` elimina de `paths`
    los nodos liberados por el editor (evitaba "cast a freed object" que abortaba
    la malla 3D completa).

### 3.2 `scenes/tracks/editable_track_segment.gd`

- `_exit_tree()` ya no persiste la baja: notifica con `solicitar_baja_segmento()`
  y deja que `TrackNetwork` la confirme en el próximo frame.

### 3.3 `scenes/procedural_track/base_turnout.gd`

- Nuevo grupo **Edición Manual** con el pulsador `boton_eliminar_aparato`
  (baja persistente de un switch desde el Inspector) y el helper público
  `eliminar_aparato()` / `obtener_track_network()`.

### 3.4 `scenes/tracks/track_geometry.gd`

- `construir_geometria()` y `actualizar_geometria_tramo()` ignoran entradas
  liberadas (`is_instance_valid`) en vez de abortar la generación.

### 3.5 Herramientas nuevas

| Archivo | Uso |
| :-- | :-- |
| `tools/audit_integracion_switches.gd` | Mide huecos, gap y quiebre tangencial por conexión |
| `tools/test_persistencia_edicion.gd` | Test de persistencia (borrar/mover/eliminar + regresión de desmontaje) |
| `tools/diag_puertos_switch.gd` | Diagnóstico puntual del estado de los puertos de un switch |

---

## 4. Verificación

```bash
GODOT="/c/Program Files (x86)/Godot/Oficial/Godot4/GD/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe"

# Comportamiento + persistencia de tramos (tests existentes, ahora en verde)
"$GODOT" --headless --path . -s res://tools/test_editable_tracks.gd

# Persistencia de edición manual (borrar/mover/eliminar + regresión)
"$GODOT" --headless --path . -s res://tools/test_persistencia_edicion.gd

# Calidad de la integración switch ↔ vías
"$GODOT" --headless --path . -s res://tools/audit_integracion_switches.gd

# Smoke test del nivel
"$GODOT" --headless --path . --quit-after 150 res://levels/ramal_roca_switches/ramal_roca_switches.tscn
```

> Los tests escriben en journals temporales (`res://tools/_test_*_temporal.json`)
> para no tocar `red_godot_constitucion_bosques_edits.json`.

---

## 5. Unión natural a escala real (implementado)

### Qué generaba las uniones extrañas

El artefacto visual (durmientes en abanico y franjas cruzando varias vías) lo
producían los propios extremos flexibles cuando se los **estiraba** para cerrar un
empalme:

* el corte de vía era fijo en 120 m (o el largo nominal del flexible) en lugar de
  cortar donde termina el riel del aparato;
* si el puerto quedaba lateral o por detrás del borne, se forzaba una transición
  alargando el flexible hasta el otro extremo del tramo: se midió un flexible de
  **156.94 m con radio de curvatura de 1 m** (y 24 casos de codo lateral);
* las curvas del aparato eran canónicas (5.3° de desvío) mientras la vía real de
  OSM desvía con otro ángulo y con curvatura propia, así que la unión no podía
  ser natural.

### Qué se cambió

1. **Corte natural**: `_calcular_distancia_adaptativa()` corta la vía real en la
   proyección del borne del puerto sobre la curva real (mínimo
   `MARGEN_MINIMO_UNION_M = 1 m`). Ya no hay constantes de 120 m ni largos
   nominales forzados.
2. **Mapeo a escala real**: `recalibrar_aparatos_con_via_real` (activo por
   defecto) hace que cada desvío simple **Tipo A** copie la geometría real:
   `curva_directa` = la vía de paso real muestreada sobre la longitud del
   aparato, `curva_desviada` = la vía desviada real. Los bornes caen sobre las
   vías ⇒ la unión es continua y sin codos, y los extremos flexibles quedan sin
   trabajo (se descartan solos cuando no aportan nada).
3. **Límite de estiramiento**: si aún hace falta una transición, el flexible no
   puede exceder su largo nominal + 8 m (`MARGEN_MAX_EXTENSION_LEAD`). Preferimos
   un hueco chico y honesto antes que una curva deformada.
4. **Reporte**: `_conflictos_adaptacion_switch` registra los puertos que quedan
   por detrás del borne (unión no natural) en vez de deformarlos.

### Resultado medido

`tools/audit_integracion_switches.gd`:

| | Antes (código recibido) | Con corte 120 m | Ahora |
| :-- | :-- | :-- | :-- |
| Leads con ángulo forzado > 60° | 200 / 620 | 3 / 620 | **0 / 620** |
| Extremos con codo (ratio < 0.85) | — | 24 | **1** |
| Peor radio / longitud de flexible | 1 m / 156.94 m | 1 m / 156.94 m | radio 2 m / 8.44 m |
| Tramos visibles | 518 (con 571 en red) | 386 | 412 (con 566 en red) |
| Tramos absorbidos | 50 | 279 | 107 |

### Lo que falta de este eje

La recalibración cubre **Tipo A** (166 de los 239 aparatos del nivel). Los tipos
**B (simétrico), C (cruce), D (escape) y E (tijera)** siguen con geometría
canónica: sus bornes pueden no coincidir con las vías y quedan 16 huecos reales.
Aplicarles el mismo criterio es el siguiente paso (P1 de abajo).

---

## 5b. Optimización: por qué el editor se congelaba al editar

### Diagnóstico medido (`tools/profile_edicion.gd`)

| Operación | Antes | Ahora |
| :-- | :-- | :-- |
| 1 edición de curva de un tramo | **2587 ms** | **73 ms** |
| Eliminar un tramo + re-mallado | 1060 ms | **64 ms** |
| Mover un switch + reintegrar | 1051 ms | **67 ms** |
| `_reconstruir_conexiones_adaptativas()` | 2840 ms | **65 ms** |
| `TrackGeometry.construir_geometria()` (2ª vez) | 1855 ms | **4 ms** |

Desglose del costo original (con el instrumento `debug_tiempos`):

```
TrackNetwork[t]: reconexión 1199 ms (recalibración 1077 ms, conexiones 122 ms)
TrackNetwork[t]: aparatos recalibrados: 47
```

La causa era que **cada** edición reconstruía todo:

1. `_reconstruir_conexiones_adaptativas()` recalibraba los 47 aparatos Tipo A y
   re-ejecutaba `construir_geometria()` de cada uno (malla completa del aparato:
   rieles, durmientes, balasto, corazón, espadines, marmita). Además la
   recalibración **no era idempotente**: `construir_geometria()` recorta
   `largo_turnout` y eso cambiaba la muestra de la vía real en cada pasada, así
   que el caché nunca acertaba.
2. `TrackGeometry.construir_geometria()` llamaba a `limpiar()` y regeneraba las
   566 mallas de tramo, aunque sólo hubiera cambiado una.
3. `FlexibleTrackLead.reconstruir_tramo()` re-mallaba los 614 extremos flexibles
   en cada re-anclaje, aunque su curva no hubiera cambiado.
4. Cada tramo absorbido emitía un `push_warning` **con backtrace** en cada
   reconstrucción: cientos de líneas por edición en el panel de Salida.

### Qué se cambió

1. **Huella por aparato** (`_hash_recalibracion`): la longitud de calibración se
   cuantiza a 0.5 m y se restaura después de construir, así el aparato sólo se
   reconstruye si cambió su geometría real o su pose (0-2 aparatos por edición en
   lugar de 47).
2. **Geometría incremental de vías** (`_cache_tramos` en `TrackGeometry`): cada
   tramo guarda la huella de su curva + rango útil; `construir_geometria()` reusa
   las mallas que no cambiaron y sólo descarta/regenera las que sí.
3. **Extremos flexibles**: `reconstruir_tramo()` compara la curva nueva con la
   actual y no re-malla si no cambió.
4. **Aviso único** por tramo absorbido (`_absorbidos_avisados`).
5. **Re-mallado tras una baja**: eliminar un tramo o un switch ahora dispara
   `construir_geometria()` diferido (incremental), que corrige la geometría de los
   tramos vecinos (antes quedaban recortes obsoletos).

### Costo que queda (no es una edición)

La **primera** carga de la escena sigue costando ~1.5-1.8 s: es la generación
inicial de las 412 mallas de vía (rieles + balasto + durmientes). Si molesta, el
siguiente paso es paralelizarla con `WorkerThreadPool` o repartirla en varios
frames (progresiva por chunks).

---

## 5c. Propuesta de mejora de la integración switch ↔ vías

El principio de diseño propuesto: **el aparato se adapta a la vía real, no al
revés**. Hoy el flujo es mixto: la posición y la orientación se derivan de la
traza, pero las *dimensiones* y el *ángulo de desvío* salen de valores canónicos
(28 m de vía directa, 5.3° de desvío, 34-68 m de escape/tijera).

### P1 — Recalibrar las dimensiones del aparato con la geometría real (mayor impacto)

* **Qué**: al cargar/editar, recalcular por aparato y en este orden:
  1. **Eje de paso** por *least squares* sobre la vía común y la directa
     (hoy se usa una tangente muestreada a 2.5 m, sensible al ruido de OSM).
  2. `largo_aparato` = arco real entre el borne de entrada y el punto donde la
     vía directa deja de coincidir con la recta del aparato.
  3. **Ángulo y geometría de la desviada** desde la vía desviada real
     (`curva_desviada` = Bézier cúbica con tangente `+Z` al inicio y tangente
     real al final), en lugar de la curva canónica de 2.8 m / 28 m.
* **Por qué**: los 179 tramos absorbidos y los 60 huecos restantes provienen casi
  todos de aparatos compuestos (Tipo D/E) cuyas cotas canónicas **no coinciden
  con la separación real entre uniones**: el borne de salida cae por detrás de
  la vía real y el flexible, al no poder avanzar, se descarta (hueco).
* **Efecto esperado**: bajar los absorbidos a ~50-80 y los huecos a <10, sin
  tocar la traza real. Es la única vía para lograrlo, porque absorber traza es
  hoy el precio de la continuidad.
* **Costo**: reescribir el bloque de orientación de `_generar_aparatos_de_via()`
  (Etapas 1-4) para calcular `largo_*`/`angulo` desde `paths` en vez de constantes,
  y un `recalibrar_aparatos()` que se ejecute al abrir la escena (sin regenerar
  los nodos, para no perder las ediciones manuales).

### P2 — Cortes múltiples por tramo (corrección estructural)

`_recortes_segmentos` guarda **un** `Vector2` `[d_inicio, d_fin]` por tramo. Un
tramo con switch en ambos extremos sólo puede expresar un rango, y con tramos
cortos el `_registrar_recorte_segmento()` los colapsa a `Vector2.ZERO`
(absorbido). Cambiar a `seg_id -> Array[Vector2]` (lista de intervalos
excluidos) y que `TrackGeometry` construya una malla por intervalo superviviente
permite:

* dos switches por tramo sin absorber,
* que `_conflictos_adaptacion_switch` (hoy sólo se registra y avisa) se pueda
  **resolver** en vez de descartar geometría.

### P3 — Emparejar puerto ↔ vía por coordenada lateral

Hoy `_seleccionar_lead_para_conexion()` compara distancia al borne + alineación.
En aparatos compuestos (tijeras, escapes en H) los cuatro bornes están a pocos
metros y la asignación puede intercambiar vías (se ve como un flexible que cruza
a la vía paralela). Propuesta: expresar cada puerto como `(junction_id, borne,
dirección)` y emparejar contra `(segment_id, extremo)` usando **el offset lateral
en el sistema del aparato** como criterio principal, con la alineación como
desempate.

### P4 — Una sola función de reintegración (deuda técnica)

Hoy la conexión se calcula en dos lugares que discrepan entre sí:
`_generar_aparatos_de_via()` (Etapas 1-4, que conecta con `conectar_a_via_externa`
a mano) y `_reconstruir_conexiones_adaptativas()` (que las rehace). Cualquier
cambio de criterio hay que hacerlo dos veces, y el resultado final depende de
cuál corrió último. Propuesta: `reintegrar_aparato(sw)` única, idempotente,
llamada desde `_ready()`, `cargar_red()`, `encajar_segmento_con_vecino()` y
`reintegrar_switches_editados()`.

### P5 — Umbrales en el control de calidad

Dejar `tools/audit_integracion_switches.gd` con umbrales y salida distinta de 0
si se superan, para usarlo como *gate*: p. ej. `sin huecos < 10`,
`gap máx < 0.05 m`, `quiebre máx < 3°`, `absorbidos < 20 %`.

---

## 6. Cómo editar y guardar (flujo recomendado)

### Mover un tramo

1. Pulsar `boton_habilitar_edicion_vias` en `TrackNetwork` (los tramos quedan
   seleccionables en el árbol y en el viewport).
2. Seleccionar el `Path3D` y editar puntos/manijas o usar `offset_inicio`,
   `offset_fin`, `tangente_inicio`, `tangente_fin` del Inspector.
3. `boton_guardar` (por tramo) o `boton_guardar_todas_las_ediciones`
   (todo el journal). `boton_resetear` restaura la forma original.

### Mover un switch

1. Seleccionar el nodo del aparato en `TrackNetwork/Switches/...` y moverlo con
   el gizmo.
2. Al soltar, `TrackNetwork` re-ancla automáticamente los extremos flexibles a
   las vías reales (debounce 0.35 s) y actualiza el journal.
3. Guardar la escena (Ctrl+S) para fijar la pose en el `.tscn`.

### Eliminar

* **Tramo**: borrar el `Path3D` en el inspector de escena (la baja se confirma y
  persiste sola) o pulsar `boton_eliminar_tramo`.
* **Switch**: pulsar `boton_eliminar_aparato` en el Inspector del aparato (baja
  persistente) o borrar el nodo del contenedor.
* **Deshacer todas las bajas**: `boton_restaurar_todos_los_tramos` recrea los
  `Path3D` dados de baja desde el JSON base y limpia el journal. Un deshacer
  inmediato del editor (Ctrl+Z) también se respeta: la baja recién se confirma
  `VENTANA_CONFIRMACION_BAJA_MS` (300 ms) después y sólo si el nodo sigue ausente.

### Los dos niveles de persistencia

| Nivel | Archivo | Rol |
| :-- | :-- | :-- |
| Documento de trabajo | `ramal_roca_switches.tscn` | **Fuente de verdad** de qué existe y su geometría |
| Journal de cambios | `red_godot_constitucion_bosques_edits.json` | Permite **regenerar** la red desde el JSON base de OSM respetando ediciones, bajas y poses de switches |

**Qué guarda el journal** (sólo lo que cambió):

| Clave | Contenido |
| :-- | :-- |
| `<seg_id>` | Curva editada del tramo (offsets, tangentes, puntos) |
| `_eliminados` | Tramos eliminados |
| `_switches_eliminados` | Aparatos eliminados |
| `_switches.<node_id>` | Pose (`transform`), estado, largos y tipo del aparato |
| `_switches.<node_id>.extremos.<puerto>` | **Extremos de switch fijados a mano**: `punto_inicio`, `direccion_inicio`, largos, offsets, ángulo, factor y extremo manual |

**El JSON base de OSM nunca se escribe**: `_escribir_archivo_ediciones()` aborta con
error si la ruta destino coincide con `_obtener_ruta_red_json()` o si el archivo
destino tiene forma de red base (`segments` como Array).

### Editar un extremo de switch y que se conserve

1. En el aparato, habilitar *Editable Children* si hace falta para llegar a los
   nodos `ExtremosFlexibles/Extremo_*`.
2. Ajustar el extremo (`punto_fin_manual`, `direccion_fin_manual`,
   `longitud_extension`, `offset_lateral`, `angulo_curva_deg`, …) o usar
   `boton_fijar_extremo` para congelarlo en su pose actual.
3. Tildar `respetar_edicion_manual` (lo hace solo `boton_fijar_extremo`). El
   anclaje automático deja de tocar ese extremo y `boton_guardar[_todas_las_ediciones]`
   lo persiste en el journal; al reabrir se re-aplica. `boton_liberar_extremo`
   devuelve el control al anclaje automático.

Si el journal y la escena discrepan, **gana la escena**; el journal se auto-corrige
al abrir (`_reconciliar_eliminados_con_escena()`).

---

## 7. Limitaciones conocidas al día de hoy

### 7.1 Por qué no se usa el Tipo E (tijera) en la playa de Constitución

El detector de tijeras exige: un centro con 4 ramas donde **cada rama sea la vía
desviada de una unión de 3 ramas** (o sea, un desvío en cada esquina).

En la playa real, la topología OSM es una **cadena de uniones de 4 ramas cuyas
ramas son casi paralelas**. Medido con `tools/probe_tijera.gd` en la unión
`2931298164`:

```
seg_172 dir( 0.12, -0.99)   seg_202 dir(-0.01, -1.00)
seg_173 dir(-0.13,  0.99)   seg_203 dir( 0.04,  1.00)
```

Las cuatro ramas están dentro de ~7° del eje (tramos de 12-29 m, vías separadas
4-5 m): no es una tijera, es un nodo compartido entre dos vías paralelas. Por eso
falla el test estricto (`_detectar_segmento_desviado_union` sólo considera uniones
de 3 ramas) y tampoco lo acepta el test tolerante: no hay "línea de paso +
diagonal", las 4 ramas son paralelas.

Consecuencia: en todo el nivel se detecta **una sola tijera**
(`Tijera_Bretelle_E_9993305211`) y esas zonas caen al *fallback*: cruces (Tipo C) +
escapes (Tipo D) + desvíos (A/B) sobre las mismas vías. Además, un Tipo E único no
puede representar una **escalera de 2-3 bretelles en serie**, que es lo que hay.

**La causa de fondo del trenzado no es la clasificación sino la escala**: los
aparatos canónicos miden 20-28 m (A/B) y 44-88 m (D) mientras que la unión real
siguiente está a **12-29 m**. Aunque se clasifique bien, cualquier aparato más
largo que el tramo se superpone con el vecino. El arreglo de fondo es dimensionar
cada aparato con la distancia real a la unión vecina
(`largo = min(nominal, distancia_real - margen)`) junto con P2 (varios cortes por
tramo).

Herramientas de diagnóstico: `tools/diag_tipos_aparatos.gd` (clasificación y
reconteo tras regenerar) y `tools/probe_tijera.gd` (ramas y direcciones de una
unión puntual).

1. **60 de 537 conexiones** quedan sin geometría de transición (los bornes de
   aparatos compuestos caen detrás de la vía real). Se resuelve con P1.
2. **179 de 569 tramos** se absorben (el flexible ocupa el tramo completo).
   Se resuelve con P1 + P2.
3. Regenerar desde el JSON base produce **212** aparatos contra los **183** de la
   escena: el `.tscn` fue generado con una versión anterior del detector de
   uniones. Conviene regenerar aparatos de forma controlada, no automática.
4. `roca_edit` (journal vacío suelto) es un residuo de haber apuntado
   `ruta_archivo_ediciones` a ese archivo. No se usa y se puede borrar.
