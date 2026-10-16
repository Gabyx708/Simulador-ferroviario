# 🚆 Train Simulator (Godot 4.7)

Simulador ferroviario en tiempo real desarrollado en **Godot Engine 4.7**, enfocado en la física y dinámica de formaciones (CSR Línea Roca), generación procedural de vías e infraestructura ferroviaria, y reconstrucción de trazas a partir de datos reales de OpenStreetMap (OSM).

---

## 📁 Estructura de Carpetas

El proyecto sigue una arquitectura **basada en componentes y dominios co-localizados** (*Feature-based Co-location*), separando recursos crudos, utilidades compartidas, entidades jugables y ensamblado de niveles:

```text
res://
├── addons/                  # Plugins externos (ej. Sky3D)
├── archive/                 # Archivos comprimidos o respaldos fuera del runtime
│
├── assets/                  # Archivos crudos (sin lógica de juego directa)
│   ├── audio/               # Efectos de sonido organizados en snake_case
│   │   ├── tracks/          # Sonidos de juntas, desvíos, rodadura
│   │   └── train/           # Sonidos de tracción, compresor, frenos
│   ├── legacy/              # Archivos de definición heredados (ej. MSTS / OpenBVE .sms)
│   └── models/              # Mallas 3D crudas (.glb) y sus archivos .import
│       ├── constitucion/    # Terminal y entorno de Constitución
│       ├── passengers/      # Modelos de pasajeros y atribución
│       ├── tracks/          # Tramos de vía, postes de catenaria
│       └── train/           # Coches motrices y remolcados
│
├── common/                  # Recursos y utilidades transversales (sin lógica de juego)
│   ├── materials/           # Materiales genéricos reutilizables (.tres)
│   ├── shaders/             # Shaders globales (.gdshader)
│   └── utils/               # Constantes matemáticas y helpers puros
│
├── levels/                  # Escenas de ensamblado de mundo y circuitos
│   ├── ramal_roca_main/     # Escena de inicio del Ramal Roca
│   ├── ramal_roca/          # Variante del nivel Ramal Roca
│   ├── showcase_switches/   # Escena de demostración de switches
│   └── test_track/          # Circuito cerrado de pruebas
│
├── resources/               # Datos del juego (.tres, .res)
│                            # Tablas de aceleración, cronogramas, estaciones
│
├── scenes/                  # Entidades del juego (.tscn y .gd juntos)
│   ├── camera/              # Cámaras (libre, cabina, persecución)
│   ├── tracks/              # Infraestructura (generación de rieles, postes, traza)
│   └── train/               # Formaciones ferroviarias, bogies, simulación física
│
├── systems/                 # Lógica global, reglas de simulación y Autoloads
│                            # Control de tráfico, sistema horario, señalización
│
├── tools/                   # Herramientas, pruebas y auditorías
│   ├── osm/                 # Pipeline Python OSM -> Godot (osm_a_godot.py)
│   └── test_*.gd / audit_*.gd # Pruebas y auditorías headless
│
├── ui/                      # Interfaz de usuario
│   ├── components/          # Widgets reutilizables (velocímetro, tacómetro, reloj)
│   └── screens/             # Menúes y HUD de cabina
│
├── .gitattributes
├── .gitignore               # Configuración de exclusión para Godot 4 + Python
├── icon.svg
└── project.godot
```

---

## 🏛️ Arquitectura del Proyecto

### 1. Co-localización de Escenas y Scripts (`scenes/`)
En Godot, una entidad y su lógica son inseparables. Por ello, **los scripts (`.gd`) y sus escenas (`.tscn`) viven en la misma carpeta**:
- En `scenes/train/` se encuentra `tren.gd` (clase base genérica), `tren_csr.gd` (especialización CSR) y la escena derivada `tren_csr.tscn`.
- En `scenes/tracks/` conviven los scripts generadores (`via_generada.gd`, `postes_catenaria.gd`, `traza_osm.gd`).
- En `scenes/camera/` se encuentra `camara_libre.gd` y `camara_libre.tscn`.
- En `scenes/infrastructure/` se encuentran `estacion.gd` (con `estacion.tscn`) y `poste_parada.gd` (con `poste_parada.tscn`).

