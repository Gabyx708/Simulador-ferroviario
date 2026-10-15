# Circulación por sentido, cabeceras y reservas

Estado del sistema en el commit `b826b58` (rama `feature/mejoras-generales`).
Describe cómo los trenes eligen vía, andén y ruta en el nivel
`ramal_roca_main`, cómo se reservan los recursos para evitar choques y qué
configuración de la escena depende de esto.

Código involucrado: `scenes/train/tren.gd`, `scenes/tracks/track_network.gd`,
`scenes/tracks/editable_track_segment.gd`, `scenes/infrastructure/estacion.gd`
y `scenes/services/servicio_ferroviario.gd`.

## 1. Sentido de cada vía

Cada `Path3D` de la red (`EditableTrackSegment`) tiene `uso_direccion`:

| Valor | Uso | Color de depuración |
| --- | --- | --- |
| `IDA` (0, por defecto) | Constitución → Bosques | verde |
| `VUELTA` (1) | Bosques → Constitución | celeste |
| `USO_COMUN` (2) | ambos sentidos | amarillo |

Un tramo sin la línea `uso_direccion` en la escena es **IDA**. Los tramos
nuevos nacen así: hay que revisarlos cuando se agregan sobre una vía de vuelta
(fue el caso de `seg_763`, `seg_764` y `seg_152`).

El nodo `ServicioConstitucionBosques` tiene `separar_vias_por_sentido = true`:
cada tren sólo planifica y recorre vías compatibles con su sentido operativo
(`es_sentido_ida()` en el tren). El servicio repite ida y vuelta en bucle.

## 2. Grafo de ruteo

`TrackNetwork` arma el grafo a partir de la topología del JSON base, los
aparatos de vía de la escena y estas dos correcciones al cargar:

- **Ramas de aparatos eliminadas** (`_reasignar_ramas_eliminadas_de_switches`):
  si un aparato nombra una rama cuyo `Path3D` ya no existe, adopta el tramo
  cuyo extremo quedó suelto junto al aparato. Caso real: `seg_74` → `seg_75`
  en `Desvio_B_11811730945` (Rafael Calzada).
- **Empalmes dibujados en la escena** (`_integrar_empalmes_de_escena`): dos
  extremos de `Path3D` a menos de 1 m que continúan uno en el otro se unen
  aunque el JSON no los conozca (por ejemplo `seg_327` ↔ `seg_125`). Se guardan
  aparte de las uniones del JSON: sólo los usa el ruteo y no alteran los
  recortes de los aparatos.

`planificar_ruta` aplica dos reglas al recorrer el grafo:

- **Sentido**: no entra a una vía incompatible con el sentido del tren. La vía
  de origen se exceptúa sólo cuando se indica (`permitir_origen_terminal`).
- **Rama → rama prohibido** (`_es_paso_entre_ramas`): en un desvío sólo se
  circula entre la vía común y una rama. Pasar de la directa a la desviada es un
  retroceso físico (caso real: llegar por `seg_308` y volver por `seg_496`).

## 3. Elección de andén en estaciones intermedias

1. **Candidatos por poste** (`Estacion.obtener_puntos_parada_multivia`): se
   proyecta el poste del sentido sobre cada vía paralela al andén. Entra la vía
   que está a menos de `ancho_cobertura_vias / 2` del centro y a menos de
   `ancho_cobertura_vias / 2 + 3` m del poste. Después se descartan las vías
   de sentido incompatible.
2. **Continuidad**: en ida, el andén debe permitir seguir hasta Bosques; en
   vuelta, debe alcanzar algún andén de la parada siguiente
   (`_candidatos_con_continuidad_terminal`). Así no se elige un andén paralelo
   cuya vía no sigue hacia la próxima estación.
3. **Elección** (`_mejor_ruta_a_candidatos_desde`): menos agujas y, a igualdad,
   menos metros. Un andén con otra formación suma 300 m
   (`PENALIZACION_ANDEN_OCUPADO_M`): desempata andenes paralelos sin justificar
   rodeos.
4. **Sin ruta hacia adelante**: se prueba invertir el sentido local sólo como
   ajuste corto en el andén. Se descarta si la ruta mide más del doble de la
   distancia real al andén más 500 m (evita "ida y vuelta" de kilómetros).

En Lanús y Gerli hay dos vías de vuelta por estación y cada línea de vuelta
sigue por su propia vía sin cruces (`seg_480 → seg_481 → seg_482` y
`seg_316 → seg_314 → seg_8`). Por eso ambas estaciones tienen
`ancho_cobertura_vias = 47`: con el valor por defecto (35) no reconocían
`seg_314` ni `seg_482` como andén.

## 4. Cabeceras: invertir la marcha en el andén

En Constitución y en Bosques no hay maniobra: el tren llega a un andén, bajan
todos, embarcan los del sentido opuesto en ese mismo andén y sale marcha atrás
(`_invierte_en_anden_de_cabecera`, `_invertir_marcha_en_el_lugar`).

- Al invertir, el último coche pasa a ser la cabecera; la formación no se mueve.
- La primera salida de las formaciones iniciales de Constitución no invierte:
  ya miran hacia Yrigoyen.
- La vía del andén donde se invirtió puede recorrerse en el sentido nuevo hasta
  salir de ella (`_salida_cabecera_traza`).

