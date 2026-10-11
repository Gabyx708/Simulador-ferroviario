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
- El nivel principal reúne la red ferroviaria, switches, estaciones, cuatro formaciones CSR, la terminal de Constitución, el HUD y `SimulacionController`. El servicio actual opera exclusivamente Constitución → Bosques y finaliza en Bosques.
- Conservá los archivos fuente `.glb`, `.png` y sus `.import` al compartir recursos nuevos. `.godot/` es caché local y está ignorado por Git.

### Configurar el recorrido por estaciones

En `ramal_roca_main.tscn`, el nodo `ServicioConstitucionBosques` guarda la secuencia operacional, no el orden visual de las vías. Después de crear cada andén `Estacion`, asignalo a su `Path3D`, ajustá `progreso_en_via` y arrastralo a `paradas` en el Inspector del servicio, en orden Constitución → Bosques. El `TrenCSR` ya está vinculado al servicio.

Al hacer clic sobre una formación, la cámara cambia a una vista cenital y la sigue. `WASD` desplaza el encuadre relativo al tren, `Q/E` acerca o aleja la cámara, `Shift` acelera ese desplazamiento y `C` alterna entre seguimiento cenital y cámara libre; el seguimiento no se pierde al mover el encuadre.

Cada andén es una parada independiente: para vías distintas de ida y vuelta agregá dos estaciones con el mismo `nombre_estacion`. El planificador resuelve el camino por el grafo de `TrackNetwork` y mueve las agujas necesarias. Si un par de paradas debe tomar un itinerario no mínimo, agregá en `overrides_json` una entrada como `{"0>1": ["seg_470", "seg_471"]}`.

Una `Estacion` puede cubrir varias vías paralelas sin duplicar el nodo: ajustá `ancho_cobertura_vias` en el Inspector. El tren proyecta el poste de parada sobre cada vía que atraviesa ese corredor y, si ya circula por una de ellas, frena allí sin buscar el `Path3D` usado como ancla visual de la estación.

### Pruebas headless

Al pedirle pruebas a un agente, incluí siempre la ruta exacta del ejecutable de
Godot; no asumas que está disponible en el `PATH`. En este equipo:

```text
C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe
```

Ejecutá desde la raíz del repositorio:

```powershell
# Carga rápida de la escena de inicio
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --quit-after 150

# Servicio, estados y terminal
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_recorrido_completo.gd
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_finalizacion_bosques.gd
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_ruta_invalida_ida.gd

# Controlador, comandos, HUD y velocidad operativa
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_simulacion_controller.gd
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_comandos_simulacion.gd
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_hud_velocidad_simulacion.gd
& 'C:\Program Files (x86)\Godot\Oficial\Godot4\GD\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/test_velocidad_operativa.gd

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