### 2. Separación entre Recursos Crudos (`assets/`) y Compartidos (`common/`)
- **`assets/`**: Aloja mallas 3D crudas exportadas de Blender (`.glb`) y audios crudos (`.wav`). Ningún archivo dentro de `assets/` debe tener scripts de lógica de juego atados.
- **`common/`**: Centraliza shaders globales (ej. `SkyMaterial.gdshader`), materiales base (`common/materials/`) y librerías utilitarias.

### 3. Ensamblado de Mundos (`levels/`)
Los niveles son escenas compuestas que heredan de `BaseLevel` (`levels/base_level.gd`) donde se orquestan las entidades: un `Path3D` de la traza, el generador `ViaGenerada`, los postes de catenaria, las estaciones modulares y la formación `TrenCSR`.

---

## Ejecutar el proyecto y validar cambios

- Abrí `project.godot` con **Godot 4.7** (la integración se verificó con Godot 4.7.2) y esperá a que termine la importación inicial de recursos.
- La escena de inicio es `levels/ramal_roca_main/ramal_roca_main.tscn`. Usá **F5** para ejecutar el proyecto; con **F6** podés ejecutar la escena abierta en el editor.
- El nivel principal reúne la red ferroviaria, switches, estaciones, cuatro formaciones CSR, la terminal de Constitución, el HUD y `SimulacionController`. El servicio recorre Constitución → Bosques → Constitución en bucle.
- Conservá los archivos fuente `.glb`, `.png` y sus `.import` al compartir recursos nuevos. `.godot/` es caché local y está ignorado por Git.

### Configurar el recorrido por estaciones

En `ramal_roca_main.tscn`, el nodo `ServicioConstitucionBosques` guarda la secuencia operacional, no el orden visual de las vías. Después de crear cada andén `Estacion`, asignalo a su `Path3D`, ajustá `progreso_en_via` y arrastralo a `paradas` en el Inspector del servicio, en orden Constitución → Bosques. El `TrenCSR` ya está vinculado al servicio.

Al hacer clic sobre una formación, la cámara cambia a una vista cenital y la sigue. `WASD` desplaza el encuadre relativo al tren, `Q/E` acerca o aleja la cámara, `Shift` acelera ese desplazamiento y `C` alterna entre seguimiento cenital y cámara libre; el seguimiento no se pierde al mover el encuadre.

Cada andén es una parada independiente: para vías distintas de ida y vuelta agregá dos estaciones con el mismo `nombre_estacion`. El planificador resuelve el camino por el grafo de `TrackNetwork` y mueve las agujas necesarias. Si un par de paradas debe tomar un itinerario no mínimo, agregá en `overrides_json` una entrada como `{"0>1": ["seg_470", "seg_471"]}`.

Una `Estacion` puede cubrir varias vías paralelas sin duplicar el nodo: ajustá `ancho_cobertura_vias` en el Inspector. El tren proyecta el poste de parada sobre cada vía que atraviesa ese corredor y, si ya circula por una de ellas, frena allí sin buscar el `Path3D` usado como ancla visual de la estación.

En José Mármol, `usar_traza_como_via_ida` fija la parada Constitución → Bosques
en la vía asignada a la estación (`seg_210`), usando su poste de ida para frenar
y embarcar. El desvío posterior `seg_135` y su aparato se eliminaron de la escena
y se registraron como bajas en las ediciones de la red. La salida conserva la
continuidad `seg_210` → `seg_211` → `seg_212` → `seg_694` hacia Rafael Calzada.

En el nivel principal, `separar_vias_por_sentido` hace que cada tren sólo use
vías compatibles con su sentido: cada `Path3D` declara `uso_direccion` (IDA,
VUELTA o uso común). Los destinos de los andenes laterales se asignan al
iniciar según ese lado; los centrales mantienen sus destinos configurados. En
las cabeceras (Constitución y Bosques) bajan todos, embarcan los del sentido
opuesto en el mismo andén y la formación sale marcha atrás, sin maniobra.
`finalizar_al_volver` cierra el servicio después de la última bajada en
Constitución. Si el grafo no tiene una conexión transitable, el tren informa un
recorrido incompleto; no cambia de vía por teletransporte.