**Andenes en vía muerta** (`_candidatos_andenes_tope`). En las cabeceras
también son paradas todas las vías con un extremo sin salida cerca de la
estación, si su sentido coincide con el del tren. El punto de parada es:

1. Si la estación tiene formaciones colocadas en la escena: donde, después de
   invertir, la nueva cabecera queda a la misma distancia del tope que esas
   formaciones (≈160 m en Constitución).
2. Si no: el `Marker3D` de `MarcadoresDeInstancia` que está sobre esa vía
   (a menos de 2 m).
3. Si tampoco hay marcador: 12 m antes del tope.

Entre andenes en vía muerta, uno ocupado (con un tren encima o reservado) se
descarta mientras haya otro libre.

### Playa de Constitución

| Andenes de vuelta (VUELTA) | Andenes de ida (IDA) |
| --- | --- |
| `seg_186`, `seg_466`, `seg_468`, `seg_472`, `seg_474`, `seg_161` | `seg_591`, `seg_589`, `seg_587`, `seg_585`, `seg_583`, `seg_622` |

Para salir de ida desde un andén de vuelta, sus accesos están en
`USO_COMUN`: `seg_621`, `476`, `451`, `592`, `463`, `424`, `590`, `181`,
`182`, `183`, `331`, `390`, `588`, `438`, `439`, `555`, `586`, `343`, `584`
y `179`.

### Bosques

Sólo `seg_617` es alcanzable como andén de llegada de ida; `seg_241` no tiene
camino. Se sale marcha atrás por `seg_16 → seg_15 → seg_248 → seg_247 →
seg_616` (los cuatro primeros, de uso común).

## 5. Reservas y separación entre trenes

**Recursos exclusivos** (`TrackNetwork.solicitar_reserva_seccion`):

- **Agujas**: sólo se reserva la aguja de una unión con desvío
  (`_nodo_tiene_aguja`). Se libera cuando la cola pasa la unión.
- **Vías de uso común y andenes en vía muerta** (`es_via_exclusiva`): se
  reservan en bloque con los tramos del mismo tipo que siguen en el itinerario
  (`_bloque_exclusivo_tras`). Cada uno se libera cuando la cola sale de él
  (`liberar_via_al_salir`). Así un tren no entra a una vía compartida mientras
  otro la usa, ni queda detenido adentro esperando un andén ocupado.
- **Andén inicial**: las formaciones de la escena reservan su vía de salida en
  Constitución (`reservar_tramo_inicial`).

Las vías IDA o VUELTA comunes, por largas que sean, no se reservan: la
separación la resuelve la detección de conflictos del tren
(`_detectar_conflicto_proximo`), que mide la distancia real al tren de adelante
en la misma vía y en la vía siguiente y frena con su distancia de frenado más
un margen.

**Cola de solicitudes** (`_adquirir_recursos_fifo`): se atienden por orden de
llegada, con dos excepciones para evitar bloqueos mutuos:

- un recurso que ya es del tren que lo pide no se cede a los que esperan;
- no se espera a una solicitud anterior que necesita algo que tiene el tren
  actual.

**Limpieza** (`depurar_reservas_tren`): al fijar una ruta nueva, el tren suelta
las vías exclusivas que había reservado y no va a recorrer, y su solicitud
pendiente.

El mecanismo que corría de costado a un tren que estorbaba más de 30 s
(`apartar_de_via_para_ceder_paso`) ya no se dispara: lo dejaba encima de la vía
paralela del sentido contrario. La función se conserva porque la usa
`tools/test_filtro_vias.gd`.

## 6. Limitaciones conocidas

- **Esperas en la salida de Constitución.** Una vía de uso común se reserva
  para un solo tren, aunque los demás vayan en el mismo sentido. Las salidas de
  la playa comparten cadenas de vías comunes (por ejemplo
  `seg_668 → 366 → 423 → 389 → 388 → 387 → 386`), así que las formaciones salen
  de a una y acumulan atraso. Propuesta pendiente: permitir varios trenes del
  mismo sentido en una vía común y bloquear sólo al sentido contrario.
- **Sólo 3 de los 6 andenes de vuelta reciben trenes.** `seg_472`, `seg_474` y
  `seg_161` son inalcanzables en vuelta: el camino cruza `seg_575` (y además
  `seg_93`, o `seg_416` y `seg_458`), que están en IDA. Ponerlos en uso común
  los habilita pero alarga las cadenas del punto anterior.
- **Punto de parada en Constitución.** Con formaciones iniciales en la escena,
  el tren de vuelta frena a mitad del andén para quedar, al invertir, a la
  altura de esas formaciones; no llega a los marcadores.
- **Bosques tiene un único andén de llegada** (`seg_617`): los trenes que
  llegan esperan antes de `seg_15` mientras el anterior invierte y sale.

## 7. Diagnóstico

- Al acercarse a una estación, el tren imprime la ruta elegida:
  `Ruta [aproximacion]: estacion=… candidato=seg_X agujas=N …`.
- `tools/diag_tren_atascado.gd` registra el estado de la flota en una corrida
  acelerada sin ventana.
- Cada vez que se cambia el sentido de un tramo en la escena, conviene
  actualizar también `uso_direccion` del mismo tramo en
  `tramo_completo_constitucion_bosques/red_godot_constitucion_bosques_edits.json`,
  para que una regeneración de la red desde el JSON no lo revierta.