El detalle de la elección de vía y andén, las cabeceras, las reservas y las
limitaciones conocidas está en
[docs/circulacion_por_sentido.md](docs/circulacion_por_sentido.md).

### Capacidad de pasajeros por estación

La propiedad `capacidad_maxima_espera` de cada estación fija el máximo de pasajeros
esperando para subir. La cantidad de figuras visibles se regula por separado con
`maximo_pasajeros_visibles`. Cuando ese límite se alcanza, las figuras se reparten
proporcionalmente a las cantidades reales de cada andén.

La capacidad se reparte equitativamente entre los
andenes disponibles, incluidos los centrales. Cada andén conserva su propia
fila de pasajeros: por ejemplo, una estación de 1.200 pasajeros con tres
andenes admite 400 en espera por andén. Si la capacidad no es divisible, los
pasajeros restantes se reparten de a uno para conservar el total.

Cada fila distingue pasajeros a Constitución y a Bosques. El destino de cada
andén se ajusta en «Demanda por destino» del Inspector: por defecto, `AndenA`
sirve a Bosques, `AndenB` a Constitución y los centrales sirven ambos destinos,
compartiendo su capacidad. Un tren toma solo pasajeros de su destino dentro
del andén donde se detiene.
Al habilitar la separación de vías por sentido, el servicio adapta los destinos
de `AndenA` y `AndenB` a su ubicación física. Constitución conserva su único
andén de pasajeros, dedicado al embarque hacia Bosques.

El tren embarca únicamente desde el andén más cercano a la vía por la que
se detiene; el sentido de servicio desempata entre los andenes laterales.
La bajada conserva el contador general de la estación y su visualización
temporal; esos pasajeros no se incorporan a las filas de embarque.
El render refleja las cantidades de cada fila y los totales de la estación
siguen disponibles para el HUD y las estadísticas.

Al hacer clic sobre una estación o su icono «ℹ», se abre una ventana en el HUD
con el mismo fondo oscuro y borde ámbar del panel del tren. Muestra el nombre,
el total en estación (quienes esperan y quienes acaban de bajar), la capacidad,
el histórico y los totales de subida y bajada. La sección «Andenes de abordaje» incluye
una fila `Andén 1: ... pasajeros`, `Andén 2: ... pasajeros`, etc. Se numeran
primero los andenes laterales y después los centrales. Los valores se actualizan
mediante las señales de pasajeros de la estación seleccionada.
Cuando un tren embarca pasajeros, «En espera» cambia a «Abordando» hasta que
termina esa operación.

El botón de estaciones muestra sólo el icono «⌂», conserva su nombre en el tooltip
y está ubicado abajo entre «Métricas» y «Trenes». Abre
un listado desplazable de todas las estaciones del nivel. Cada fila muestra
sus pasajeros actuales (incluidos quienes acaban de bajar) y el estado
«En espera» o «Abordando», actualizado por las mismas señales del panel individual.
Al elegir una fila, el listado se cierra, la cámara libre existente encuadra
los andenes de esa estación y se abre su información. No requiere cámaras
adicionales y funciona también con la simulación pausada.
La vista de estaciones usa la misma `altura_cenital` que la vista del tren
(85 metros por defecto), manteniendo una mirada inclinada hacia los andenes.

El botón «Trenes» reemplaza a «Próximamente» y reúne el listado que antes estaba
en la esquina del HUD. Muestra la cantidad simultánea, la próxima estación de
cada formación, sus pasajeros a bordo y capacidad, destino, estado y puntualidad.
Al elegir «▶ Tren N», el menú se cierra y la cámara y el tablero seleccionan esa
formación. Cada tarjeta tiene su botón «Eliminar», independiente de la selección,
que elimina sólo ese tren mediante `SimulacionController`. El menú conserva
«Agregar tren en Constitución» y muestra la cola de despacho. Se cierra con «✕»
o `Esc`, y sus datos se refrescan también con la simulación pausada.

La ventana de información de la estación ocupa el lugar del panel del tren: seleccionar otra estación cambia
sus datos y seleccionar un tren vuelve a mostrar su tablero. Se cierra con «✕»
o `Esc`. El icono de información permanece visible y reemplaza al antiguo cartel
3D desplegable.
Los paneles de opciones generales y métricas también tienen una cruz para cerrar.
La cruz del tablero del tren oculta su información sin eliminar la formación;
al volver a seleccionarla, el tablero vuelve a aparecer.

Los modelos de pasajeros se reparten entre `AndenA`, `AndenB` y los andenes
centrales habilitados con `cantidad_andenes_centrales`. Se colocan sobre la
superficie real de cada andén, respetando su posición, altura y ajustes
laterales. Al cambiar la geometría se actualizan sus posiciones y el volumen
usado para renderizarlos.
En estaciones integradas a una terminal existente se puede ocultar la estructura
genérica con `mostrar_estructura_andenes`, manteniendo visibles el icono y los
pasajeros. En Plaza Constitución, `desfasaje_vertical_pasajeros_anden_a` y
`ajuste_lateral_pasajeros_anden_a` colocan las figuras del andén A sobre la
plataforma integrada a la terminal sin alterar la parada del tren.

| Estación | Capacidad de pasajeros en espera |
| :------- | ------------------------------: |
| Plaza Constitución | 3.000 |
| Hipólito Yrigoyen | 1.000 |
| Darío Santillán y Maximiliano Kosteki | 2.300 |
| Gerli | 1.200 |
| Lanús | 2.500 |
| Remedios de Escalada | 1.600 |
| Banfield | 1.900 |
| Lomas de Zamora | 2.200 |
| Temperley | 2.400 |
| José Mármol | 1.100 |
| Rafael Calzada | 1.200 |
| Claypole | 1.600 |
| Ingeniero Dante Ardigó | 1.200 |
| Florencio Varela | 1.500 |
| Estanislao S. Zeballos | 1.200 |
| Bosques | 1.400 |

Bosques y Constitución también usan estas capacidades en el nivel alternativo
`levels/ramal_roca/ramal_roca.tscn`.

Gerli tiene dos andenes y admite 600 pasajeros en cada uno. Remedios de Escalada
tiene también un andén central habilitado; sus 1.600 lugares se reparten entre
las tres filas como 534, 533 y 533 pasajeros.

### Demanda por estación y destino

Las 16 estaciones de la tabla usan perfiles `DemandaEstacion` en
`resources/passengers/`, vinculados mediante `demanda_pasajeros`. Los valores
son pasajeros promedio por formación; entre paréntesis se conserva la estimación
diaria proporcionada como referencia.

La demanda se asigna por el destino real del servicio: Constitución → Bosques
usa los valores «a Bosques» y Bosques → Constitución usa «a Constitución».
La orientación de cada Path3D no invierte estos valores.
En las estaciones intermedias, la subida hacia Constitución supera a la subida
hacia Bosques, y la bajada es mayor en los trenes que van hacia Bosques. Los
perfiles de Yrigoyen y Santillán y Kosteki se ajustaron a ese patrón. Constitución
y Bosques conservan sus perfiles de terminal; allí baja toda la formación.

| Estación | Suben a Constitución | Bajan a Constitución | Suben a Bosques | Bajan a Bosques |
| :------- | -------------------: | -------------------: | --------------: | --------------: |
| Plaza Constitución | 10 (500/día) | 1.420 (71.000/día) | 1.420 (71.000/día) | 12 (600/día) |
| Hipólito Yrigoyen | 40 (2.000/día) | 15 (750/día) | 15 (750/día) | 40 (2.000/día) |
| Darío Santillán y Maximiliano Kosteki | 125 (6.200/día) | 90 (4.500/día) | 90 (4.500/día) | 120 (6.000/día) |
| Gerli | 55 (2.750/día) | 15 (750/día) | 18 (900/día) | 55 (2.750/día) |
| Lanús | 240 (12.000/día) | 110 (5.500/día) | 120 (6.000/día) | 240 (12.000/día) |
| Remedios de Escalada | 80 (4.000/día) | 45 (2.250/día) | 50 (2.500/día) | 80 (4.000/día) |
| Banfield | 140 (7.000/día) | 60 (3.000/día) | 65 (3.200/día) | 140 (7.000/día) |
| Lomas de Zamora | 210 (10.500/día) | 80 (4.000/día) | 90 (4.500/día) | 210 (10.500/día) |
| Temperley | 280 (14.000/día) | 130 (6.500/día) | 150 (7.500/día) | 280 (14.000/día) |
| José Mármol | 72 (3.600/día) | 12 (600/día) | 14 (700/día) | 74 (3.700/día) |
| Rafael Calzada | 98 (4.900/día) | 10 (500/día) | 12 (600/día) | 100 (5.000/día) |
| Claypole | 220 (11.000/día) | 30 (1.500/día) | 35 (1.800/día) | 225 (11.300/día) |
| Ingeniero Dante Ardigó | 105 (5.200/día) | 6 (300/día) | 8 (400/día) | 105 (5.300/día) |
| Florencio Varela | 270 (13.500/día) | 24 (1.200/día) | 28 (1.400/día) | 270 (13.700/día) |
| Estanislao S. Zeballos | 95 (4.800/día) | 6 (300/día) | 8 (400/día) | 95 (4.900/día) |
| Bosques | 130 (6.500/día) | 8 (400/día) | 10 (500/día) | 130 (6.600/día) |

La simulación usa una variación aleatoria de ±15 % alrededor de los promedios,
redondeada a pasajeros enteros. La generación continua usa un intervalo de
referencia de **24 segundos de simulación**, que reduce a la mitad la generación
actual; se puede editar junto con la variación en cada perfil. Las estaciones
sin perfil usan una tasa base de 0,375 en lugar de 0,75 pasajeros por segundo.
La tasa de cada destino se reparte entre los andenes que lo sirven. Los
andenes completos dejan de generar. Los promedios de subida regulan únicamente
la generación de pasajeros: al llegar un tren suben todos los que esperan en
su andén y destino, hasta completar la capacidad libre de la formación.
Si hace falta, la parada se prolonga hasta terminar ese embarque. Los pasajeros
que no entran en el tren permanecen en su fila para la próxima formación.

La bajada intermedia usa el promedio del destino correspondiente, limitado por
los pasajeros a bordo. En ambas terminales bajan todos; en Bosques se embarca
la nueva fila hacia Constitución después de la maniobra de regreso.
El tren conserva a los pasajeros embarcados en su contador `pasajeros_actuales`
hasta que desciendan en una parada. La capacidad actual de la formación es 500.
Las cuatro formaciones del nivel principal heredan la configuración de pasajeros
de `Tren`: 500 lugares, tandas de 6 e intervalo base de 0,15 segundos, ajustado
al tiempo disponible en cada parada.
Las estaciones sin perfil conservan el porcentaje de bajada anterior.

### Métricas globales, espera y puntualidad

El panel «Métricas» conserva la comparación de eventos, el retraso acumulado,
su evolución y la tabla por evento. Además muestra:

- Pasajeros transportados: total de embarques; «En viaje» cuenta pasajeros a
  bordo de servicios activos y, debajo, «Completados» cuenta a quienes ya
  descendieron. Los pasajeros en trenes incompletos se muestran aparte.
- Un único contador de recorridos finalizados: salir de una terminal, llegar
  a la otra y regresar al origen. Llegar sólo a la terminal opuesta no suma.
  Los incompletos por evento terminal se distinguen de errores de ruta y los
  resultados se conservan si una formación se elimina.
- Trenes simultáneos actuales y máximo histórico. El menú «Trenes» de la
  navegación inferior muestra también la cantidad actual y la puntualidad de cada formación.
- Espera global: sólo el tiempo de espera actual, calculado como el promedio de
  las esperas actuales de todas las estaciones. Cada estación tiene el mismo
  peso; las que no tienen pasajeros en espera aportan cero.
- Espera por estación: un menú `OptionButton` con el mismo diseño que los
  selectores de fallas. Al elegir una estación aparecen debajo su espera actual,
  los pasajeros esperando y la espera media hasta abordar. Se usan colas FIFO
  independientes por andén y destino, sin atribuir espera a quienes acaban de bajar.
- Tasa de demora: porcentaje de servicios activos atrasados respecto de su
  horario y demora media, incluyendo cero para quienes están en tiempo.

En «Horario previsto» del servicio, `tiempos_tramos_ida_s` y
`tiempos_tramos_vuelta_s` permiten fijar segundos de marcha por cada par de
estaciones, en orden Constitución → Bosques (la vuelta usa el mismo índice de
tramo en sentido inverso). Sin valores, el tiempo se **estima** con la distancia
entre estaciones, una velocidad de referencia de 50 km/h y un factor 1,123.
Se agregan las paradas nominales de cada formación, su demora inicial programada
y los 30 segundos de referencia de la maniobra terminal, todos configurables.
La estimación geométrica puede ajustarse con tiempos de tramo explícitos para
calibrar el horario a la traza y la maniobra reales.

`MetricasServicio` copia ese horario al dar de alta cada tren; los eventos y
los cambios posteriores de velocidad no desplazan sus llegadas previstas.
El menú «Horario previsto y llegadas por tren» reúne también la información
que antes aparecía en «Por tren» y usa el mismo diseño que los selectores de fallas.
Al elegir una formación aparecen debajo su estado, destino, próxima estación,
pasajeros, retraso acumulado, puntualidad, tiempo total previsto, tiempo
transcurrido y todas las llegadas de ambos sentidos. Los detalles usan una fuente
de 14 puntos. Ambos menús conservan la selección y sólo reconstruyen sus opciones
cuando cambia el listado, manteniendo el menú abierto durante los refrescos.
Los tiempos de llegada se
expresan en minutos:segundos desde el inicio del recorrido. Un tren queda
«Atrasado» si supera la llegada prevista; conserva ese estado hasta que
una llegada posterior lo deje nuevamente «En tiempo». La comparación vuelve
a cero al completar cada viaje entre cabeceras: al llegar a Bosques para
iniciar la vuelta, y al llegar a Constitución para iniciar una nueva ida.
También se detecta una próxima llegada vencida mientras sigue viajando. La
tolerancia independiente `tolerancia_horario_s` del controlador es de un
segundo por defecto.
Este estado puede recuperar puntualidad; el retraso acumulado usado para
atribuir el impacto de los eventos se conserva por separado.

### Pruebas headless

Al pedirle pruebas a un agente, incluí siempre la ruta exacta del ejecutable de
Godot; no asumas que está disponible en el `PATH`. En este equipo:

```text
F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe
```

Ejecutá desde la raíz del repositorio:

```powershell
# Carga rápida de la escena de inicio
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --quit-after 150

# Servicio, estados y terminal
# Las pruebas históricas de solo ida requieren configurar solo_ida = true
# y finalizar_al_volver = false; el nivel principal ahora opera ida y vuelta.
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_recorrido_completo.gd
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_finalizacion_bosques.gd
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_ruta_invalida_ida.gd

# Controlador, comandos, HUD y velocidad operativa
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_simulacion_controller.gd
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_comandos_simulacion.gd
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_hud_velocidad_simulacion.gd
& 'F:\descargas\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_velocidad_operativa.gd

```

`test_servicio_ferroviario.gd` conserva una limitación geométrica conocida:
Plaza Constitución no resuelve un candidato para `PosteParadaIda`. No usarlo
como criterio de aceptación hasta revisar esa geometría.

---

## 📜 Guía de Programación y Buenas Prácticas (Godot 4.7 / GDScript)

### 1. Nomenclatura Estándar
| Tipo                                      | Convención                  | Ejemplo                                    |
| :---------------------------------------- | :-------------------------- | :----------------------------------------- |
| Carpetas                                  | `snake_case`                | `assets/audio/tracks/`, `scenes/train/`    |
| Archivos (`.gd`, `.tscn`, `.glb`, `.wav`) | `snake_case` en minúsculas  | `tren.gd`, `tren_csr.gd`, `junta_55.wav`   |
| Clases globales                           | `PascalCase`                | `class_name Tren`, `class_name TrenCSR`    |
| Nodos en el Árbol de Escena               | `PascalCase`                | `Path3D`, `TrenCSR`, `CamaraLibre`         |
| Constantes                                | `CONSTANT_CASE`             | `RADIO_RUEDA`, `SEMI_BOGIE`, `PASO`        |
| Variables y Funciones                     | `snake_case`                | `velocidad_max_kmh`, `velocidad_actual()`  |
| Variables y métodos privados/internos     | `_snake_case` (prefijo `_`) | `_avance`, `_cuerpos`, `_construir()`      |
| Señales                                   | `snake_case` en pasado      | `estacion_alcanzada`, `velocidad_cambiada` |

> [!WARNING]
> **Sensibilidad a mayúsculas/minúsculas**: Nunca uses nombres de archivo en mayúsculas (como `SOUND` o `Frenos.WAV`). Windows es insensible a mayúsculas, pero Linux, macOS y plataformas de exportación son sensibles; las diferencias causan dependencias rotas al exportar o ejecutar en otros sistemas.

---

### 2. Tipado Estático Obligatorio
Aprovechá las optimizaciones del compilador y el autocompletado de Godot 4 usando tipado estático estricto:

```gdscript
# BIEN: Tipado inferido cuando el tipo es explícito
var velocidad : float = 30.0
var coches: Array = []

# BIEN: Parámetros y retornos con tipo definido
func progreso_mas_cercano(punto: Vector3, paso: float = 2.0) -> float:
	var mejor_distancia := INF
	return mejor_distancia

```

---

### 3. Carga de Recursos y `@export` Resiliente
**Nunca uses cadenas de texto hardcodeadas dentro de `load()` en métodos como `_ready()`:**

```gdscript
# MAL: Si se mueve el modelo o se renombra la carpeta, falla en tiempo de ejecución
var modelo = load("res://csr_roca_coche_motriz.glb")

# BIEN: Usa @export con preload() por defecto
@export_group("Modelos")
@export var escena_coche_motriz: PackedScene = preload("res://assets/models/train/csr_roca_coche_motriz.glb")
@export var escena_coche_remolcado: PackedScene = preload("res://assets/models/train/csr_roca_coche_remolcado.glb")
```
*Ventajas:*
- Si la ruta se rompe, Godot te avisa en tiempo de compilación.
- El modelo se puede intercambiar directamente arrastrándolo en el Inspector sin tocar una sola línea de código.

---

### 4. Buenas Prácticas en Scripts `@tool` (Generación Procedural)
Los scripts como `via_generada.gd` y `postes_catenaria.gd` se ejecutan en el editor (`@tool`) para construir mallas y postes sobre la traza en tiempo real.

> [!CAUTION]
> **Evitar inflar escenas (`.tscn`)**:
> Si a un nodo generado proceduralmente por un script `@tool` le asignás:
> ```gdscript
> nodo.owner = get_tree().edited_scene_root # ¡CUIDADO!
> ```
> Godot serializará cada vértice de la malla en el archivo `.tscn` como un arreglo de bytes gigantesco, haciendo que la escena pese 10 MB o más de texto plano.
> 
> **Regla:** Los nodos autogenerados solo deben ser hijos (`add_child()`). No les asignes `owner` a menos que sea estrictamente necesario que queden guardados como parte de la escena estática.

---

### 5. Convenciones de Coordenadas y Física
- **Unidades:** Sistema métrico internacional (distancias en metros, masas en kg, velocidades internas en m/s, aceleración en m/s²). Para la interfaz de usuario convertir a km/h (`vel * 3.6`).
- **Orientación 3D en Godot:**
  - `-Z` hacia adelante (*Forward*).
  - `+Y` hacia arriba (*Up*).
  - `+X` hacia la derecha (*Right*).
- **Proyección OpenStreetMap:**
  - `+X` corresponde al Este.
  - `-Z` corresponde al Norte.
  - El plano vertical está en `Y = 0` (cota del terreno).

---

## 🛠️ Herramientas Externas (Pipeline OSM)

Para importar trazas reales de OpenStreetMap:
1. Instalar dependencias de Python:
   ```bash
   pip install -r tools/osm/requirements.txt
   ```
2. Ejecutar la conversión sobre un extracto `.osm`:
   ```bash
   python tools/osm/osm_a_godot.py mapa.osm --salida ./salida --ferrocarril Roca
   ```
3. Conservar el extracto OSM original junto con la salida generada para poder
   repetir la conversión.
