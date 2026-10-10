@tool
extends Node3D
class_name TrackNetwork
## Administrador y generador de red ferroviaria basado en grafos (TrackNetwork).
##
## Carga cualquier archivo JSON de red topológica (ej. red_godot.json) con segmentos y
## uniones (junctions/switches). Detecta geométricamente los desvíos (Vía Común, Vía Directa,
## Vía Desviada, Lado Izquierda/Derecha y Ángulo de divergencia real) y conecta los estados
## de ruteo para trenes y agujas móviles.
##
## Compatible con Godot 4.x / 4.7 con tipado estático estricto.
const TURNOUT_TIPO_A_SCRIPT = preload("res://scenes/procedural_track/procedural_turnout.gd")
const TURNOUT_TIPO_B_SCRIPT = preload("res://scenes/procedural_track/procedural_symmetrical_turnout.gd")
const TURNOUT_TIPO_C_SCRIPT = preload("res://scenes/procedural_track/procedural_crossing.gd")
const TURNOUT_TIPO_D_SCRIPT = preload("res://scenes/procedural_track/procedural_crossover.gd")
const TURNOUT_TIPO_E_SCRIPT = preload("res://scenes/procedural_track/procedural_scissors_crossover.gd")
const SWITCH_TIPO_A_SCENE = preload("res://scenes/switches/switch_tipo_a.tscn")
const SWITCH_TIPO_B_SCENE = preload("res://scenes/switches/switch_tipo_b.tscn")
const SWITCH_TIPO_C_SCENE = preload("res://scenes/switches/switch_tipo_c.tscn")
const SWITCH_TIPO_D_SCENE = preload("res://scenes/switches/switch_tipo_d.tscn")
const SWITCH_TIPO_E_SCENE = preload("res://scenes/switches/switch_tipo_e.tscn")
const EDITABLE_TRACK_SEGMENT_SCRIPT = preload("res://scenes/tracks/editable_track_segment.gd")
const DISTANCIA_MINIMA_ADAPTACION_SWITCH: float = 120.0
const MARGEN_FINAL_SEGMENTO_SWITCH: float = 2.0
const PASO_BUSQUEDA_ADAPTACION_SWITCH: float = 10.0
const DOT_TANGENTE_ADAPTACION_SWITCH: float = 0.985
signal red_cargada(total_segmentos: int, total_uniones: int)
signal switch_conmutado(nodo_id: int, segmento_destino: String)
signal switch_movido(nodo_id: int, desviada: bool, segmento_activo: String)

# Caché en memoria universal para evitar re-lecturas constantes de disco
static var _json_cache: Dictionary = {}

@export_group("Origen de Datos")
## Ruta al archivo JSON con los segmentos y uniones de cualquier red.
@export_file("*.json") var json_path: String = "res://tramo_completo_constitucion_bosques/red_godot_constitucion_bosques.json":
	set(v):
		if json_path == v:
			return
		json_path = v
		if is_inside_tree() or not paths.is_empty():
			cargar_red()

## Intervalo métrico de muestreo para la interpolación de Curve3D.
@export_range(0.5, 50.0, 0.5) var bake_interval: float = 2.0:
	set(v):
		var nuevo: float = maxf(0.1, v)
		if is_equal_approx(bake_interval, nuevo):
			return
		bake_interval = nuevo
		_actualizar_bake_intervals()

## Factor de curvatura suave Catmull-Rom para eliminar esquinas y quiebres duros.
@export_range(0.0, 0.5, 0.01) var factor_suavizado: float = 0.25:
	set(v):
		var nuevo: float = clampf(v, 0.0, 0.5)
		if is_equal_approx(factor_suavizado, nuevo):
			return
		factor_suavizado = nuevo
		if is_inside_tree() or not paths.is_empty():
			cargar_red()

@export_group("Organización y Tramos en Escena")
## Organiza los tramos (Path3D) dentro de nodos jerárquicos Node3D por Sector y Estación en el árbol de escena.
@export var organizar_en_nodos_tramos: bool = true:
	set(v):
		if organizar_en_nodos_tramos == v:
			return
		organizar_en_nodos_tramos = v
		if is_inside_tree() or not paths.is_empty():
			cargar_red()

## Si está activo, limita la red estrictamente al verdadero corredor Constitución - Bosques (vía Temperley).
## Descarta automáticamente la Vía Quilmes, colas hacia Gutiérrez/Korn y ramales secundarios.
@export var solo_constitucion_bosques: bool = true:
	set(v):
		if solo_constitucion_bosques == v:
			return
		solo_constitucion_bosques = v
		if solo_constitucion_bosques:
			filtro_ramal = 0
		else:
			filtro_ramal = 1
		if is_inside_tree() or not paths.is_empty():
			cargar_red()

## Pulsador: Forzar recarga inmediata de la red desde el archivo JSON base.
@export var boton_recargar_red: bool = false:
	set(v):
		if v:
			boton_recargar_red = false
			_json_cache.clear()
			tramos_excluidos = PackedStringArray()
			_ediciones_guardadas = cargar_ediciones_guardadas()
			_ediciones_guardadas["_eliminados"] = []
			_escribir_archivo_ediciones()
			mostrar_en_arbol_editor = true
			generar_mecanismos_visuales = true
			cargar_red()

## Pulsador: Purgar y eliminar inmediatamente del árbol de escena cualquier tramo ajeno a Constitución - Bosques.
@export var boton_purgar_tramos_ajenos: bool = false:
	set(v):
		if v:
			boton_purgar_tramos_ajenos = false
			purgar_tramos_ajenos()

## Pulsador: Sincronizar 'paths' inspeccionando todos los nodos Path3D hijos en el árbol (útil si borraste tramos a mano).
@export var boton_sincronizar_desde_arbol: bool = false:
	set(v):
		if v:
			boton_sincronizar_desde_arbol = false
			recolectar_paths_desde_arbol()

@export_group("Filtrado de Ramales y Tramos")
## Filtro por ramal predefinido para aislar o eliminar secciones de la red.
@export_enum(
	"Constitución - Bosques (Vía Temperley - Oficial)",
	"Toda la Red (Incluye Vía Quilmes y Ramales)",
	"Rango Métrico Personalizado"
) var filtro_ramal: int = 0:
	set(v):
		if filtro_ramal == v:
			return
		filtro_ramal = v
		if filtro_ramal == 0:
			solo_constitucion_bosques = true
		elif filtro_ramal == 1:
			solo_constitucion_bosques = false
		if is_inside_tree() or not paths.is_empty():
			cargar_red()

## Coordenada Z mínima en metros (activo con Rango Métrico Personalizado).
@export var rango_z_min: float = 0.0:
	set(v):
		if is_equal_approx(rango_z_min, v):
			return
		rango_z_min = v
		if (is_inside_tree() or not paths.is_empty()) and filtro_ramal == 2:
			cargar_red()

## Coordenada Z máxima en metros (activo con Rango Métrico Personalizado).
@export var rango_z_max: float = 25000.0:
	set(v):
		if is_equal_approx(rango_z_max, v):
			return
		rango_z_max = v
		if (is_inside_tree() or not paths.is_empty()) and filtro_ramal == 2:
			cargar_red()

## Coordenada X mínima en metros (activo con Rango Métrico Personalizado).
@export var rango_x_min: float = -3000.0:
	set(v):
		if is_equal_approx(rango_x_min, v):
			return
		rango_x_min = v
		if (is_inside_tree() or not paths.is_empty()) and filtro_ramal == 2:
			cargar_red()

## Coordenada X máxima en metros (activo con Rango Métrico Personalizado).
@export var rango_x_max: float = 20000.0:
	set(v):
		if is_equal_approx(rango_x_max, v):
			return
		rango_x_max = v
		if (is_inside_tree() or not paths.is_empty()) and filtro_ramal == 2:
			cargar_red()

## Identificador del tramo individual a excluir de la red (ej. 'seg_4', 'seg_316').
@export var tramo_a_excluir: String = ""

## Pulsador: Excluir/Eliminar el tramo especificado en 'tramo_a_excluir'.
@export var boton_excluir_tramo: bool = false:
	set(v):
		if v:
			boton_excluir_tramo = false
			_excluir_tramo_manual()

## Pulsador: Restaurar todos los tramos eliminados de la red.
## Recrea los Path3D dados de baja (exclusiones y journal) desde la topología base,
## limpia los registros de bajas y reescribe el journal.
@export var boton_restaurar_todos_los_tramos: bool = false:
	set(v):
		if v:
			boton_restaurar_todos_los_tramos = false
			tramo_a_excluir = ""
			restaurar_tramos_eliminados()

## Lista de IDs de tramos excluidos o eliminados de la red.
@export var tramos_excluidos: PackedStringArray = []:
	set(v):
		tramos_excluidos = v
		if is_inside_tree() or not paths.is_empty():
			if _tiene_vias_en_arbol():
				_purgar_tramos_excluidos_del_arbol()
			else:
				cargar_red()

@export_group("Control de Cambios de Vía (Switches)")
## Si está activo, instancia los aparatos de vía visuales en el contenedor $Switches.
@export var generar_mecanismos_visuales: bool = true:
	set(v):
		if generar_mecanismos_visuales == v:
			return
		generar_mecanismos_visuales = v
		if is_inside_tree():
			if _tiene_vias_en_arbol():
				if generar_mecanismos_visuales:
					generar_switches_desde_paths_existentes()
				else:
					limpiar_switches()
			else:
				cargar_red()

## Pulsador: Generar switches adaptados sobre los tramos Path3D existentes en la escena (no desde el JSON estático).
@export var boton_generar_switches: bool = false:
	set(v):
		if v:
			boton_generar_switches = false
			generar_switches_desde_paths_existentes()

## Pulsador: Limpiar todos los switches de la escena.
@export var boton_limpiar_switches: bool = false:
	set(v):
		if v:
			boton_limpiar_switches = false
			limpiar_switches()

## Si está activo, cada desvío simple copia la geometría REAL de la vía de paso y de
## la vía desviada (mapeo a escala real) en lugar de usar curvas canónicas de 5.3°.
## Así los puertos del aparato caen sobre las vías y la unión es natural (sin codos).
@export var recalibrar_aparatos_con_via_real: bool = true:
	set(v):
		if recalibrar_aparatos_con_via_real == v:
			return
		recalibrar_aparatos_con_via_real = v
		if is_inside_tree() and not paths.is_empty():
			_reconstruir_conexiones_adaptativas()

## Índice secuencial del switch a inspeccionar (0 a N-1).
@export var switch_indice_inspeccion: int = 0:
	set(v):
		if switch_indice_inspeccion == v:
			return
		switch_indice_inspeccion = v
		if _bloqueo_recursivo:
			return
		_seleccionar_switch_por_indice(switch_indice_inspeccion)

## ID numérico OSM del nodo del switch seleccionado.
@export var switch_id_inspeccion: int = 0:
	set(v):
		if switch_id_inspeccion == v:
			return
		switch_id_inspeccion = v
		if _bloqueo_recursivo:
			return
		_actualizar_inspeccion_switch()

## Pulsador: Avanzar al siguiente cambio de vía de la red.
@export var switch_siguiente: bool = false:
	set(v):
		if v:
			switch_siguiente = false
			_ir_siguiente_switch()

## Pulsador: Retroceder al cambio de vía anterior de la red.
@export var switch_anterior: bool = false:
	set(v):
		if v:
			switch_anterior = false
			_ir_anterior_switch()

## Pulsador para seleccionar automáticamente el switch más cercano al origen.
@export var seleccionar_switch_mas_cercano: bool = false:
	set(v):
		if v:
			seleccionar_switch_mas_cercano = false
			_seleccionar_switch_cercano()

## Estado de la aguja del switch inspeccionado: false = Directa, true = Desviada.
## Al modificarlo en el Inspector, las vías y agujas se mueven inmediatamente en el viewport 3D.
@export var aguja_desviada: bool = false:
	set(v):
		if aguja_desviada == v:
			return
		aguja_desviada = v
		if _bloqueo_recursivo:
			return
		if switch_id_inspeccion != 0:
			set_switch_desviado(switch_id_inspeccion, aguja_desviada)
			_actualizar_texto_info_switch()

## Pulsador para conmutar la aguja del switch seleccionado en el Inspector.
@export var conmutar_aguja_inspeccion: bool = false:
	set(v):
		if v:
			conmutar_aguja_inspeccion = false
			if switch_id_inspeccion != 0:
				conmutar_switch(switch_id_inspeccion)
				_bloqueo_recursivo = true
				aguja_desviada = is_switch_desviado(switch_id_inspeccion)
				_actualizar_texto_info_switch()
				_bloqueo_recursivo = false

## Pulsador: Excluir/Eliminar la vía desviada del switch actual de la red.
@export var excluir_via_desviada_actual: bool = false:
	set(v):
		if v:
			excluir_via_desviada_actual = false
			_excluir_desviada_actual()

## Ficha técnica y estado del cambio de vía seleccionado en el Inspector.
@export_multiline var info_switch_actual: String = ""

@export_group("Editor")
## Si está activo, muestra todos los tramos de vía (Path3D) y cambios de vía (AparatoDeVia)
## como nodos seleccionables en el árbol de escena del editor de Godot.
@export var mostrar_en_arbol_editor: bool = true:
	set(v):
		if mostrar_en_arbol_editor == v:
			return
		mostrar_en_arbol_editor = v
		if is_inside_tree():
			if mostrar_en_arbol_editor:
				habilitar_edicion_en_arbol()
			else:
				cargar_red()

## Pulsador para forzar la recarga limpia del archivo JSON desde disco y reconstruir la red completa.
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			_json_cache.clear()
			tramos_excluidos = PackedStringArray()
			_ediciones_guardadas = cargar_ediciones_guardadas()
			_ediciones_guardadas["_eliminados"] = []
			_escribir_archivo_ediciones()
			mostrar_en_arbol_editor = true
			generar_mecanismos_visuales = true
			if is_inside_tree():
				cargar_red()

@export_group("Persistencia y Edición de Vías")
## Archivo JSON donde se guardan las ediciones de vías modificadas. Si está vacío, usa el nombre base + '_edits.json'.
@export_file("*.json") var ruta_archivo_ediciones: String = "":
	set(v):
		if ruta_archivo_ediciones == v:
			return
		ruta_archivo_ediciones = v
		# Sólo se recarga el JOURNAL. Antes esto llamaba a cargar_red() y, en el
		# editor, regeneraba la red desde el JSON base: se perdían las curvas
		# editadas de la escena (y al guardar la escena quedaban sobreescritas).
		if is_inside_tree():
			_recargar_journal()
			print("TrackNetwork: Journal de ediciones -> %s" % obtener_ruta_ediciones_json())

## Pulsador: Hace visibles y seleccionables todos los tramos de vía en el árbol del editor de Godot para editarlos con el gizmo 3D.
@export var boton_habilitar_edicion_vias: bool = false:
	set(v):
		if v:
			boton_habilitar_edicion_vias = false
			habilitar_edicion_en_arbol()

## Pulsador: Guarda permanentemente todas las vías editadas en el archivo de ediciones JSON.
@export var boton_guardar_todas_las_ediciones: bool = false:
	set(v):
		if v:
			boton_guardar_todas_las_ediciones = false
			guardar_todas_las_ediciones()

## Pulsador: re-ancla los extremos flexibles de TODOS los aparatos a las vías reales
## (usalo después de mover switches a mano para forzar la actualización de las vías).
@export var boton_reintegrar_switches: bool = false:
	set(v):
		if v:
			boton_reintegrar_switches = false
			reintegrar_todos_los_switches()

## Pulsador: Restaura todas las vías a su forma original base del JSON descartando todas las modificaciones.
@export var boton_resetear_todas_las_ediciones: bool = false:
	set(v):
		if v:
			boton_resetear_todas_las_ediciones = false
			resetear_todas_las_ediciones()

## Total de tramos de vía con ediciones guardadas o activas.
@export var total_vias_editadas: int = 0

## Diagnóstico: imprime el tiempo de cada reconstrucción de conexiones.
@export var debug_tiempos: bool = false

## Diccionario de ediciones persistentes: segment_id -> Dictionary
var _ediciones_guardadas: Dictionary = {}

## Diccionario de datos crudos: segment_id -> Dictionary
var segments_data: Dictionary = {}
## Diccionario de nodos Path3D instanciados: segment_id -> Path3D
var paths: Dictionary = {}
## Diccionario de nodos de unión/switches: node_id (String) -> Dictionary
var junctions: Dictionary = {}
## Estado seleccionado de cada switch: node_id (int) -> segment_id de destino (String)
var switch_states: Dictionary = {}
## Diccionario de aparatos de vía instanciados: node_id (int) -> BaseTurnout
var aparatos_de_via: Dictionary = {}
## Rango métrico útil de vía plena por segmento [d_inicio, d_fin] libre de solapes con switches
var _recortes_segmentos: Dictionary = {}
## Intervalos EXCLUIDOS por segmento (uno por cada unión): permite que un tramo
## entre DOS aparatos conserve vía plena en el medio en vez de colapsar a absorbido.
var _recortes_extra: Dictionary = {}
## Segmentos donde dos zonas de adaptación no dejan separación física suficiente.
var _conflictos_adaptacion_switch: Dictionary = {}
## Registro único de cada extremo switch-segmento conectado en la última reconstrucción.
var _conexiones_switch_segmento: Dictionary = {}
# Tramos ya avisados como absorbidos (evita repetir el aviso en cada reconstrucción).
var _absorbidos_avisados: Dictionary = {}
## Segmentos cuya representación visual queda completamente reemplazada por un switch.
var _segmentos_reemplazados_por_switch: Dictionary = {}
## Mapeo de enclavamientos entre switches gemelos de escape (Crossover en H)
var _enclavamientos_crossover: Dictionary = {}

# Contenedores organizados para no saturar el árbol de nodos
var _contenedor_vias: Node3D = null
var _contenedor_switches: Node3D = null

# Lista ordenada en Z de IDs de switches para acceso O(1) instantáneo
var _switches_ordenados: Array[int] = []
# Bandera de protección anti-recursión
var _bloqueo_recursivo: bool = false
# Bandera para evitar eliminar registros persistentes durante el vaciado interno de red
var _limpiando: bool = false

# --- Persistencia de bajas (tramos y aparatos de vía) ---
# IDs de tramos cuya baja se persistió en disco (journal de ediciones).
# La ESCENA es la fuente de verdad de qué existe; esta lista solo se usa
# cuando la red se regenera desde el JSON base (cargar_red).
var _eliminados_persistentes: Dictionary = {}
# Bajas candidatas detectadas en el mismo frame por _exit_tree de un tramo.
var _bajas_tramos_pendientes: Dictionary = {}
# Bajas de aparatos de vía (switches) persistidas: node_id (String) -> true
var _switches_eliminados_persistentes: Dictionary = {}
# Huella (transform + estado) de cada switch para detectar movimientos en el editor.
var _huellas_switches: Dictionary = {}
# Huella de las curvas reales copiadas por cada aparato (evita recalibrar de más).
var _hash_recalibracion: Dictionary = {}
# Aparatos ya alineados al junction (el ajuste se aplica una sola vez por sesión).
var _refit_hecho: Dictionary = {}
var _switch_movido_pendiente: bool = false
var _acum_polling_switches: float = 0.0
# Edición incremental: tramos cuya geometría cambió y se resolverán agrupados.
var _segmentos_edicion_pendientes: Dictionary = {}
var _edicion_diferida_programada: bool = false

## Intervalo (s) entre sondeos de huellas de aparatos en el editor.
const INTERVALO_POLLING_SWITCHES: float = 0.25
const MAX_BAJAS_POR_FRAME: int = 12
## Avance mínimo (m) que debe tener el tramo flexible hacia la vía real para que
## la transición exista y no se descarte la curva (hueco en el empalme).
const LONGITUD_MINIMA_TRANSICION: float = 6.0
## Cuánto puede alargarse un extremo flexible por encima de su largo nominal para
## cerrar un empalme. Acotarlo evita curvas deformadas de radio ridículo.
const MARGEN_MAX_EXTENSION_LEAD: float = 8.0
## Corte mínimo (m) en la vía real para evitar superposición de balasto en la unión.
const MARGEN_MINIMO_UNION_M: float = 1.0
## Ventana de gracia (ms) antes de dar por confirmada la baja de un tramo.
## Evita registrar bajas por operaciones transitorias del editor (deshacer, reparentar).
const VENTANA_CONFIRMACION_BAJA_MS: int = 300


func _ready() -> void:
	add_to_group("track_network")
	_asegurar_contenedores()
	_asegurar_topologia_cargada()

	# Cargar registros de ediciones y exclusiones guardadas
	_recargar_journal()

	# Si la escena ya contiene tramos de vía serializados en el árbol (ej. en ramal_roca_main.tscn):
	if _tiene_vias_en_arbol():
		#print("TrackNetwork: Vías existentes detectadas en escena. Sincronizando árbol de escena...")
		recolectar_paths_desde_arbol()
		recolectar_switches_desde_arbol()
		# IMPORTANTE: la escena manda. Nunca se aplica la lista persistente de
		# bajas sobre los tramos que YA existen en el árbol: hacerlo borraba la
		# red completa al abrir la escena (toda edición manual se perdía al guardar).
		_reconciliar_eliminados_con_escena()
		_purgar_tramos_excluidos_del_arbol()
		_purgar_switches_eliminados_del_arbol()
		_depurar_tramos_invalidos()

		if aparatos_de_via.is_empty() and generar_mecanismos_visuales:
			_generar_aparatos_de_via()
		else:
			_reconstruir_conexiones_adaptativas()
		if _aplicar_extremos_guardados_si_faltan() > 0:
			_recortes_segmentos.clear()
			_reconstruir_conexiones_adaptativas()

		_inicializar_seguimiento_switches_editor()
		red_cargada.emit(paths.size(), junctions.size())
		habilitar_edicion_en_arbol()
		# Restaurar ediciones de estaciones desde el journal (diferido).
		call_deferred("aplicar_estaciones_guardadas")
		var geo: Node = get_node_or_null("GeometriaVias")
		if geo != null and geo.has_method("construir_geometria"):
			geo.call_deferred("construir_geometria")
	else:
		# Primera carga o escena vacía: generar desde el archivo JSON base
		cargar_red()


# ==============================================================================
# PERSISTENCIA DE BAJAS Y EDICIONES MANUALES (TRAMOS Y APARATOS DE VÍA)
# ==============================================================================

## Recarga el journal de ediciones desde disco SIN tocar los tramos de la escena.
##
## Se usa al abrir la escena, al regenerar la red y al cambiar `ruta_archivo_ediciones`.
## Es importante que no regenere la red: en el editor eso borraría las curvas
## editadas a mano que todavía no se guardaron en el journal.
func _recargar_journal() -> void:
	_ediciones_guardadas = cargar_ediciones_guardadas()
	_eliminados_persistentes.clear()
	if _ediciones_guardadas.has("_eliminados"):
		for item: Variant in (_ediciones_guardadas["_eliminados"] as Array):
			_eliminados_persistentes[str(item)] = true
	_switches_eliminados_persistentes.clear()
	if _ediciones_guardadas.has("_switches_eliminados"):
		for item: Variant in (_ediciones_guardadas["_switches_eliminados"] as Array):
			_switches_eliminados_persistentes[str(item)] = true
	total_vias_editadas = _contar_ediciones_reales()


## Reincorpora a la red los tramos que figuraban como eliminados en el journal
## pero que siguen existiendo como nodos dentro de la escena.
##
## La escena (.tscn) es la fuente de verdad de qué tramos existen. El journal
## sólo aporta información cuando la red se regenera desde el JSON base.
func _reconciliar_eliminados_con_escena() -> void:
	if _eliminados_persistentes.is_empty():
		return
	var descartados: int = 0
	for seg_id: String in _eliminados_persistentes.keys():
		if paths.has(seg_id) or _buscar_nodo_segmento_en_arbol(seg_id) != null:
			_eliminados_persistentes.erase(seg_id)
			descartados += 1
	if descartados > 0:
		_sincronizar_lista_eliminados_en_ediciones()
		_escribir_archivo_ediciones()
		#print("TrackNetwork: %d bajas persistentes descartadas (los tramos siguen en la escena)." % descartados)


## Vuelca los diccionarios de bajas dentro del journal de ediciones.
func _sincronizar_lista_eliminados_en_ediciones() -> void:
	var arr: Array = []
	for seg_id: String in _eliminados_persistentes.keys():
		arr.append(seg_id)
	_ediciones_guardadas["_eliminados"] = arr
	var arr_sw: Array = []
	for nid: String in _switches_eliminados_persistentes.keys():
		arr_sw.append(nid)
	_ediciones_guardadas["_switches_eliminados"] = arr_sw


## Elimina del árbol los switches cuya baja fue persistida explícitamente.
func _purgar_switches_eliminados_del_arbol() -> void:
	if _switches_eliminados_persistentes.is_empty():
		return
	for nid_str: String in _switches_eliminados_persistentes.keys():
		var nid: int = int(nid_str)
		if not aparatos_de_via.has(nid):
			continue
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		aparatos_de_via.erase(nid)
		_switches_ordenados.erase(nid)
		if sw != null and is_instance_valid(sw):
			var padre: Node = sw.get_parent()
			if padre != null:
				padre.remove_child(sw)
			sw.queue_free()


## Busca recursivamente un tramo por segment_id dentro del contenedor de vías.
func _buscar_nodo_segmento_en_arbol(seg_id: String) -> Path3D:
	if _contenedor_vias == null:
		return null
	return _buscar_nodo_segmento_recursivo(_contenedor_vias, seg_id)


## Quita de `paths` los tramos que ya no existen (nodos liberados por el editor).
## Sin esto, TrackGeometry intentaba leer nodos liberados y abortaba la malla.
func _depurar_tramos_invalidos() -> void:
	var invalidos: Array[String] = []
	for seg_id: String in paths.keys():
		if not is_instance_valid(paths[seg_id]):
			invalidos.append(seg_id)
	for seg_id: String in invalidos:
		paths.erase(seg_id)
		_recortes_segmentos.erase(seg_id)
	if not invalidos.is_empty():
		pass
		#print("TrackNetwork: %d tramos liberados fueron depurados del registro." % invalidos.size())


func _buscar_nodo_segmento_recursivo(nodo: Node, seg_id: String) -> Path3D:
	for hijo: Node in nodo.get_children():
		if hijo is EditableTrackSegment:
			var ed: EditableTrackSegment = hijo as EditableTrackSegment
			if ed.segment_id == seg_id:
				return ed
		elif hijo.get_child_count() > 0:
			var res: Path3D = _buscar_nodo_segmento_recursivo(hijo, seg_id)
			if res != null:
				return res
	return null


## Llamada por EditableTrackSegment cuando su nodo sale del árbol.
##
## La baja NO se persiste de inmediato: queda pendiente y `_process()` la confirma
## recién después de `VENTANA_CONFIRMACION_BAJA_MS`, verificando que el nodo siga
## ausente y que la escena siga viva. Así se distinguen las bajas manuales del
## usuario del desmontaje/recarga de la escena (que antes marcaba TODA la red como
## eliminada) y se tolera un deshacer inmediato del editor.
func solicitar_baja_segmento(seg_id: String) -> void:
	# Sólo se registra la baja de tramos que la red conoce: así un nodo ajeno
	# que sale del árbol no ensucia el journal.
	if seg_id.is_empty() or _limpiando or not paths.has(seg_id):
		return
	_bajas_tramos_pendientes[seg_id] = Time.get_ticks_msec()


## Confirma las bajas de tramos cuya ventana de gracia ya venció.
func _procesar_bajas_segmentos_pendientes() -> void:
	if _bajas_tramos_pendientes.is_empty():
		return
	# Si la instancia ya no está operativa, el árbol se estaba desmontando.
	if not is_inside_tree() or is_queued_for_deletion():
		_bajas_tramos_pendientes.clear()
		return
	var ahora: int = Time.get_ticks_msec()
	var vencidas: Array[String] = []
	for seg_id: String in _bajas_tramos_pendientes.keys():
		if ahora - int(_bajas_tramos_pendientes[seg_id]) >= VENTANA_CONFIRMACION_BAJA_MS:
			vencidas.append(seg_id)
	if vencidas.is_empty():
		return
	# Un desmontaje masivo (recarga/cierre de escena) no es una edición manual.
	var masivo: bool = vencidas.size() > MAX_BAJAS_POR_FRAME
	_bajas_tramos_pendientes.clear()
	if masivo:
		return
	for seg_id: String in vencidas:
		# Reapareció (undo del editor) o sigue existiendo: no fue una baja real.
		# Se consulta el ÁRBOL (no `paths`, que puede haber sido depurado).
		if _buscar_nodo_segmento_en_arbol(seg_id) != null:
			continue
		_registrar_baja_persistente(seg_id)


## Recrea los tramos dados de baja (exclusiones + journal) desde la topología base.
func restaurar_tramos_eliminados() -> int:
	_asegurar_topologia_cargada()
	# Los tramos dados de baja nunca llegan a `segments_data` (se saltean al
	# regenerar la red), así que hay que buscarlos en el JSON base crudo.
	var datos_red: Dictionary = _obtener_datos_red_json()
	var crudos: Dictionary = {}
	for seg_raw: Variant in (datos_red.get("segments", []) as Array):
		if seg_raw is Dictionary:
			var s_dict: Dictionary = seg_raw as Dictionary
			crudos[str(s_dict.get("id", ""))] = s_dict

	var ids: Array[String] = []
	for s: String in tramos_excluidos:
		ids.append(s)
	for s: String in _eliminados_persistentes.keys():
		if not ids.has(s):
			ids.append(s)

	tramos_excluidos = PackedStringArray()
	_eliminados_persistentes.clear()
	_sincronizar_lista_eliminados_en_ediciones()

	var root_owner: Node = _obtener_root_owner()
	var restaurados: int = 0
	for seg_id: String in ids:
		if paths.has(seg_id) or _buscar_nodo_segmento_en_arbol(seg_id) != null:
			continue
		var seg: Dictionary = {}
		if crudos.has(seg_id):
			seg = crudos[seg_id] as Dictionary
		elif segments_data.has(seg_id):
			seg = segments_data[seg_id] as Dictionary
		if seg.is_empty():
			continue
		var puntos_vector: Array[Vector3] = []
		for p_raw: Variant in (seg.get("points", []) as Array):
			if p_raw is Dictionary:
				var p: Dictionary = p_raw as Dictionary
				puntos_vector.append(Vector3(
					float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0))
				))
		if puntos_vector.size() < 2:
			continue
		var clasificacion: Array[String] = _clasificar_segmento(seg, puntos_vector)
		var path: Path3D = EDITABLE_TRACK_SEGMENT_SCRIPT.new()
		path.name = seg_id
		path.segment_id = seg_id
		path.sector_nombre = clasificacion[0]
		path.tramo_nombre = clasificacion[1]
		var curve: Curve3D = _construir_curva_suave(puntos_vector)
		curve.bake_interval = bake_interval
		path.curve = curve
		path.curva_original = curve.duplicate() as Curve3D
		var contenedor: Node3D = _contenedor_vias
		if organizar_en_nodos_tramos:
			contenedor = _obtener_o_crear_contenedor_tramo(clasificacion[0], clasificacion[1])
		contenedor.add_child(path)
		if root_owner != null:
			path.owner = root_owner
		paths[seg_id] = path
		if path is EditableTrackSegment:
			var ed: EditableTrackSegment = path as EditableTrackSegment
			if not ed.geometria_modificada.is_connected(_on_segmento_geometria_modificada):
				ed.geometria_modificada.connect(_on_segmento_geometria_modificada)
		restaurados += 1

	_escribir_archivo_ediciones()
	_recortes_segmentos.clear()
	_reconstruir_conexiones_adaptativas()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	#print("TrackNetwork: %d tramos restaurados desde la topología base." % restaurados)
	return restaurados


func _registrar_baja_persistente(seg_id: String) -> void:
	paths.erase(seg_id)
	_recortes_segmentos.erase(seg_id)
	if not tramos_excluidos.has(seg_id):
		var arr: PackedStringArray = tramos_excluidos
		arr.append(seg_id)
		tramos_excluidos = arr
	_eliminados_persistentes[seg_id] = true
	_sincronizar_lista_eliminados_en_ediciones()
	_escribir_archivo_ediciones()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("eliminar_geometria_tramo"):
		geo.call("eliminar_geometria_tramo", seg_id)
	_purgar_switches_huerfanos(seg_id)
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Tramo '%s' eliminado y persistido." % seg_id)


## Elimina los aparatos de vía que quedaron sin alguna de sus vías.
func _purgar_switches_huerfanos(seg_id: String) -> void:
	var aparatos_a_borrar: Array[int] = []
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		if sw.via_comun_id == seg_id or sw.via_directa_id == seg_id or sw.via_desviada_id == seg_id:
			aparatos_a_borrar.append(nid)
	for nid_del: int in aparatos_a_borrar:
		var sw_del: BaseTurnout = aparatos_de_via.get(nid_del) as BaseTurnout
		aparatos_de_via.erase(nid_del)
		_switches_ordenados.erase(nid_del)
		if sw_del != null and is_instance_valid(sw_del):
			var padre_sw: Node = sw_del.get_parent()
			if padre_sw != null:
				padre_sw.remove_child(sw_del)
			sw_del.queue_free()


## Elimina en caliente un switch y registra su baja en el journal.
func eliminar_switch(nodo_id: int) -> void:
	var sw: BaseTurnout = aparatos_de_via.get(nodo_id) as BaseTurnout
	if sw == null:
		return
	_quitar_aparato_del_registro(sw)
	_switches_eliminados_persistentes[str(nodo_id)] = true
	_sincronizar_lista_eliminados_en_ediciones()
	_persistir_diccionario_switches()
	_recortes_segmentos.clear()
	_reconstruir_conexiones_adaptativas()
	_escribir_archivo_ediciones()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Aparato de vía %d eliminado y persistido." % nodo_id)


## Quita del registro TODAS las claves que apunten a la misma instancia de aparato.
## Los aparatos compuestos (tijeras, escapes) registran varios node_id para una
## sola instancia; dejar claves colgando producía casts de objetos liberados.
func _quitar_aparato_del_registro(sw: BaseTurnout) -> void:
	if sw == null:
		return
	var claves: Array[int] = []
	for nid: int in aparatos_de_via.keys():
		if aparatos_de_via[nid] == sw:
			claves.append(nid)
	for nid_del: int in claves:
		aparatos_de_via.erase(nid_del)
		_switches_ordenados.erase(nid_del)
	_huellas_switches.erase(sw.node_id)
	if is_instance_valid(sw):
		var padre: Node = sw.get_parent()
		if padre != null:
			padre.remove_child(sw)
		sw.queue_free()


## Aplica las bajas persistentes de aparatos sobre la red recién generada.
func _aplicar_bajas_switches_persistentes() -> void:
	if _switches_eliminados_persistentes.is_empty():
		return
	var eliminados: int = 0
	for nid_str: String in _switches_eliminados_persistentes.keys():
		var nid: int = int(nid_str)
		var sw: BaseTurnout = aparatos_de_via.get(nid) as BaseTurnout
		if sw == null:
			continue
		_quitar_aparato_del_registro(sw)
		eliminados += 1
	if eliminados > 0:
		print("TrackNetwork: %d aparatos de vía no se regeneraron (baja persistente)." % eliminados)


# ==============================================================================
# SEGUIMIENTO DE SWITCHES EN EL EDITOR (MOVER / RE-ANCLAR / PERSISTIR)
# ==============================================================================

func _inicializar_seguimiento_switches_editor() -> void:
	_huellas_switches.clear()
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw != null:
			_huellas_switches[nid] = _huella_switch(sw)


## Huella estable de un aparato: transform + estado de agujas.
func _huella_switch(sw: BaseTurnout) -> int:
	var h: int = hash(sw.transform)
	h = hash(h ^ hash(sw.is_desviado()))
	h = hash(h ^ hash(sw.via_comun_id) ^ hash(sw.via_directa_id) ^ hash(sw.via_desviada_id))
	return h


func _process(delta: float) -> void:
	# Las bajas de tramos se confirman siempre (editor y juego): la ventana de
	# gracia evita registrar bajas por operaciones transitorias del editor.
	_procesar_bajas_segmentos_pendientes()
	if not Engine.is_editor_hint() or aparatos_de_via.is_empty():
		return
	# El sondeo de huellas de aparatos se limita a ~0.25 s: recorrer los ~200 switches
	# cada frame (hashear transform+estado y comprobar ancestros) es costoso en el editor.
	_acum_polling_switches += delta
	if _acum_polling_switches < INTERVALO_POLLING_SWITCHES:
		return
	_acum_polling_switches = 0.0
	var cambio: bool = false
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var h: int = _huella_switch(sw)
		if not _huellas_switches.has(nid) or int(_huellas_switches[nid]) != h:
			_huellas_switches[nid] = h
			cambio = true
	if not cambio:
		_detectar_switches_removidos()
		return
	# El sondeo cada `INTERVALO_POLLING_SWITCHES` ya actúa de debounce.
	reintegrar_switches_editados()


## Detecta aparatos que el usuario quitó del contenedor en el editor y persiste su baja.
## Sólo se ejecuta en el editor: si la escena entera se desmonta, este proceso no corre.
func _detectar_switches_removidos() -> void:
	if _contenedor_switches == null or aparatos_de_via.is_empty():
		return
	var removidos: Array[BaseTurnout] = []
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null or not is_instance_valid(sw):
			continue
		if not _contenedor_switches.is_ancestor_of(sw):
			removidos.append(sw)
	if removidos.is_empty():
		return
	for sw: BaseTurnout in removidos:
		_switches_eliminados_persistentes[str(sw.node_id)] = true
		_quitar_aparato_del_registro(sw)
	_sincronizar_lista_eliminados_en_ediciones()
	_persistir_diccionario_switches()
	_escribir_archivo_ediciones()
	_recortes_segmentos.clear()
	_reconstruir_conexiones_adaptativas()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: %d aparatos de vía quitados del árbol; baja persistida." % removidos.size())


## Re-ancla los extremos flexibles a las vías reales tras mover un switch y
## persiste la nueva posición/estado en el journal de ediciones.
func reintegrar_switches_editados() -> void:
	if aparatos_de_via.is_empty():
		return
	reiniciar_alineacion_aparatos()
	_reconstruir_conexiones_adaptativas()
	_persistir_diccionario_switches()
	_escribir_archivo_ediciones()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Re-anclaje de switches editados + journal actualizado.")


## Fuerza el re-anclaje de todos los aparatos a las vías reales (las vías se actualizan).
func reintegrar_todos_los_switches() -> void:
	if aparatos_de_via.is_empty():
		return
	reiniciar_alineacion_aparatos()
	_recortes_segmentos.clear()
	_reconstruir_conexiones_adaptativas()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Extremos flexibles re-anclados y vías actualizadas.")


## Permite que el ajuste de alineación al junction se vuelva a evaluar.
func reiniciar_alineacion_aparatos() -> void:
	_refit_hecho.clear()
	_huellas_switches.clear()
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw != null:
			_huellas_switches[nid] = _huella_switch(sw)


## Construye el diccionario serializable de switches y lo vuelca en el journal.
func _persistir_diccionario_switches() -> void:
	var sw_dict: Dictionary = {}
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var b: Basis = sw.transform.basis
		var o: Vector3 = sw.transform.origin
		sw_dict[str(nid)] = {
			"name": String(sw.name),
			"node_id": nid,
			"transform": [
				b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
				o.x, o.y, o.z
			],
			"via_comun_id": sw.via_comun_id,
			"via_directa_id": sw.via_directa_id,
			"via_desviada_id": sw.via_desviada_id,
			"largo_aparato": sw.get_largo_aparato(),
			"tipo_aparato": sw.get_tipo_aparato(),
			"desviada": sw.is_desviado()
		}
		# Extremos flexibles fijados a mano (edición de los extremos del switch).
		var extremos: Dictionary = {}
		var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
		if g_ext != null:
			for h: Node in g_ext.get_children():
				if not (h is FlexibleTrackLead):
					continue
				var l: FlexibleTrackLead = h as FlexibleTrackLead
				if not l.respetar_edicion_manual:
					continue
				extremos[String(l.name)] = {
					"punto_inicio": [l.punto_inicio.x, l.punto_inicio.y, l.punto_inicio.z],
					"direccion_inicio": [l.direccion_inicio.x, l.direccion_inicio.y, l.direccion_inicio.z],
					"longitud_extension": l.longitud_extension,
					"offset_lateral": l.offset_lateral,
					"offset_vertical": l.offset_vertical,
					"angulo_curva_deg": l.angulo_curva_deg,
					"factor_tangente": l.factor_tangente,
					"usar_extremo_manual": l.usar_extremo_manual,
					"punto_fin_manual": [l.punto_fin_manual.x, l.punto_fin_manual.y, l.punto_fin_manual.z],
					"direccion_fin_manual": [l.direccion_fin_manual.x, l.direccion_fin_manual.y, l.direccion_fin_manual.z],
					"respetar_edicion_manual": true
				}
		if not extremos.is_empty():
			(sw_dict[str(nid)] as Dictionary)["extremos"] = extremos
	_ediciones_guardadas["_switches"] = sw_dict


## Aplica a los aparatos recién generados las posiciones/estados guardados en el
## journal. Se usa únicamente al regenerar la red desde el JSON base.
func _aplicar_switches_guardados() -> void:
	if not _ediciones_guardadas.has("_switches"):
		return
	var sw_dict: Dictionary = _ediciones_guardadas["_switches"] as Dictionary
	if sw_dict.is_empty():
		return
	var aplicados: int = 0
	for nid_str: String in sw_dict.keys():
		var nid: int = int(nid_str)
		var sw: BaseTurnout = aparatos_de_via.get(nid) as BaseTurnout
		if sw == null:
			continue
		var datos: Dictionary = sw_dict[nid_str] as Dictionary
		# Si el aparato cambió de tipo al regenerar, su pose guardada no aplica.
		var tipo_guardado: String = str(datos.get("tipo_aparato", ""))
		if not tipo_guardado.is_empty() and tipo_guardado != sw.get_tipo_aparato():
			continue
		var tr: Array = datos.get("transform", []) as Array
		if tr.size() >= 12:
			var nb: Basis = Basis(
				Vector3(float(tr[0]), float(tr[1]), float(tr[2])),
				Vector3(float(tr[3]), float(tr[4]), float(tr[5])),
				Vector3(float(tr[6]), float(tr[7]), float(tr[8]))
			)
			var no: Vector3 = Vector3(float(tr[9]), float(tr[10]), float(tr[11]))
			sw.transform = Transform3D(nb, no)
		if datos.has("via_comun_id"):
			sw.via_comun_id = str(datos["via_comun_id"])
		if datos.has("via_directa_id"):
			sw.via_directa_id = str(datos["via_directa_id"])
		if datos.has("via_desviada_id"):
			sw.via_desviada_id = str(datos["via_desviada_id"])
		sw.conmutar_a(1 if bool(datos.get("desviada", false)) else 0)
		_aplicar_extremos_guardados(sw, datos)
		aplicados += 1
	if aplicados > 0:
		print("TrackNetwork: %d switches restaurados desde el journal de ediciones." % aplicados)


## Aplica a un aparato los extremos flexibles fijados a mano guardados en el journal.
## Devuelve cuántos extremos restauró.
func _aplicar_extremos_guardados(sw: BaseTurnout, datos: Dictionary) -> int:
	var extremos: Dictionary = datos.get("extremos", {}) as Dictionary
	if extremos.is_empty():
		return 0
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return 0
	var aplicados: int = 0
	for nombre: String in extremos.keys():
		var lead: FlexibleTrackLead = g_ext.get_node_or_null(nombre) as FlexibleTrackLead
		if lead == null:
			continue
		var e: Dictionary = extremos[nombre] as Dictionary
		lead._bloqueo_reconstruccion = true
		lead.longitud_extension = float(e.get("longitud_extension", lead.longitud_extension))
		lead.offset_lateral = float(e.get("offset_lateral", lead.offset_lateral))
		lead.offset_vertical = float(e.get("offset_vertical", lead.offset_vertical))
		lead.angulo_curva_deg = float(e.get("angulo_curva_deg", lead.angulo_curva_deg))
		lead.factor_tangente = float(e.get("factor_tangente", lead.factor_tangente))
		var pi_a: Array = e.get("punto_inicio", []) as Array
		if pi_a.size() >= 3:
			lead.punto_inicio = Vector3(float(pi_a[0]), float(pi_a[1]), float(pi_a[2]))
		var di_a: Array = e.get("direccion_inicio", []) as Array
		if di_a.size() >= 3:
			lead.direccion_inicio = Vector3(float(di_a[0]), float(di_a[1]), float(di_a[2]))
		lead.usar_extremo_manual = bool(e.get("usar_extremo_manual", true))
		var pf_a: Array = e.get("punto_fin_manual", []) as Array
		if pf_a.size() >= 3:
			lead.punto_fin_manual = Vector3(float(pf_a[0]), float(pf_a[1]), float(pf_a[2]))
		var df_a: Array = e.get("direccion_fin_manual", []) as Array
		if df_a.size() >= 3:
			lead.direccion_fin_manual = Vector3(float(df_a[0]), float(df_a[1]), float(df_a[2]))
		lead.respetar_edicion_manual = true
		lead._bloqueo_reconstruccion = false
		lead.reconstruir_tramo()
		aplicados += 1
	return aplicados


## En la carga desde escena, completa con el journal los extremos que la escena no
## trae fijados a mano (la escena siempre gana si ya los tiene).
func _aplicar_extremos_guardados_si_faltan() -> int:
	if not _ediciones_guardadas.has("_switches"):
		return 0
	var sw_dict: Dictionary = _ediciones_guardadas["_switches"] as Dictionary
	var total: int = 0
	for nid_str: String in sw_dict.keys():
		var sw: BaseTurnout = aparatos_de_via.get(int(nid_str)) as BaseTurnout
		if sw == null:
			continue
		total += _aplicar_extremos_guardados(sw, sw_dict[nid_str] as Dictionary)
	if total > 0:
		print("TrackNetwork: %d extremos de switch restaurados desde el journal." % total)
	return total


func _obtener_root_owner() -> Node:
	if not Engine.is_editor_hint():
		return null
	var root: Node = get_tree().edited_scene_root if get_tree() != null else null
	if root == null:
		root = self
	return root


func _asegurar_contenedores() -> void:
	var root_owner: Node = _obtener_root_owner()

	_contenedor_vias = get_node_or_null("Vias") as Node3D
	if _contenedor_vias == null:
		_contenedor_vias = Node3D.new()
		_contenedor_vias.name = "Vias"
		add_child(_contenedor_vias)
	if root_owner != null:
		_contenedor_vias.owner = root_owner

	_contenedor_switches = get_node_or_null("Switches") as Node3D
	if _contenedor_switches == null:
		_contenedor_switches = Node3D.new()
		_contenedor_switches.name = "Switches"
		add_child(_contenedor_switches)
	if root_owner != null:
		_contenedor_switches.owner = root_owner


func _limpiar() -> void:
	_limpiando = true
	_asegurar_contenedores()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("limpiar"):
		geo.call("limpiar")
	if _contenedor_vias != null:
		_limpiar_nodo_recursivo(_contenedor_vias)
	if _contenedor_switches != null:
		_limpiar_nodo_recursivo(_contenedor_switches)

	segments_data.clear()
	paths.clear()
	junctions.clear()
	aparatos_de_via.clear()
	_switches_ordenados.clear()
	_recortes_segmentos.clear()
	_recortes_extra.clear()
	_conflictos_adaptacion_switch.clear()
	_conexiones_switch_segmento.clear()
	_segmentos_reemplazados_por_switch.clear()
	_enclavamientos_crossover.clear()
	_hash_recalibracion.clear()
	_segmentos_edicion_pendientes.clear()
	_edicion_diferida_programada = false
	_limpiando = false


func _limpiar_nodo_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	for c: Node in nodo.get_children():
		_desasignar_owner_recursivo(c)
		nodo.remove_child(c)
		# La red puede regenerarse en el mismo frame desde setters @tool.
		# free() elimina el nombre inmediatamente y evita colisiones al recrear switches.
		c.free()


func _desasignar_owner_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	for h: Node in nodo.get_children():
		_desasignar_owner_recursivo(h)
	nodo.owner = null


## Obtiene o crea el contenedor de Sector y Tramo dentro de _contenedor_vias
func _obtener_o_crear_contenedor_tramo(sector_nombre: String, tramo_nombre: String) -> Node3D:
	var root_owner: Node = _obtener_root_owner()

	var nodo_sector: Node3D = _contenedor_vias.get_node_or_null(sector_nombre) as Node3D
	if nodo_sector == null:
		nodo_sector = Node3D.new()
		nodo_sector.name = sector_nombre
		_contenedor_vias.add_child(nodo_sector)
	if root_owner != null:
		nodo_sector.owner = root_owner

	var nodo_tramo: Node3D = nodo_sector.get_node_or_null(tramo_nombre) as Node3D
	if nodo_tramo == null:
		nodo_tramo = Node3D.new()
		nodo_tramo.name = tramo_nombre
		nodo_sector.add_child(nodo_tramo)
	if root_owner != null:
		nodo_tramo.owner = root_owner

	return nodo_tramo


## Obtiene o crea el contenedor de Sector y Tramo dentro de _contenedor_switches
func _obtener_o_crear_contenedor_switch_tramo(sector_nombre: String, tramo_nombre: String) -> Node3D:
	var root_owner: Node = _obtener_root_owner()

	var nodo_sector: Node3D = _contenedor_switches.get_node_or_null(sector_nombre) as Node3D
	if nodo_sector == null:
		nodo_sector = Node3D.new()
		nodo_sector.name = sector_nombre
		_contenedor_switches.add_child(nodo_sector)
	if root_owner != null:
		nodo_sector.owner = root_owner

	var nodo_tramo: Node3D = nodo_sector.get_node_or_null(tramo_nombre) as Node3D
	if nodo_tramo == null:
		nodo_tramo = Node3D.new()
		nodo_tramo.name = tramo_nombre
		nodo_sector.add_child(nodo_tramo)
	if root_owner != null:
		nodo_tramo.owner = root_owner

	return nodo_tramo


## Determina el sector y tramo al que pertenece un aparato de vía según su posición y vías conectadas.
func _determinar_sector_tramo_switch(pos_sw: Vector3, via_ids: Array[String]) -> Array[String]:
	for vid: String in via_ids:
		if not vid.is_empty() and segments_data.has(vid):
			var seg: Dictionary = segments_data[vid] as Dictionary
			if seg.has("sector") and seg.has("tramo"):
				return [str(seg["sector"]), str(seg["tramo"])]
	return _clasificar_segmento({}, [pos_sw])


## Verifica si la escena ya contiene nodos Path3D serializados en el árbol.
func _tiene_vias_en_arbol() -> bool:
	if _contenedor_vias == null:
		return false
	return _contar_paths_recursivo(_contenedor_vias) > 0


func _contar_paths_recursivo(nodo: Node) -> int:
	var c: int = 0
	for h: Node in nodo.get_children():
		if h is Path3D:
			c += 1
		elif h.get_child_count() > 0:
			c += _contar_paths_recursivo(h)
	return c


## Recorre recursivamente _contenedor_vias para sincronizar 'paths' con los nodos Path3D existentes.
func recolectar_paths_desde_arbol() -> void:
	paths.clear()
	if _contenedor_vias != null:
		_recolectar_paths_recursivo(_contenedor_vias)
	print("TrackNetwork: Sincronizados %d tramos Path3D desde el árbol de escena." % paths.size())


func _recolectar_paths_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	for hijo: Node in nodo.get_children():
		if hijo is Path3D:
			var sid: String = hijo.name
			if hijo is EditableTrackSegment:
				var ed: EditableTrackSegment = hijo as EditableTrackSegment
				if not ed.segment_id.is_empty():
					sid = ed.segment_id
				if not ed.geometria_modificada.is_connected(_on_segmento_geometria_modificada):
					ed.geometria_modificada.connect(_on_segmento_geometria_modificada)
			paths[sid] = hijo as Path3D
		elif hijo.get_child_count() > 0:
			_recolectar_paths_recursivo(hijo)


## Recorre recursivamente _contenedor_switches para sincronizar 'aparatos_de_via' con los nodos existentes.
func recolectar_switches_desde_arbol() -> void:
	aparatos_de_via.clear()
	_switches_ordenados.clear()
	if _contenedor_switches != null:
		_recolectar_switches_recursivo(_contenedor_switches)
	#print("TrackNetwork: Sincronizados %d aparatos de vía desde el árbol de escena." % aparatos_de_via.size())


func _recolectar_switches_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	for hijo: Node in nodo.get_children():
		if hijo is BaseTurnout:
			var sw: BaseTurnout = hijo as BaseTurnout
			var nid: int = sw.node_id
			if nid != 0:
				aparatos_de_via[nid] = sw
				if not _switches_ordenados.has(nid):
					_switches_ordenados.append(nid)
				if not sw.estado_cambiado.is_connected(_on_switch_registrado_cambiado.bind(nid, sw)):
					sw.estado_cambiado.connect(_on_switch_registrado_cambiado.bind(nid, sw))
		elif hijo.get_child_count() > 0:
			_recolectar_switches_recursivo(hijo)


func _on_switch_registrado_cambiado(desv_val: Variant, node_id: int, sw: BaseTurnout) -> void:
	var desv_b: bool = bool(desv_val)
	var seg_activo: String = sw.get_segmento_activo()
	switch_states[node_id] = seg_activo
	switch_conmutado.emit(node_id, seg_activo)
	switch_movido.emit(node_id, desv_b, seg_activo)


## Elimina del árbol de escena y de la red cualquier tramo presente en tramos_excluidos.
func _purgar_tramos_excluidos_del_arbol() -> void:
	if tramos_excluidos.is_empty():
		return
	var geo: Node = get_node_or_null("GeometriaVias")
	for s_ex: String in tramos_excluidos:
		if paths.has(s_ex):
			var p: Path3D = paths[s_ex] as Path3D
			paths.erase(s_ex)
			if p != null and is_instance_valid(p):
				var padre: Node = p.get_parent()
				if padre != null:
					padre.remove_child(p)
				p.queue_free()
		if geo != null and geo.has_method("eliminar_geometria_tramo"):
			geo.call("eliminar_geometria_tramo", s_ex)


## Limpia todos los aparatos de vía instanciados en la escena.
func limpiar_switches() -> void:
	if _contenedor_switches != null:
		_limpiar_nodo_recursivo(_contenedor_switches)
	aparatos_de_via.clear()
	_switches_ordenados.clear()
	_recortes_segmentos.clear()
	_conflictos_adaptacion_switch.clear()
	_conexiones_switch_segmento.clear()
	_segmentos_reemplazados_por_switch.clear()
	_enclavamientos_crossover.clear()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")


## Genera switches exclusivamente adaptados sobre los tramos Path3D que existen en la escena.
func generar_switches_desde_paths_existentes() -> void:
	recolectar_paths_desde_arbol()
	_asegurar_topologia_cargada()

	if _contenedor_switches != null:
		_limpiar_nodo_recursivo(_contenedor_switches)
	aparatos_de_via.clear()
	_switches_ordenados.clear()

	_generar_aparatos_de_via()
	# Se reponen las poses/estados guardados sólo de los aparatos que conservaron
	# su tipo (si cambió, la pose vieja no tiene sentido).
	_aplicar_switches_guardados()
	_aplicar_bajas_switches_persistentes()
	_reconstruir_conexiones_adaptativas()
	habilitar_edicion_en_arbol()

	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")

	print("TrackNetwork: Generados %d switches a partir de los %d tramos existentes." % [aparatos_de_via.size(), paths.size()])


## Elimina permanentemente un tramo de vía de la red, su modelo 3D y switches huérfanos.
func eliminar_segmento(seg_id: String) -> void:
	if seg_id.is_empty():
		return
	if paths.has(seg_id):
		var p: Path3D = paths[seg_id] as Path3D
		paths.erase(seg_id)
		if p != null and is_instance_valid(p):
			var padre: Node = p.get_parent()
			if padre != null:
				padre.remove_child(p)
			p.queue_free()
	notificar_segmento_eliminado(seg_id)
	_reconstruir_conexiones_adaptativas()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("eliminar_geometria_tramo"):
		geo.call("eliminar_geometria_tramo", seg_id)
	# Los tramos vecinos cambian su rango útil (el aparato que los recortaba
	# desapareció): el re-mallado incremental sólo rehace los que cambiaron.
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Tramo '%s' eliminado permanentemente." % seg_id)


## Notificación recibida cuando un nodo Path3D sale del árbol de escena (ej. al borrarlo en el editor).
func notificar_segmento_eliminado(seg_id: String) -> void:
	if _limpiando or seg_id.is_empty():
		return
	if paths.has(seg_id):
		paths.erase(seg_id)
	if not tramos_excluidos.has(seg_id):
		var arr: PackedStringArray = tramos_excluidos
		arr.append(seg_id)
		tramos_excluidos = arr
	_eliminados_persistentes[seg_id] = true
	_sincronizar_lista_eliminados_en_ediciones()
	_escribir_archivo_ediciones()
	_recortes_segmentos.erase(seg_id)

	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("eliminar_geometria_tramo"):
		geo.call("eliminar_geometria_tramo", seg_id)

	# Remover switches que hayan quedado incompletos por la eliminación de esta vía
	_purgar_switches_huerfanos(seg_id)
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")


## Elimina del árbol de escena cualquier nodo de tramo perteneciente a la Vía Quilmes o colas ajenas.
func purgar_tramos_ajenos() -> void:
	if _contenedor_vias == null:
		return
	var eliminados: int = 0
	var nodo_excl: Node = _contenedor_vias.get_node_or_null("Tramos_Excluidos")
	if nodo_excl != null:
		nodo_excl.owner = null
		_contenedor_vias.remove_child(nodo_excl)
		nodo_excl.queue_free()
		eliminados += 1

	recolectar_paths_desde_arbol()
	for s_id: String in paths.keys():
		var p: Path3D = paths[s_id] as Path3D
		if p == null or p.curve == null or p.curve.point_count < 2:
			continue
		var puntos_vec: Array[Vector3] = []
		for i: int in p.curve.point_count:
			puntos_vec.append(p.curve.get_point_position(i))
		var clas: Array[String] = _clasificar_segmento({}, puntos_vec)
		if clas[0] == "Tramos_Excluidos":
			paths.erase(s_id)
			var padre: Node = p.get_parent()
			if padre != null:
				p.owner = null
				padre.remove_child(p)
				p.queue_free()
				eliminados += 1

	print("TrackNetwork: Purgados %d tramos ajenos de la escena." % eliminados)
	if generar_mecanismos_visuales:
		_generar_aparatos_de_via()


func _actualizar_bake_intervals() -> void:
	for path_nodo: Variant in paths.values():
		if path_nodo is Path3D:
			var p: Path3D = path_nodo as Path3D
			if p.curve != null:
				p.curve.bake_interval = bake_interval


## Determina la ruta final del archivo JSON según los filtros activos.
func _obtener_ruta_red_json() -> String:
	# `solo_constitucion_bosques` es el discriminador real: los setters de
	# `filtro_ramal` lo mantienen sincronizado (0 -> true, 1 -> false).
	var preferida: String = (
		"res://tramo_completo_constitucion_bosques/red_godot.json"
		if not solo_constitucion_bosques
		else "res://tramo_completo_constitucion_bosques/red_godot_constitucion_bosques.json"
	)
	var ruta: String = preferida if FileAccess.file_exists(preferida) else json_path

	if not FileAccess.file_exists(ruta):
		var fallback: String = "res://tramo_completo_constitucion_bosques/red_godot_constitucion_bosques.json"
		if FileAccess.file_exists(fallback):
			ruta = fallback
		else:
			fallback = "res://tramo_completo_constitucion_bosques/red_godot.json"
			if FileAccess.file_exists(fallback):
				ruta = fallback
	return ruta


## Determina la ruta del archivo JSON de red y devuelve el Dictionary parseado (con caché).
func _obtener_datos_red_json() -> Dictionary:
	var ruta_final: String = _obtener_ruta_red_json()
	if not FileAccess.file_exists(ruta_final):
		push_error("TrackNetwork: No se encontró el archivo de red: %s" % ruta_final)
		return {}

	if _json_cache.has(ruta_final):
		return (_json_cache[ruta_final] as Dictionary).duplicate(true)

	var file: FileAccess = FileAccess.open(ruta_final, FileAccess.READ)
	if file == null:
		push_error("TrackNetwork: No se pudo abrir: %s (Error: %s)" % [
			ruta_final,
			error_string(FileAccess.get_open_error())
		])
		return {}

	var texto: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(texto)
	if error != OK:
		push_error("TrackNetwork: Error JSON (%s): %s en línea %d" % [
			ruta_final,
			json.get_error_message(),
			json.get_error_line()
		])
		return {}

	if not (json.data is Dictionary):
		push_error("TrackNetwork: Formato JSON inválido (se esperaba Dictionary con 'segments' y 'junctions').")
		return {}

	var data: Dictionary = json.data as Dictionary
	_json_cache[ruta_final] = data
	return data.duplicate(true)


## Asegura que la topología (junctions y segments_data) esté cargada en memoria desde el JSON.
func _asegurar_topologia_cargada() -> void:
	if not junctions.is_empty() and not segments_data.is_empty():
		return
	var data: Dictionary = _obtener_datos_red_json()
	if data.is_empty():
		return
	junctions = data.get("junctions", {}) as Dictionary
	var segmentos_raw: Array = data.get("segments", []) as Array
	for seg_raw: Variant in segmentos_raw:
		if seg_raw is Dictionary:
			var seg: Dictionary = seg_raw as Dictionary
			var seg_id: String = str(seg.get("id", ""))
			if not seg_id.is_empty():
				segments_data[seg_id] = seg


## Instancia o clona un aparato de vía tipo A con extremos flexibles integrados.
func _instanciar_switch_tipo_a() -> ProceduralTurnout:
	if SWITCH_TIPO_A_SCENE != null:
		var inst: Node = SWITCH_TIPO_A_SCENE.instantiate()
		if inst is ProceduralTurnout:
			return inst as ProceduralTurnout
	var to: ProceduralTurnout = TURNOUT_TIPO_A_SCRIPT.new()
	to.generar_extremos_flexibles = true
	return to


## Instancia o clona un aparato de vía simétrico tipo B con extremos flexibles integrados.
func _instanciar_switch_tipo_b() -> ProceduralSymmetricalTurnout:
	if SWITCH_TIPO_B_SCENE != null:
		var inst: Node = SWITCH_TIPO_B_SCENE.instantiate()
		if inst is ProceduralSymmetricalTurnout:
			return inst as ProceduralSymmetricalTurnout
	var to: ProceduralSymmetricalTurnout = TURNOUT_TIPO_B_SCRIPT.new()
	to.generar_extremos_flexibles = true
	return to


## Instancia o clona un cruce de vías tipo C con extremos flexibles integrados.
func _instanciar_switch_tipo_c() -> ProceduralCrossing:
	if SWITCH_TIPO_C_SCENE != null:
		var inst: Node = SWITCH_TIPO_C_SCENE.instantiate()
		if inst is ProceduralCrossing:
			return inst as ProceduralCrossing
	var to: ProceduralCrossing = TURNOUT_TIPO_C_SCRIPT.new()
	to.generar_extremos_flexibles = true
	return to


## Instancia o clona un escape crossover tipo D con extremos flexibles integrados.
func _instanciar_switch_tipo_d() -> ProceduralCrossover:
	if SWITCH_TIPO_D_SCENE != null:
		var inst: Node = SWITCH_TIPO_D_SCENE.instantiate()
		if inst is ProceduralCrossover:
			return inst as ProceduralCrossover
	var to: ProceduralCrossover = TURNOUT_TIPO_D_SCRIPT.new()
	to.generar_extremos_flexibles = true
	return to


## Instancia o clona una tijera / bretelle tipo E con extremos flexibles integrados.
func _instanciar_switch_tipo_e() -> ProceduralScissorsCrossover:
	if SWITCH_TIPO_E_SCENE != null:
		var inst: Node = SWITCH_TIPO_E_SCENE.instantiate()
		if inst is ProceduralScissorsCrossover:
			return inst as ProceduralScissorsCrossover
	var to: ProceduralScissorsCrossover = TURNOUT_TIPO_E_SCRIPT.new()
	to.generar_extremos_flexibles = true
	return to


## Crea una curva desviada estándar a derecha (espejada de Tipo A canónico).


## Obtiene la posición 3D global y la dirección tangencial hacia afuera del tramo en el punto de recorte.
## Devuelve la curva COMPLETA de un tramo (la original, sin el recorte automático):
## todo el análisis de uniones y distancias se calcula contra ella (idempotencia).
func _curva_completa_de_path(p: Path3D) -> Curve3D:
	if p == null:
		return null
	if p is EditableTrackSegment:
		var e: EditableTrackSegment = p as EditableTrackSegment
		if e.curva_original != null and e.curva_original.point_count >= 2:
			return e.curva_original
	return p.curve


## Obtiene la posición 3D global y la dirección tangencial hacia afuera del tramo en el punto de recorte.
func _obtener_punto_recorte_segmento(path: Path3D, end_tipo: String, dist_recorte: float) -> Dictionary:
	if path == null or path.curve == null or path.curve.point_count < 2:
		return {"pos": Vector3.ZERO, "dir": Vector3.FORWARD}
	var c: Curve3D = _curva_completa_de_path(path)
	if c == null or c.point_count < 2:
		return {"pos": Vector3.ZERO, "dir": Vector3.FORWARD}
	var l: float = c.get_baked_length()
	dist_recorte = clampf(dist_recorte, 0.0, maxf(0.0, l - MARGEN_FINAL_SEGMENTO_SWITCH))
	if end_tipo == "start":
		var d_sample: float = clampf(dist_recorte, 0.0, maxf(0.0, l - 1.0))
		var d_dir: float = minf(l, d_sample + 0.5)
		var p0: Vector3 = c.sample_baked(d_sample)
		var p1: Vector3 = c.sample_baked(d_dir)
		var dir: Vector3 = (p1 - p0).normalized() if p1.distance_squared_to(p0) > 1e-6 else Vector3.FORWARD
		p0 = path.global_transform * p0
		dir = (path.global_transform.basis * dir).normalized()
		return {"pos": p0, "dir": dir}
	else:
		var d_sample: float = clampf(l - dist_recorte, minf(1.0, l), l)
		var d_dir: float = maxf(0.0, d_sample - 0.5)
		var p0: Vector3 = c.sample_baked(d_sample)
		var p1: Vector3 = c.sample_baked(d_dir)
		var dir: Vector3 = (p1 - p0).normalized() if p1.distance_squared_to(p0) > 1e-6 else Vector3.BACK
		p0 = path.global_transform * p0
		dir = (path.global_transform.basis * dir).normalized()
		return {"pos": p0, "dir": dir}


## Dirección real (global, normalizada) de la vía `seg_id` en el punto de recorte.
func _direccion_real_segmento_extremo(seg_id: String, end_tipo: String, dist: float = 0.0) -> Vector3:
	var p: Path3D = paths.get(seg_id) as Path3D
	if p == null or p.curve == null or p.curve.point_count < 2:
		return Vector3.FORWARD
	var d: Vector3 = _obtener_punto_recorte_segmento(p, end_tipo, dist)["dir"] as Vector3
	return d if d.length_squared() > 1e-6 else Vector3.FORWARD


func _extremo_opuesto(end_tipo: String) -> String:
	return "end" if end_tipo == "start" else "start"


## Dirección (en espacio local del aparato) de la vía real vista desde el extremo
## OPUESTO al aparato. Se usa cuando el tramo es tan corto que el extremo flexible
## lo cubre entero: la dirección correcta es la de la vía en el otro nodo, no una
## constante arbitraria (evitaba quiebres de hasta 22°).
func _dir_local_hacia_extremo_opuesto(trans_sw: Transform3D, seg_id: String, end_tipo: String) -> Vector3:
	var d_mundo: Vector3 = _direccion_real_segmento_extremo(seg_id, _extremo_opuesto(end_tipo))
	var d_local: Vector3 = trans_sw.basis.inverse() * d_mundo
	return d_local.normalized() if d_local.length_squared() > 1e-6 else Vector3.FORWARD


## Calcula tangentes continuas compartidas C1 para todas las uniones de la red,
## eliminando quiebres y esquinas duras en los empalmes entre segmentos.
func _calcular_tangentes_de_uniones(segmentos_raw: Array) -> Dictionary:
	var tangentes: Dictionary = {}
	var seg_puntos_map: Dictionary = {}

	for s_raw: Variant in segmentos_raw:
		if not (s_raw is Dictionary):
			continue
		var s_dict: Dictionary = s_raw as Dictionary
		var sid: String = str(s_dict.get("id", ""))
		var raw_pts: Array = s_dict.get("points", []) as Array
		if raw_pts.size() < 2:
			continue
		var pts: Array[Vector3] = []
		for p: Variant in raw_pts:
			if p is Dictionary:
				pts.append(Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0))))
		if pts.size() >= 2:
			seg_puntos_map[sid] = pts

	for j_key: Variant in junctions.keys():
		var j_dict: Dictionary = junctions[j_key] as Dictionary
		var conns: Array = j_dict.get("segments", []) as Array

		# Empalmes de 2 segmentos (continuidad de vía plena)
		if conns.size() == 2:
			var c0: Dictionary = conns[0] as Dictionary
			var c1: Dictionary = conns[1] as Dictionary
			var s0_id: String = str(c0.get("segment_id", ""))
			var s1_id: String = str(c1.get("segment_id", ""))
			if not seg_puntos_map.has(s0_id) or not seg_puntos_map.has(s1_id):
				continue
			var pts0: Array[Vector3] = seg_puntos_map[s0_id]
			var pts1: Array[Vector3] = seg_puntos_map[s1_id]
			var e0: String = str(c0.get("end", "start"))
			var e1: String = str(c1.get("end", "start"))

			var v0: Vector3 = (pts0[pts0.size() - 1] - pts0[pts0.size() - 2]).normalized() if e0 == "end" else (pts0[0] - pts0[1]).normalized()
			var v1: Vector3 = (pts1[1] - pts1[0]).normalized() if e1 == "start" else (pts1[pts1.size() - 2] - pts1[pts1.size() - 1]).normalized()

			if v0.dot(v1) > 0.0:
				var t_j: Vector3 = (v0 + v1).normalized()
				tangentes[s0_id + "_" + e0] = t_j if e0 == "end" else -t_j
				tangentes[s1_id + "_" + e1] = t_j if e1 == "start" else -t_j

		# Uniones de 3 o más segmentos (desvíos / switches): calcular tangente recta principal
		elif conns.size() >= 3:
			var mejor_dot: float = -2.0
			var idx_in: int = 0
			var idx_out: int = 1
			for i: int in conns.size():
				for k: int in range(i + 1, conns.size()):
					var c_i: Dictionary = conns[i] as Dictionary
					var c_k: Dictionary = conns[k] as Dictionary
					var s_i: String = str(c_i.get("segment_id", ""))
					var s_k: String = str(c_k.get("segment_id", ""))
					if not seg_puntos_map.has(s_i) or not seg_puntos_map.has(s_k):
						continue
					var pts_i: Array[Vector3] = seg_puntos_map[s_i]
					var pts_k: Array[Vector3] = seg_puntos_map[s_k]
					var e_i: String = str(c_i.get("end", "start"))
					var e_k: String = str(c_k.get("end", "start"))
					var v_i: Vector3 = (pts_i[pts_i.size() - 1] - pts_i[pts_i.size() - 2]).normalized() if e_i == "end" else (pts_i[0] - pts_i[1]).normalized()
					var v_k: Vector3 = (pts_k[1] - pts_k[0]).normalized() if e_k == "start" else (pts_k[pts_k.size() - 2] - pts_k[pts_k.size() - 1]).normalized()
					var d: float = v_i.dot(v_k)
					if d > mejor_dot:
						mejor_dot = d
						idx_in = i
						idx_out = k

			if mejor_dot > 0.60:
				var ci: Dictionary = conns[idx_in] as Dictionary
				var ck: Dictionary = conns[idx_out] as Dictionary
				var si_id: String = str(ci.get("segment_id", ""))
				var sk_id: String = str(ck.get("segment_id", ""))
				var ei: String = str(ci.get("end", "start"))
				var ek: String = str(ck.get("end", "start"))
				var pts_i: Array[Vector3] = seg_puntos_map[si_id]
				var pts_k: Array[Vector3] = seg_puntos_map[sk_id]
				var vi: Vector3 = (pts_i[pts_i.size() - 1] - pts_i[pts_i.size() - 2]).normalized() if ei == "end" else (pts_i[0] - pts_i[1]).normalized()
				var vk: Vector3 = (pts_k[1] - pts_k[0]).normalized() if ek == "start" else (pts_k[pts_k.size() - 2] - pts_k[pts_k.size() - 1]).normalized()
				var t_main: Vector3 = (vi + vk).normalized()
				tangentes[si_id + "_" + ei] = t_main if ei == "end" else -t_main
				tangentes[sk_id + "_" + ek] = t_main if ek == "start" else -t_main

	return tangentes


## Carga y parsea el archivo de red JSON con caché en memoria.
func cargar_red() -> void:
	_limpiar()

	var data: Dictionary = _obtener_datos_red_json()
	if data.is_empty():
		return

	var segmentos_raw: Array = data.get("segments", []) as Array
	junctions = data.get("junctions", {}) as Dictionary

	var root_owner: Node = _obtener_root_owner()
	var t0: int = Time.get_ticks_msec()

	_recargar_journal()
	var tangentes_bordes: Dictionary = _calcular_tangentes_de_uniones(segmentos_raw)

	for seg_raw: Variant in segmentos_raw:
		if not (seg_raw is Dictionary):
			continue
		var seg: Dictionary = seg_raw as Dictionary
		var seg_id: String = str(seg.get("id", ""))
		if seg_id.is_empty():
			continue
		# Los tramos dados de baja explícitamente no se regeneran.
		if _eliminados_persistentes.has(seg_id):
			continue
		if tramos_excluidos.has(seg_id):
			continue

		var puntos_raw: Array = seg.get("points", []) as Array
		if puntos_raw.size() < 2:
			continue

		var puntos_vector: Array[Vector3] = []
		for p_raw: Variant in puntos_raw:
			if p_raw is Dictionary:
				var p: Dictionary = p_raw as Dictionary
				puntos_vector.append(Vector3(
					float(p.get("x", 0.0)),
					float(p.get("y", 0.0)),
					float(p.get("z", 0.0))
				))

		var clasificacion: Array[String] = _clasificar_segmento(seg, puntos_vector)
		var sector_nombre: String = clasificacion[0]
		var tramo_nombre: String = clasificacion[1]

		if not _segmento_pasa_filtro(seg_id, puntos_vector, sector_nombre):
			continue

		segments_data[seg_id] = seg

		var path: Path3D = EDITABLE_TRACK_SEGMENT_SCRIPT.new()
		path.name = seg_id
		path.segment_id = seg_id
		path.sector_nombre = sector_nombre
		path.tramo_nombre = tramo_nombre
		var tan_ini: Vector3 = tangentes_bordes.get(seg_id + "_start", Vector3.ZERO) as Vector3
		var tan_fin: Vector3 = tangentes_bordes.get(seg_id + "_end", Vector3.ZERO) as Vector3
		var curve: Curve3D = _construir_curva_suave(puntos_vector, tan_ini, tan_fin)
		curve.bake_interval = bake_interval
		path.curve = curve
		path.curva_original = curve.duplicate() as Curve3D

		if _ediciones_guardadas.has(seg_id):
			path.deserializar_datos(_ediciones_guardadas[seg_id] as Dictionary)
		else:
			path.esta_modificada = false
			path.estado_edicion = "Original"
		path.longitud_metros = path.curve.get_baked_length()

		if organizar_en_nodos_tramos:
			var contenedor_tramo: Node3D = _obtener_o_crear_contenedor_tramo(sector_nombre, tramo_nombre)
			contenedor_tramo.add_child(path)
		else:
			_contenedor_vias.add_child(path)

		paths[seg_id] = path

		if root_owner != null:
			path.owner = root_owner
		if path is EditableTrackSegment:
			var segmento_editable: EditableTrackSegment = path as EditableTrackSegment
			if not segmento_editable.geometria_modificada.is_connected(_on_segmento_geometria_modificada):
				segmento_editable.geometria_modificada.connect(_on_segmento_geometria_modificada)

	total_vias_editadas = _contar_ediciones_reales()

	if generar_mecanismos_visuales:
		_generar_aparatos_de_via()
		_aplicar_switches_guardados()
	_aplicar_bajas_switches_persistentes()

	var t_fin: int = Time.get_ticks_msec() - t0
	print("TrackNetwork: Red cargada en %d ms (%d segmentos, %d uniones, %d switches) desde %s" % [
		t_fin,
		paths.size(),
		junctions.size(),
		aparatos_de_via.size(),
		_obtener_ruta_red_json()
	])
	red_cargada.emit(paths.size(), junctions.size())
	habilitar_edicion_en_arbol()

	# Restaurar ediciones de estaciones desde el journal (diferido: deben estar en el árbol).
	call_deferred("aplicar_estaciones_guardadas")

	# Actualizar inmediatamente la geometría visual 3D (TrackGeometry) si existe
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")


func _clasificar_segmento(seg: Dictionary, puntos: Array[Vector3]) -> Array[String]:
	# 1. Si el JSON ya trae pre-clasificado el sector y tramo:
	if seg.has("sector") and seg.has("tramo"):
		return [str(seg["sector"]), str(seg["tramo"])]

	if puntos.is_empty():
		return ["Sector_01_Constitucion_Avellaneda", "01_Plaza_Constitucion"]

	var x_sum: float = 0.0
	var z_sum: float = 0.0
	for p: Vector3 in puntos:
		x_sum += p.x
		z_sum += p.z
	var x_avg: float = x_sum / float(puntos.size())
	var z_avg: float = z_sum / float(puntos.size())
	var seg_id: String = str(seg.get("id", ""))

	# A) Exclusiones: Vía Quilmes y colas ajenas
	# 1. Cola Bosques - Gutiérrez (al sureste de Bosques)
	if z_avg > 21750.0 and x_avg > 14200.0:
		return ["Sector_07_Colas_Y_Ramales", "Cola_Bosques_Gutierrez"]

	# 2. Ramal Quilmes (al este del corredor principal)
	if (z_avg < 17500.0 and x_avg > 1000.0) or (x_avg > 14500.0 and z_avg < 21700.0):
		if z_avg <= 14500.0:
			return ["Sector_06_Ramal_Quilmes", "01_Avellaneda_Quilmes"]
		elif z_avg <= 18000.0:
			return ["Sector_06_Ramal_Quilmes", "02_Quilmes_Berazategui"]
		else:
			return ["Sector_06_Ramal_Quilmes", "03_Berazategui_Bosques"]

	# 3. Colas sur Temperley hacia Korn / Ezeiza / Haedo
	if seg_id in ["seg_639", "seg_562", "seg_563", "seg_564", "seg_565", "seg_566", "seg_568", "seg_569", "seg_570", "seg_571", "seg_572", "seg_573", "seg_95", "seg_286", "seg_595"]:
		return ["Sector_07_Colas_Y_Ramales", "Cola_Temperley_Sur_Korn"]
	if seg_id in ["seg_79", "seg_127", "seg_128", "seg_129", "seg_131", "seg_132", "seg_133", "seg_134", "seg_337"]:
		return ["Sector_07_Colas_Y_Ramales", "Temperley_Vias_Secundarias_Sur"]

	# B) Unión y curva Temperley a Mármol (vital para no romper la red)
	if seg_id in ["seg_6", "seg_7", "seg_90", "seg_91", "seg_209", "seg_344", "seg_345", "seg_358", "seg_359", "seg_692", "seg_693", "seg_695", "seg_696", "seg_700"]:
		return ["Sector_04_Temperley_Claypole", "10_Temperley_Marmol"]

	# C) Corredor Constitución - Bosques vía Temperley:
	if z_avg <= 4500.0:
		var sec: String = "Sector_01_Constitucion_Avellaneda"
		var tra: String = "01_Plaza_Constitucion" if z_avg <= 1500.0 else ("02_Constitucion_Yrigoyen" if z_avg <= 3000.0 else "03_Yrigoyen_Avellaneda")
		return [sec, tra]
	elif z_avg <= 9800.0 and x_avg <= 1000.0:
		var sec: String = "Sector_02_Avellaneda_Lanus"
		var tra: String = "04_Avellaneda_Gerli" if z_avg <= 7500.0 else "05_Gerli_Lanus"
		return [sec, tra]
	elif z_avg <= 17500.0 and x_avg <= 1000.0:
		var sec: String = "Sector_03_Lanus_Temperley"
		var tra: String = "06_Lanus_Escalada" if z_avg <= 12000.0 else ("07_Escalada_Banfield" if z_avg <= 13800.0 else ("08_Banfield_Lomas" if z_avg <= 15500.0 else "09_Lomas_Temperley"))
		return [sec, tra]
	elif x_avg <= 7200.0:
		var sec: String = "Sector_04_Temperley_Claypole"
		var tra: String = "10_Temperley_Marmol" if x_avg <= 2000.0 else ("11_Marmol_Calzada" if x_avg <= 4500.0 else "12_Calzada_Claypole")
		return [sec, tra]
	else:
		var sec: String = "Sector_05_Claypole_Bosques"
		var tra: String = "13_Claypole_Ardigo" if x_avg <= 10000.0 else ("14_Ardigo_Varela" if x_avg <= 12200.0 else ("15_Varela_Zeballos" if x_avg <= 13500.0 else "16_Zeballos_Bosques"))
		return [sec, tra]


func _segmento_pasa_filtro(seg_id: String, puntos: Array[Vector3], sector_nombre: String) -> bool:
	if tramos_excluidos.has(seg_id) or puntos.is_empty():
		return false
	if filtro_ramal == 1:
		# Modo Toda la Red: cargar absolutamente todo
		return true

	var es_secundario: bool = sector_nombre.begins_with("Sector_06") or sector_nombre.begins_with("Sector_07") or sector_nombre == "Tramos_Excluidos"
	if solo_constitucion_bosques and es_secundario:
		return false
	if filtro_ramal == 0:
		return not es_secundario

	# filtro_ramal == 2: Rango Métrico Personalizado
	var x_sum: float = 0.0
	var z_sum: float = 0.0
	for p: Vector3 in puntos:
		x_sum += p.x
		z_sum += p.z
	var x_avg: float = x_sum / float(puntos.size())
	var z_avg: float = z_sum / float(puntos.size())
	return z_avg >= rango_z_min and z_avg <= rango_z_max and x_avg >= rango_x_min and x_avg <= rango_x_max


## Obtiene el vector unitario 2D horizontal (X, Z) que sale de una unión a lo largo de un segmento.
func _obtener_vector_salida_segmento(seg_id: String, end_tipo: String) -> Vector2:
	if not paths.has(seg_id):
		return Vector2.ZERO
	var p: Path3D = paths[seg_id] as Path3D
	if p == null or p.curve == null or p.curve.point_count < 2:
		return Vector2.ZERO

	var c: Curve3D = _curva_completa_de_path(p)
	if c == null or c.point_count < 2:
		return Vector2.ZERO
	var l: float = c.get_baked_length()
	var d_sample: float = minf(2.5, l * 0.4)

	var v3: Vector3
	if end_tipo == "start":
		v3 = (c.sample_baked(d_sample) - c.sample_baked(0.0)).normalized()
	else:
		v3 = (c.sample_baked(maxf(l - d_sample, 0.0)) - c.sample_baked(l)).normalized()

	var v2: Vector2 = Vector2(v3.x, v3.z)
	return v2.normalized() if v2.length_squared() > 1e-4 else Vector2.ZERO


## Variante tolerante para tijeras en cadena: acepta como "rama desviada" un tramo
## que sale de una unión con 4+ ramas (el centro de otro cruce/tijera) siempre que
## entre las OTRAS ramas exista una línea de paso clara (casi opuesta) y la rama
## analizada no sea colineal con ella (o sea: es una diagonal, no la vía de paso).
func _es_rama_desviada_tolerante(j_id: int, seg_id: String) -> bool:
	var j_dict: Dictionary = junctions.get(str(j_id), {}) as Dictionary
	var conns: Array = j_dict.get("segments", []) as Array
	if conns.size() < 4:
		return false
	var dirs: Dictionary = {}
	for c_raw: Variant in conns:
		if c_raw is Dictionary:
			var c: Dictionary = c_raw as Dictionary
			var sid: String = str(c.get("segment_id", ""))
			var e_t: String = str(c.get("end", "start"))
			dirs[sid] = _obtener_vector_salida_segmento(sid, e_t)
	if not dirs.has(seg_id):
		return false
	var otros: Array[String] = []
	for sid2: String in dirs.keys():
		if sid2 != seg_id:
			otros.append(sid2)
	var v_seg: Vector2 = dirs[seg_id] as Vector2
	for i: int in otros.size():
		for k: int in range(i + 1, otros.size()):
			var v_i: Vector2 = dirs[otros[i]] as Vector2
			var v_k: Vector2 = dirs[otros[k]] as Vector2
			if v_i.dot(v_k) < -0.85:
				if absf(v_seg.dot(v_i)) < 0.98 and absf(v_seg.dot(v_k)) < 0.98:
					return true
	return false


## Detecta qué segmento de una unión de 3 ramas es la vía desviada (divergente).
func _detectar_segmento_desviado_union(j_id: int) -> String:
	var j_dict: Dictionary = junctions.get(str(j_id), {}) as Dictionary
	var conns: Array = j_dict.get("segments", []) as Array
	# Sólo participan las ramas que existen: una vía eliminada/excluida devuelve
	# dirección nula y ensuciaba el cálculo del par "de paso" (llegaba a elegirse
	# como vía desviada una rama inexistente).
	var ids: Array[String] = []
	var dirs: Array[Vector2] = []
	for c_raw: Variant in conns:
		if not (c_raw is Dictionary):
			return ""
		var s_id: String = str((c_raw as Dictionary).get("segment_id", ""))
		var e_t: String = str((c_raw as Dictionary).get("end", "start"))
		var v: Vector2 = _obtener_vector_salida_segmento(s_id, e_t)
		if v.length_squared() < 1e-6:
			continue
		ids.append(s_id)
		dirs.append(v)
	if dirs.size() != 3:
		return ""

	var best_dot: float = 1.0
	var pair: Array[int] = [0, 1]
	for i: int in 3:
		for k: int in range(i + 1, 3):
			var dot_ik: float = dirs[i].dot(dirs[k])
			if dot_ik < best_dot:
				best_dot = dot_ik
				pair = [i, k]

	if best_dot < -0.6:
		var div_idx: int = 3 - pair[0] - pair[1]
		return ids[div_idx]
	return ""


## Instancia y calibra geométricamente los aparatos de vía (Tipos A, B, C, D, E) detectando
## la vía común, vía directa y vía desviada real, con su lado y ángulo de divergencia,
## organizándolos según el sector y tramo de vías al que pertenecen.
func _generar_aparatos_de_via() -> void:
	_asegurar_topologia_cargada()
	if _contenedor_switches != null:
		_limpiar_nodo_recursivo(_contenedor_switches)
	aparatos_de_via.clear()
	_switches_ordenados.clear()
	_recortes_segmentos.clear()
	_enclavamientos_crossover.clear()
	var root_owner: Node = _obtener_root_owner()
	var procesados_set: Dictionary = {}

	# -------------------------------------------------------------------------
	# 1. PRE-ANÁLISIS TOPOLÓGICO: Tijeras (Tipo E) y Crossovers (Tipo D)
	# -------------------------------------------------------------------------
	var scissors_4way_set: Dictionary = {}    # 4way_jid (int) -> Array[int] (turnouts vinculados)
	var scissors_turnout_set: Dictionary = {} # turnout_jid (int) -> 4way_jid (int)
	var crossover_pair_map: Dictionary = {}   # turnout_jid (int) -> Array [partner_jid (int), diag_sid (String)]

	# A) Detectar centros de Scissors Crossover (Tijeras en X / Bretelle):
	# Un centro 4-way cuyas 4 ramas conectan a la vía desviada de 4 desvíos distintos
	for j_key: Variant in junctions.keys():
		var j_id_int: int = int(j_key)
		var j_dict: Dictionary = junctions[j_key] as Dictionary
		var conns: Array = j_dict.get("segments", []) as Array
		if conns.size() == 4:
			var corners: Array[int] = []
			var estrictas: int = 0
			for c_raw: Variant in conns:
				if not (c_raw is Dictionary):
					continue
				var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
				if not segments_data.has(sid):
					continue
				var seg: Dictionary = segments_data[sid] as Dictionary
				var n_s: int = int(seg.get("node_start", 0))
				var n_e: int = int(seg.get("node_end", 0))
				var other_id: int = n_e if n_s == j_id_int else n_s
				if other_id != 0 and junctions.has(str(other_id)):
					if _detectar_segmento_desviado_union(other_id) == sid:
						corners.append(other_id)
						estrictas += 1
					elif _es_rama_desviada_tolerante(other_id, sid):
						# Tijeras en cadena (varias bretelles compartiendo diagonales):
						# la esquina es el centro de otro cruce/tijera, con 4+ ramas.
						corners.append(other_id)
			# Se exige que al menos 2 esquinas sean desvíos reales para no convertir
			# un cruce simple (Tipo C) en una tijera.
			if corners.size() == 4 and estrictas >= 2:
				scissors_4way_set[j_id_int] = corners
				for tid: int in corners:
					scissors_turnout_set[tid] = j_id_int

	# B) Detectar parejas de Crossover (Tipo D) entre vías paralelas conectadas por diagonal desviada
	for seg_id: String in segments_data.keys():
		var seg: Dictionary = segments_data[seg_id] as Dictionary
		var n_s: int = int(seg.get("node_start", 0))
		var n_e: int = int(seg.get("node_end", 0))
		if n_s == 0 or n_e == 0 or n_s == n_e:
			continue
		if scissors_turnout_set.has(n_s) or scissors_turnout_set.has(n_e):
			continue
		if crossover_pair_map.has(n_s) or crossover_pair_map.has(n_e):
			continue
		if _detectar_segmento_desviado_union(n_s) == seg_id and _detectar_segmento_desviado_union(n_e) == seg_id:
			var p_seg: Path3D = paths.get(seg_id) as Path3D
			var l_seg: float = p_seg.curve.get_baked_length() if (p_seg != null and p_seg.curve != null) else 999.0
			if l_seg < 120.0:
				crossover_pair_map[n_s] = [n_e, seg_id]
				crossover_pair_map[n_e] = [n_s, seg_id]
				_enclavamientos_crossover[n_s] = n_e
				_enclavamientos_crossover[n_e] = n_s

	# =========================================================================
	# ETAPA 1: TIJERAS / BRETELLES EN X (TIPO E)
	# =========================================================================
	for j_center_int: int in scissors_4way_set.keys():
		var corners: Array = scissors_4way_set[j_center_int] as Array
		var j_dict: Dictionary = junctions.get(str(j_center_int), {}) as Dictionary
		var pos_dict: Dictionary = j_dict.get("position", {}) as Dictionary
		if not pos_dict.has("x"):
			continue
		var pos_c: Vector3 = Vector3(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)), float(pos_dict.get("z", 0.0)))

		var segs_scissors: Array[String] = []
		var scissors_valida: bool = true
		for c_raw: Variant in j_dict.get("segments", []):
			if c_raw is Dictionary:
				var sid_sc: String = str((c_raw as Dictionary).get("segment_id", ""))
				segs_scissors.append(sid_sc)
				if not paths.has(sid_sc):
					scissors_valida = false
		if not scissors_valida:
			continue

		var sector_tramo: Array[String] = _determinar_sector_tramo_switch(pos_c, segs_scissors)
		if solo_constitucion_bosques:
			var sec_n: String = sector_tramo[0]
			if sec_n.begins_with("Sector_06") or sec_n.begins_with("Sector_07") or sec_n == "Tramos_Excluidos":
				continue

		# 1. Absorber las 4 diagonales centrales al 100%
		for sid: String in segs_scissors:
			_recortes_segmentos[sid] = Vector2.ZERO

		# 2. Absorber tramos paralelos entre esquinas
		for c1_raw: Variant in corners:
			var c1: int = int(c1_raw)
			for c2_raw: Variant in corners:
				var c2: int = int(c2_raw)
				if c1 < c2:
					var j_c1: Dictionary = junctions.get(str(c1), {}) as Dictionary
					for c_info: Variant in j_c1.get("segments", []):
						if c_info is Dictionary:
							var sid_c: String = str((c_info as Dictionary).get("segment_id", ""))
							if segments_data.has(sid_c):
								var s_d: Dictionary = segments_data[sid_c] as Dictionary
								var o_id: int = int(s_d.get("node_end", 0)) if int(s_d.get("node_start", 0)) == c1 else int(s_d.get("node_start", 0))
								if o_id == c2:
									_recortes_segmentos[sid_c] = Vector2.ZERO

		# 3. Orientación y dimensiones de la tijera
		var pts_in: Array[Vector3] = []
		var pts_out: Array[Vector3] = []
		for c_raw: Variant in corners:
			var cid: int = int(c_raw)
			var p_dict: Dictionary = (junctions.get(str(cid), {}) as Dictionary).get("position", {}) as Dictionary
			var cp: Vector3 = Vector3(float(p_dict.get("x", 0.0)), float(p_dict.get("y", 0.0)), float(p_dict.get("z", 0.0)))
			if cp.z <= pos_c.z:
				pts_in.append(cp)
			else:
				pts_out.append(cp)

		var fwd_sw: Vector3 = Vector3.FORWARD
		if not pts_in.is_empty() and not pts_out.is_empty():
			var avg_in: Vector3 = Vector3.ZERO
			for p: Vector3 in pts_in: avg_in += p
			avg_in /= float(pts_in.size())
			var avg_out: Vector3 = Vector3.ZERO
			for p: Vector3 in pts_out: avg_out += p
			avg_out /= float(pts_out.size())
			var d_v: Vector3 = avg_out - avg_in
			d_v.y = 0.0
			if d_v.length_squared() > 1e-4:
				fwd_sw = d_v.normalized()

		var side_sw: Vector3 = Vector3.UP.cross(fwd_sw).normalized()
		var basis_sw: Basis = Basis(side_sw, Vector3.UP, fwd_sw)
		var trans_sw: Transform3D = Transform3D(basis_sw, pos_c)

		# 4. Medir separación entre vías (distancia_ejes)
		var min_x_loc: float = 0.0
		var max_x_loc: float = 0.0
		var min_z_loc: float = -23.0
		var max_z_loc: float = 23.0
		for c_raw: Variant in corners:
			var cid: int = int(c_raw)
			var p_dict: Dictionary = (junctions.get(str(cid), {}) as Dictionary).get("position", {}) as Dictionary
			var cp: Vector3 = Vector3(float(p_dict.get("x", 0.0)), float(p_dict.get("y", 0.0)), float(p_dict.get("z", 0.0)))
			var loc: Vector3 = trans_sw.affine_inverse() * cp
			min_x_loc = minf(min_x_loc, loc.x)
			max_x_loc = maxf(max_x_loc, loc.x)
			min_z_loc = minf(min_z_loc, loc.z)
			max_z_loc = maxf(max_z_loc, loc.z)

		var dist_ejes: float = max_x_loc - min_x_loc
		if dist_ejes < 3.5 or dist_ejes > 8.0:
			dist_ejes = 5.0
		var largo_crossover_e: float = maxf(46.0, (max_z_loc - min_z_loc))

		# 5. Instanciar escena autocontenida switch_tipo_e.tscn
		var to_e: ProceduralScissorsCrossover = _instanciar_switch_tipo_e()
		to_e.name = "Tijera_Bretelle_E_%d" % j_center_int
		to_e.node_id = j_center_int
		to_e.transform = trans_sw
		to_e.distancia_ejes = dist_ejes
		to_e.largo_crossover = largo_crossover_e
		to_e.tipo_aparato_override = "TIPO_E"
		to_e.generar_extremos_flexibles = true
		to_e.construir_geometria()

		# Reajustar bornes fijos a las dimensiones reales del aparato
		var x1_e: float = -dist_ejes * 0.5
		var x2_e: float = dist_ejes * 0.5
		var z_in_e: float = -largo_crossover_e * 0.5
		var z_out_e: float = largo_crossover_e * 0.5
		var g_ext_e: Node = to_e.get_node_or_null("ExtremosFlexibles")
		if g_ext_e != null:
			var l_v1_in: FlexibleTrackLead = g_ext_e.get_node_or_null("Extremo_Via_1_Entrada") as FlexibleTrackLead
			if l_v1_in != null: l_v1_in.conectar_a_borne(Vector3(x1_e, 0.0, z_in_e), Vector3(0.0, 0.0, -1.0))
			var l_v1_out: FlexibleTrackLead = g_ext_e.get_node_or_null("Extremo_Via_1_Salida") as FlexibleTrackLead
			if l_v1_out != null: l_v1_out.conectar_a_borne(Vector3(x1_e, 0.0, z_out_e), Vector3(0.0, 0.0, 1.0))
			var l_v2_in: FlexibleTrackLead = g_ext_e.get_node_or_null("Extremo_Via_2_Entrada") as FlexibleTrackLead
			if l_v2_in != null: l_v2_in.conectar_a_borne(Vector3(x2_e, 0.0, z_in_e), Vector3(0.0, 0.0, -1.0))
			var l_v2_out: FlexibleTrackLead = g_ext_e.get_node_or_null("Extremo_Via_2_Salida") as FlexibleTrackLead
			if l_v2_out != null: l_v2_out.conectar_a_borne(Vector3(x2_e, 0.0, z_out_e), Vector3(0.0, 0.0, 1.0))

		# 6. Conectar los 4 extremos flexibles a las vías exteriores
		for c_raw: Variant in corners:
			var cid: int = int(c_raw)
			var p_dict: Dictionary = (junctions.get(str(cid), {}) as Dictionary).get("position", {}) as Dictionary
			var cp: Vector3 = Vector3(float(p_dict.get("x", 0.0)), float(p_dict.get("y", 0.0)), float(p_dict.get("z", 0.0)))
			var loc: Vector3 = trans_sw.affine_inverse() * cp

			var es_in: bool = (loc.z <= 0.0)
			var es_v1: bool = (loc.x <= 0.0)
			var lead_name: String
			if es_v1 and es_in:
				lead_name = "Extremo_Via_1_Entrada"
			elif es_v1 and not es_in:
				lead_name = "Extremo_Via_1_Salida"
			elif not es_v1 and es_in:
				lead_name = "Extremo_Via_2_Entrada"
			else:
				lead_name = "Extremo_Via_2_Salida"

			var j_c: Dictionary = junctions.get(str(cid), {}) as Dictionary
			for c_info: Variant in j_c.get("segments", []):
				if c_info is Dictionary:
					var sid_ext: String = str((c_info as Dictionary).get("segment_id", ""))
					var end_ext: String = str((c_info as Dictionary).get("end", "start"))
					if not _recortes_segmentos.has(sid_ext) or _recortes_segmentos[sid_ext] != Vector2.ZERO:
						var p_ext: Path3D = paths.get(sid_ext) as Path3D
						if p_ext != null and p_ext.curve != null:
							var l_seg_ext: float = p_ext.curve.get_baked_length()
							var trim_dist: float = minf(20.0, l_seg_ext * 0.35)
							_registrar_recorte_segmento(sid_ext, end_ext, trim_dist)
							var pt: Dictionary = _obtener_punto_recorte_segmento(p_ext, end_ext, trim_dist)
							var lead: FlexibleTrackLead = g_ext_e.get_node_or_null(lead_name) as FlexibleTrackLead if g_ext_e != null else null
							if lead != null:
								var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt["pos"] as Vector3)
								loc_pt.y = 0.0
								var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt["dir"] as Vector3)).normalized()
								lead.conectar_a_via_externa(loc_pt, loc_dir)
							break

		_registrar_switch_en_escena(to_e, j_center_int, sector_tramo, root_owner)
		procesados_set[j_center_int] = true
		for c_raw: Variant in corners:
			var cid: int = int(c_raw)
			procesados_set[cid] = true
			aparatos_de_via[cid] = to_e

	# =========================================================================
	# ETAPA 2: ESCAPES CROSSOVER ENTRE VÍAS PARALELAS EN H (TIPO D)
	# =========================================================================
	for j1_int: int in crossover_pair_map.keys():
		if procesados_set.has(j1_int):
			continue
		var pair_info: Array = crossover_pair_map[j1_int] as Array
		var j2_int: int = int(pair_info[0])
		var diag_sid: String = str(pair_info[1])
		if procesados_set.has(j2_int):
			continue

		var j1_dict: Dictionary = junctions.get(str(j1_int), {}) as Dictionary
		var _j2_dict: Dictionary = junctions.get(str(j2_int), {}) as Dictionary

		# Si el tramo diagonal no existe en paths, no generar el crossover
		if not paths.has(diag_sid):
			continue
		var p_diag: Path3D = paths.get(diag_sid) as Path3D
		if p_diag == null or p_diag.curve == null or p_diag.curve.point_count < 2:
			continue

		# Coordenadas derivadas directamente de los extremos reales de la vía existente
		var pos1: Vector3 = to_local(p_diag.to_global(p_diag.curve.get_point_position(0)))
		var pos2: Vector3 = to_local(p_diag.to_global(p_diag.curve.get_point_position(p_diag.curve.point_count - 1)))
		pos1.y = 0.0
		pos2.y = 0.0
		var pos_mid: Vector3 = (pos1 + pos2) * 0.5

		var sector_tramo: Array[String] = _determinar_sector_tramo_switch(pos_mid, [diag_sid])
		if solo_constitucion_bosques:
			var sec_n: String = sector_tramo[0]
			if sec_n.begins_with("Sector_06") or sec_n.begins_with("Sector_07") or sec_n == "Tramos_Excluidos":
				continue

		# 1. Absorber el tramo diagonal de enlace al 100%
		_recortes_segmentos[diag_sid] = Vector2.ZERO

		# 2. Orientación a lo largo de la traza de la vía principal de J1
		var fwd_sw: Vector3 = Vector3.FORWARD
		var ext_conns_1: Array[Dictionary] = []
		for c_raw: Variant in j1_dict.get("segments", []):
			if c_raw is Dictionary:
				var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
				if sid != diag_sid and paths.has(sid):
					ext_conns_1.append(c_raw as Dictionary)

		if ext_conns_1.size() >= 2:
			var v0: Vector2 = _obtener_vector_salida_segmento(str(ext_conns_1[0]["segment_id"]), str(ext_conns_1[0]["end"]))
			var v1: Vector2 = _obtener_vector_salida_segmento(str(ext_conns_1[1]["segment_id"]), str(ext_conns_1[1]["end"]))
			var dir_2d: Vector2 = (v1 - v0).normalized()
			var v_diag: Vector2 = Vector2(pos2.x - pos1.x, pos2.z - pos1.z)
			if dir_2d.dot(v_diag) < 0.0:
				dir_2d = -dir_2d
			fwd_sw = Vector3(dir_2d.x, 0.0, dir_2d.y).normalized()
		else:
			var dz_test: Vector3 = (pos2 - pos1)
			dz_test.y = 0.0
			fwd_sw = dz_test.normalized() if dz_test.length_squared() > 1e-4 else Vector3.FORWARD

		var side_sw: Vector3 = Vector3.UP.cross(fwd_sw).normalized()
		var basis_sw: Basis = Basis(side_sw, Vector3.UP, fwd_sw)
		var trans_sw: Transform3D = Transform3D(basis_sw, pos_mid)

		# 3. Medir separación entre vías y longitud
		var p1_loc: Vector3 = trans_sw.affine_inverse() * pos1
		var p2_loc: Vector3 = trans_sw.affine_inverse() * pos2
		var dist_ejes: float = absf(p2_loc.x - p1_loc.x)
		if dist_ejes < 3.5 or dist_ejes > 8.0:
			dist_ejes = 5.0
		var largo_crossover_d: float = maxf(44.0, absf(p2_loc.z - p1_loc.z) + 16.0)

		# Si p1_loc.x < p2_loc.x, la diagonal va de Vía 1 a Vía 2 (+X).
		# Si p1_loc.x > p2_loc.x, la diagonal va de Vía 2 a Vía 1 (-X, invertida).
		var es_diagonal_inv: bool = (p1_loc.x > p2_loc.x)

		# 4. Instanciar escena autocontenida switch_tipo_d.tscn
		var to_d: ProceduralCrossover = _instanciar_switch_tipo_d()
		to_d.name = "Escape_Crossover_D_%d_%d" % [j1_int, j2_int]
		to_d.node_id = j1_int
		to_d.transform = trans_sw
		to_d.distancia_ejes = dist_ejes
		to_d.largo_crossover = largo_crossover_d
		to_d.diagonal_invertida = es_diagonal_inv
		to_d.tipo_aparato_override = "TIPO_D"
		to_d.generar_extremos_flexibles = true
		to_d.construir_geometria()

		# Reajustar bornes fijos a las dimensiones reales del crossover
		var x1_d: float = -dist_ejes * 0.5
		var x2_d: float = dist_ejes * 0.5
		var z_in_d: float = -largo_crossover_d * 0.5
		var z_out_d: float = largo_crossover_d * 0.5
		var g_ext_d: Node = to_d.get_node_or_null("ExtremosFlexibles")
		if g_ext_d != null:
			var l_v1_in: FlexibleTrackLead = g_ext_d.get_node_or_null("Extremo_Via_1_Entrada") as FlexibleTrackLead
			if l_v1_in != null: l_v1_in.conectar_a_borne(Vector3(x1_d, 0.0, z_in_d), Vector3(0.0, 0.0, -1.0))
			var l_v1_out: FlexibleTrackLead = g_ext_d.get_node_or_null("Extremo_Via_1_Salida") as FlexibleTrackLead
			if l_v1_out != null: l_v1_out.conectar_a_borne(Vector3(x1_d, 0.0, z_out_d), Vector3(0.0, 0.0, 1.0))
			var l_v2_in: FlexibleTrackLead = g_ext_d.get_node_or_null("Extremo_Via_2_Entrada") as FlexibleTrackLead
			if l_v2_in != null: l_v2_in.conectar_a_borne(Vector3(x2_d, 0.0, z_in_d), Vector3(0.0, 0.0, -1.0))
			var l_v2_out: FlexibleTrackLead = g_ext_d.get_node_or_null("Extremo_Via_2_Salida") as FlexibleTrackLead
			if l_v2_out != null: l_v2_out.conectar_a_borne(Vector3(x2_d, 0.0, z_out_d), Vector3(0.0, 0.0, 1.0))

		# 5. Conectar los 4 extremos flexibles
		for j_cur: int in [j1_int, j2_int]:
			var j_c_dict: Dictionary = junctions.get(str(j_cur), {}) as Dictionary
			var p_c_loc: Vector3 = trans_sw.affine_inverse() * (pos1 if j_cur == j1_int else pos2)
			var es_v1: bool = (p_c_loc.x <= 0.0)

			for c_raw: Variant in j_c_dict.get("segments", []):
				if not (c_raw is Dictionary):
					continue
				var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
				if sid == diag_sid or not paths.has(sid):
					continue
				var end_t: String = str((c_raw as Dictionary).get("end", "start"))
				var p_seg: Path3D = paths[sid] as Path3D
				if p_seg == null or p_seg.curve == null:
					continue

				var out_vec_2d: Vector2 = _obtener_vector_salida_segmento(sid, end_t)
				var out_loc: Vector3 = (trans_sw.basis.inverse() * Vector3(out_vec_2d.x, 0.0, out_vec_2d.y)).normalized()
				var l_seg: float = p_seg.curve.get_baked_length()

				# Si out_loc.z < 0.0 se aleja hacia atrás (Entrada), si >= 0.0 hacia adelante (Salida)
				var es_in: bool = (out_loc.z < 0.0)
				var dist_al_borne: float = (p_c_loc.z - z_in_d) if es_in else (z_out_d - p_c_loc.z)
				dist_al_borne = maxf(0.0, dist_al_borne)

				var lead_name: String
				if es_v1 and es_in:
					lead_name = "Extremo_Via_1_Entrada"
				elif es_v1 and not es_in:
					lead_name = "Extremo_Via_1_Salida"
				elif not es_v1 and es_in:
					lead_name = "Extremo_Via_2_Entrada"
				else:
					lead_name = "Extremo_Via_2_Salida"

				var lead: FlexibleTrackLead = g_ext_d.get_node_or_null(lead_name) as FlexibleTrackLead if g_ext_d != null else null

				if l_seg < dist_al_borne + 6.0:
					_recortes_segmentos[sid] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(sid, j_cur)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					if lead != null:
						lead.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, sid, end_t))
				else:
					var trim_dist: float = maxf(4.0, dist_al_borne + 2.0)
					_registrar_recorte_segmento(sid, end_t, trim_dist)
					var pt: Dictionary = _obtener_punto_recorte_segmento(p_seg, end_t, trim_dist)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt["pos"] as Vector3)
					loc_pt.y = 0.0
					var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt["dir"] as Vector3)).normalized()
					if lead != null:
						lead.conectar_a_via_externa(loc_pt, loc_dir)

		_registrar_switch_en_escena(to_d, j1_int, sector_tramo, root_owner)
		procesados_set[j1_int] = true
		procesados_set[j2_int] = true
		aparatos_de_via[j2_int] = to_d

	# =========================================================================
	# ETAPA 3: CRUCES DE VÍAS A NIVEL EN X / DIAMANTE (TIPO C)
	# =========================================================================
	for j_key: Variant in junctions.keys():
		var j_id_int: int = int(j_key)
		if procesados_set.has(j_id_int):
			continue
		var j_dict: Dictionary = junctions[j_key] as Dictionary
		var conexiones: Array = j_dict.get("segments", []) as Array
		if conexiones.size() < 4:
			continue

		var datos_conns: Array[Dictionary] = []
		var seg_ids_para_clasificar: Array[String] = []
		for c_raw: Variant in conexiones:
			if c_raw is Dictionary:
				var s_id: String = str((c_raw as Dictionary).get("segment_id", ""))
				var end_t: String = str((c_raw as Dictionary).get("end", "start"))
				seg_ids_para_clasificar.append(s_id)
				if paths.has(s_id):
					var vec: Vector2 = _obtener_vector_salida_segmento(s_id, end_t)
					if vec != Vector2.ZERO:
						datos_conns.append({"segment_id": s_id, "end": end_t, "vector": vec})

		if datos_conns.size() < 4:
			continue

		var sum_pos: Vector3 = Vector3.ZERO
		for d_c: Dictionary in datos_conns:
			var p_c_path: Path3D = paths.get(str(d_c["segment_id"])) as Path3D
			if p_c_path != null and p_c_path.curve != null and p_c_path.curve.point_count > 0:
				var e_idx: int = 0 if str(d_c["end"]) == "start" else (p_c_path.curve.point_count - 1)
				sum_pos += to_local(p_c_path.to_global(p_c_path.curve.get_point_position(e_idx)))
		var pos_sw: Vector3 = sum_pos / 4.0
		pos_sw.y = 0.0

		var sector_tramo: Array[String] = _determinar_sector_tramo_switch(pos_sw, seg_ids_para_clasificar)
		if solo_constitucion_bosques:
			var sec_n: String = sector_tramo[0]
			if sec_n.begins_with("Sector_06") or sec_n.begins_with("Sector_07") or sec_n == "Tramos_Excluidos":
				continue

		var pair1: Array[int] = []
		var best_opp_dot: float = 2.0
		for i: int in 4:
			for k: int in range(i + 1, 4):
				var dot_ik: float = (datos_conns[i]["vector"] as Vector2).dot(datos_conns[k]["vector"] as Vector2)
				if dot_ik < best_opp_dot:
					best_opp_dot = dot_ik
					pair1 = [i, k]

		var pair2: Array[int] = []
		for idx: int in 4:
			if idx != pair1[0] and idx != pair1[1]:
				pair2.append(idx)

		var v_a0: Vector2 = datos_conns[pair1[0]]["vector"] as Vector2
		var v_a1: Vector2 = datos_conns[pair1[1]]["vector"] as Vector2
		var dir_a_2d: Vector2 = (v_a1 - v_a0).normalized()
		var c_a_in: Dictionary = datos_conns[pair1[0]] if v_a0.dot(dir_a_2d) < 0.0 else datos_conns[pair1[1]]
		var c_a_out: Dictionary = datos_conns[pair1[1]] if v_a0.dot(dir_a_2d) < 0.0 else datos_conns[pair1[0]]

		var v_b0: Vector2 = datos_conns[pair2[0]]["vector"] as Vector2
		var v_b1: Vector2 = datos_conns[pair2[1]]["vector"] as Vector2
		var dir_b_2d: Vector2 = (v_b1 - v_b0).normalized()
		if dir_b_2d.dot(dir_a_2d) < 0.0:
			dir_b_2d = -dir_b_2d
		var c_b_in: Dictionary = datos_conns[pair2[0]] if v_b0.dot(dir_b_2d) < 0.0 else datos_conns[pair2[1]]
		var c_b_out: Dictionary = datos_conns[pair2[1]] if v_b0.dot(dir_b_2d) < 0.0 else datos_conns[pair2[0]]

		var cos_ab: float = clampf(absf(dir_a_2d.dot(dir_b_2d)), 0.0, 0.999)
		var ang_cruce: float = acos(cos_ab)

		var fwd_sw: Vector3 = Vector3(dir_a_2d.x, 0.0, dir_a_2d.y).normalized()
		var side_sw: Vector3 = Vector3.UP.cross(fwd_sw).normalized()
		var basis_sw: Basis = Basis(side_sw, Vector3.UP, fwd_sw)
		var trans_sw: Transform3D = Transform3D(basis_sw, pos_sw)

		var semi_l: float = 10.0
		var c_a_curve: Curve3D = Curve3D.new()
		c_a_curve.add_point(Vector3(0.0, 0.0, -semi_l))
		c_a_curve.add_point(Vector3(0.0, 0.0, semi_l))

		var dir_b_loc: Vector3 = (trans_sw.basis.inverse() * Vector3(dir_b_2d.x, 0.0, dir_b_2d.y)).normalized()
		var c_b_curve: Curve3D = Curve3D.new()
		c_b_curve.add_point(-dir_b_loc * semi_l)
		c_b_curve.add_point(dir_b_loc * semi_l)

		var to_c: ProceduralCrossing = _instanciar_switch_tipo_c()
		to_c.name = "CruceDiamante_C_%d" % j_id_int
		to_c.node_id = j_id_int
		to_c.transform = trans_sw
		to_c.angulo_cruce_rad = ang_cruce
		to_c.largo_zona_cruce = 20.0
		to_c.curva_a = c_a_curve
		to_c.curva_b = c_b_curve
		to_c.tipo_aparato_override = "TIPO_C"
		to_c.generar_extremos_flexibles = true
		to_c.construir_geometria()

		var semi_largo_real: float = to_c.largo_zona_cruce * 0.5
		var dist_minima_recorte: float = semi_largo_real + 2.0

		var g_ext_c: Node = to_c.get_node_or_null("ExtremosFlexibles")
		var conns_info: Array[Dictionary] = [
			{"conn": c_a_in, "lead": "Extremo_Via_A_Entrada", "fwd_def": Vector3.BACK},
			{"conn": c_a_out, "lead": "Extremo_Via_A_Salida", "fwd_def": Vector3.FORWARD},
			{"conn": c_b_in, "lead": "Extremo_Via_B_Entrada", "fwd_def": -dir_b_loc},
			{"conn": c_b_out, "lead": "Extremo_Via_B_Salida", "fwd_def": dir_b_loc}
		]
		for c_item: Dictionary in conns_info:
			var c_dat: Dictionary = c_item["conn"] as Dictionary
			var s_id: String = str(c_dat["segment_id"])
			var end_t: String = str(c_dat["end"])
			var p_seg: Path3D = paths.get(s_id) as Path3D
			var lead: FlexibleTrackLead = g_ext_c.get_node_or_null(str(c_item["lead"])) as FlexibleTrackLead if g_ext_c != null else null
			if p_seg != null and p_seg.curve != null:
				var l_seg: float = p_seg.curve.get_baked_length()
				if l_seg < dist_minima_recorte + 4.0:
					_recortes_segmentos[s_id] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(s_id, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					if lead != null:
						lead.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, s_id, end_t))
				else:
					var trim_dist: float = minf(dist_minima_recorte, l_seg - 2.0)
					_registrar_recorte_segmento(s_id, end_t, trim_dist)
					var pt: Dictionary = _obtener_punto_recorte_segmento(p_seg, end_t, trim_dist)
					if lead != null:
						var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt["pos"] as Vector3)
						loc_pt.y = 0.0
						var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt["dir"] as Vector3)).normalized()
						lead.conectar_a_via_externa(loc_pt, loc_dir)

		_registrar_switch_en_escena(to_c, j_id_int, sector_tramo, root_owner)
		procesados_set[j_id_int] = true

	# =========================================================================
	# ETAPA 4: DESVÍOS INDIVIDUALES SIMPLES Y SIMÉTRICOS (TIPO A Y TIPO B)
	# =========================================================================
	for j_key: Variant in junctions.keys():
		var j_id_int: int = int(j_key)
		if procesados_set.has(j_id_int):
			continue
		var j_dict: Dictionary = junctions[j_key] as Dictionary
		var conexiones: Array = j_dict.get("segments", []) as Array
		var es_tag_switch: bool = bool(j_dict.get("is_switch", false))
		if not es_tag_switch and conexiones.size() < 3:
			continue

		var datos_conns: Array[Dictionary] = []
		var seg_ids_para_clasificar: Array[String] = []
		for c_raw: Variant in conexiones:
			if c_raw is Dictionary:
				var s_id: String = str((c_raw as Dictionary).get("segment_id", ""))
				var end_t: String = str((c_raw as Dictionary).get("end", "start"))
				seg_ids_para_clasificar.append(s_id)
				if paths.has(s_id):
					var vec: Vector2 = _obtener_vector_salida_segmento(s_id, end_t)
					if vec != Vector2.ZERO:
						datos_conns.append({"segment_id": s_id, "end": end_t, "vector": vec})

		if datos_conns.size() < 3:
			continue

		# 1. Identificar par de paso continuo (dot ~ -1)
		var best_through_dot: float = 1.0
		var pair_through: Array[int] = [0, 1]
		for i: int in 3:
			for k: int in range(i + 1, 3):
				var dot_ik: float = (datos_conns[i]["vector"] as Vector2).dot(datos_conns[k]["vector"] as Vector2)
				if dot_ik < best_through_dot:
					best_through_dot = dot_ik
					pair_through = [i, k]

		var div_idx: int = 0
		for idx: int in 3:
			if idx != pair_through[0] and idx != pair_through[1]:
				div_idx = idx
				break
		var desv_conn: Dictionary = datos_conns[div_idx]
		var desv_vec: Vector2 = desv_conn["vector"] as Vector2

		var c0: Dictionary = datos_conns[pair_through[0]]
		var c1: Dictionary = datos_conns[pair_through[1]]
		var dot0: float = (c0["vector"] as Vector2).dot(desv_vec)
		var stem_conn: Dictionary = c0 if dot0 < 0.0 else c1
		var dir_conn: Dictionary = c1 if dot0 < 0.0 else c0

		var stem_id: String = str(stem_conn["segment_id"])
		var tr_dir: String = str(dir_conn["segment_id"])
		var tr_desv: String = str(desv_conn["segment_id"])

		var p_stem: Path3D = paths.get(stem_id) as Path3D
		var p_dir: Path3D = paths.get(tr_dir) as Path3D
		var p_desv: Path3D = paths.get(tr_desv) as Path3D
		if p_dir == null or p_desv == null or p_stem == null or p_stem.curve == null or p_dir.curve == null or p_desv.curve == null:
			continue

		# Posición 3D calculada directamente del extremo del tramo común existente en la escena
		var end_stem_str: String = str(stem_conn["end"])
		var idx_stem: int = 0 if end_stem_str == "start" else (p_stem.curve.point_count - 1)
		var pt_stem_loc: Vector3 = p_stem.curve.get_point_position(idx_stem)
		var pos_sw: Vector3 = to_local(p_stem.to_global(pt_stem_loc))
		pos_sw.y = 0.0

		var sector_tramo: Array[String] = _determinar_sector_tramo_switch(pos_sw, seg_ids_para_clasificar)
		if solo_constitucion_bosques:
			var sec_n: String = sector_tramo[0]
			if sec_n.begins_with("Sector_06") or sec_n.begins_with("Sector_07") or sec_n == "Tramos_Excluidos":
				continue

		var l_dir: float = p_dir.curve.get_baked_length()
		var l_desv: float = p_desv.curve.get_baked_length()
		var l_stem: float = p_stem.curve.get_baked_length()

		var fwd_stem_2d: Vector2 = -(stem_conn["vector"] as Vector2)
		var fwd_sw_3d: Vector3 = Vector3(fwd_stem_2d.x, 0.0, fwd_stem_2d.y).normalized()
		if fwd_sw_3d.is_zero_approx():
			fwd_sw_3d = Vector3.FORWARD
		var side_sw: Vector3 = Vector3.UP.cross(fwd_sw_3d).normalized()
		var basis_sw: Basis = Basis(side_sw, Vector3.UP, fwd_sw_3d)
		var trans_sw: Transform3D = Transform3D(basis_sw, pos_sw)

		var desv_loc: Vector3 = trans_sw.basis.inverse() * Vector3(desv_vec.x, 0.0, desv_vec.y)
		var dir_loc: Vector3 = trans_sw.basis.inverse() * Vector3((dir_conn["vector"] as Vector2).x, 0.0, (dir_conn["vector"] as Vector2).y)
		var es_izq: bool = (desv_loc.x < 0.0)
		var es_simetrico: bool = absf(dir_loc.x) > 0.35 and absf(desv_loc.x) > 0.35

		var ap_single: BaseTurnout = null

		if es_simetrico:
			var to_b: ProceduralSymmetricalTurnout = _instanciar_switch_tipo_b()
			to_b.name = "DesvioSimetrico_B_%d" % j_id_int
			to_b.node_id = j_id_int
			to_b.transform = trans_sw
			to_b.via_comun_id = stem_id
			to_b.via_directa_id = tr_dir
			to_b.via_desviada_id = tr_desv
			to_b.largo_turnout = 20.0
			to_b.tipo_aparato_override = "TIPO_B"
			to_b.generar_extremos_flexibles = true
			to_b.construir_geometria()

			# Stem común
			var lead_stem: FlexibleTrackLead = to_b.get_node_or_null("ExtremosFlexibles/Extremo_Entrada_Comun") as FlexibleTrackLead
			if lead_stem != null:
				if l_stem < 10.0:
					_recortes_segmentos[stem_id] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(stem_id, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					lead_stem.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, stem_id, str(stem_conn["end"])))
				else:
					var l_lead_in: float = minf(6.0, maxf(2.0, l_stem - 2.0))
					_registrar_recorte_segmento(stem_id, str(stem_conn["end"]), l_lead_in)
					var pt_stem: Dictionary = _obtener_punto_recorte_segmento(p_stem, str(stem_conn["end"]), l_lead_in)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt_stem["pos"] as Vector3)
					loc_pt.y = 0.0
					var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt_stem["dir"] as Vector3)).normalized()
					lead_stem.conectar_a_via_externa(loc_pt, loc_dir)

			# Rama izquierda
			var conn_izq: Dictionary = desv_conn if es_izq else dir_conn
			var s_izq_id: String = str(conn_izq["segment_id"])
			var p_izq_seg: Path3D = paths.get(s_izq_id) as Path3D
			var l_izq_val: float = l_desv if es_izq else l_dir
			var lead_izq: FlexibleTrackLead = to_b.get_node_or_null("ExtremosFlexibles/Extremo_Salida_Izquierda") as FlexibleTrackLead
			if lead_izq != null and p_izq_seg != null:
				if l_izq_val < 24.0:
					_recortes_segmentos[s_izq_id] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(s_izq_id, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var l_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					l_pt.y = 0.0
					lead_izq.conectar_a_via_externa(l_pt, _dir_local_hacia_extremo_opuesto(trans_sw, s_izq_id, str(conn_izq["end"])))
				else:
					var tr_izq: float = minf(24.0, l_izq_val - 2.0)
					_registrar_recorte_segmento(s_izq_id, str(conn_izq["end"]), tr_izq)
					var pt_i: Dictionary = _obtener_punto_recorte_segmento(p_izq_seg, str(conn_izq["end"]), tr_izq)
					var l_pt: Vector3 = trans_sw.affine_inverse() * (pt_i["pos"] as Vector3)
					l_pt.y = 0.0
					var l_d: Vector3 = (trans_sw.basis.inverse() * (pt_i["dir"] as Vector3)).normalized()
					lead_izq.conectar_a_via_externa(l_pt, l_d)

			# Rama derecha
			var conn_der: Dictionary = dir_conn if es_izq else desv_conn
			var s_der_id: String = str(conn_der["segment_id"])
			var p_der_seg: Path3D = paths.get(s_der_id) as Path3D
			var l_der_val: float = l_dir if es_izq else l_desv
			var lead_der: FlexibleTrackLead = to_b.get_node_or_null("ExtremosFlexibles/Extremo_Salida_Derecha") as FlexibleTrackLead
			if lead_der != null and p_der_seg != null:
				if l_der_val < 24.0:
					_recortes_segmentos[s_der_id] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(s_der_id, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var l_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					l_pt.y = 0.0
					lead_der.conectar_a_via_externa(l_pt, _dir_local_hacia_extremo_opuesto(trans_sw, s_der_id, str(conn_der["end"])))
				else:
					var tr_der: float = minf(24.0, l_der_val - 2.0)
					_registrar_recorte_segmento(s_der_id, str(conn_der["end"]), tr_der)
					var pt_d: Dictionary = _obtener_punto_recorte_segmento(p_der_seg, str(conn_der["end"]), tr_der)
					var l_pt: Vector3 = trans_sw.affine_inverse() * (pt_d["pos"] as Vector3)
					l_pt.y = 0.0
					var l_d: Vector3 = (trans_sw.basis.inverse() * (pt_d["dir"] as Vector3)).normalized()
					lead_der.conectar_a_via_externa(l_pt, l_d)

			ap_single = to_b
		else:
			var to_a: ProceduralTurnout = _instanciar_switch_tipo_a()
			to_a.name = "Desvio_%s_%d" % [("A" if es_izq else "B"), j_id_int]
			to_a.node_id = j_id_int
			to_a.transform = trans_sw
			to_a.via_comun_id = stem_id
			to_a.via_directa_id = tr_dir
			to_a.via_desviada_id = tr_desv
			to_a.largo_turnout = 28.0
			to_a.tipo_aparato_override = "TIPO_A" if es_izq else "TIPO_B"
			if not es_izq:
				to_a.curva_desviada = _crear_curva_desviada_estandar_derecha()
				var g_ext_a: Node = to_a.get_node_or_null("ExtremosFlexibles")
				var l_desv_node: FlexibleTrackLead = g_ext_a.get_node_or_null("Extremo_Salida_Desviada") as FlexibleTrackLead if g_ext_a != null else null
				if l_desv_node != null:
					l_desv_node.conectar_a_borne(Vector3(2.8, 0.0, 28.0), Vector3(0.09293, 0.0, 0.99567))

			to_a.generar_extremos_flexibles = true
			to_a.construir_geometria()

			# Stem común
			var lead_stem: FlexibleTrackLead = to_a.get_node_or_null("ExtremosFlexibles/Extremo_Entrada_Comun") as FlexibleTrackLead
			if lead_stem != null:
				if l_stem < 10.0:
					_recortes_segmentos[stem_id] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(stem_id, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					lead_stem.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, stem_id, str(stem_conn["end"])))
				else:
					var l_lead_in: float = minf(6.0, maxf(2.0, l_stem - 2.0))
					_registrar_recorte_segmento(stem_id, str(stem_conn["end"]), l_lead_in)
					var pt_stem: Dictionary = _obtener_punto_recorte_segmento(p_stem, str(stem_conn["end"]), l_lead_in)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt_stem["pos"] as Vector3)
					loc_pt.y = 0.0
					var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt_stem["dir"] as Vector3)).normalized()
					lead_stem.conectar_a_via_externa(loc_pt, loc_dir)

			# Vía directa
			var lead_dir: FlexibleTrackLead = to_a.get_node_or_null("ExtremosFlexibles/Extremo_Salida_Directa") as FlexibleTrackLead
			if lead_dir != null:
				if l_dir < 32.0:
					_recortes_segmentos[tr_dir] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(tr_dir, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					lead_dir.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, tr_dir, str(dir_conn["end"])))
				else:
					var trim_dir: float = minf(34.0, l_dir - 2.0)
					_registrar_recorte_segmento(tr_dir, str(dir_conn["end"]), trim_dir)
					var pt_dir: Dictionary = _obtener_punto_recorte_segmento(p_dir, str(dir_conn["end"]), trim_dir)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt_dir["pos"] as Vector3)
					loc_pt.y = 0.0
					var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt_dir["dir"] as Vector3)).normalized()
					lead_dir.conectar_a_via_externa(loc_pt, loc_dir)

			# Vía desviada
			var lead_desv: FlexibleTrackLead = to_a.get_node_or_null("ExtremosFlexibles/Extremo_Salida_Desviada") as FlexibleTrackLead
			if lead_desv != null:
				if l_desv < 32.0:
					_recortes_segmentos[tr_desv] = Vector2.ZERO
					var o_id: int = _obtener_otro_extremo_segmento(tr_desv, j_id_int)
					var p_oth: Vector3 = _obtener_posicion_junction(o_id)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * p_oth
					loc_pt.y = 0.0
					lead_desv.conectar_a_via_externa(loc_pt, _dir_local_hacia_extremo_opuesto(trans_sw, tr_desv, str(desv_conn["end"])))
				else:
					var trim_desv: float = minf(34.0, l_desv - 2.0)
					_registrar_recorte_segmento(tr_desv, str(desv_conn["end"]), trim_desv)
					var pt_desv: Dictionary = _obtener_punto_recorte_segmento(p_desv, str(desv_conn["end"]), trim_desv)
					var loc_pt: Vector3 = trans_sw.affine_inverse() * (pt_desv["pos"] as Vector3)
					loc_pt.y = 0.0
					var loc_dir: Vector3 = (trans_sw.basis.inverse() * (pt_desv["dir"] as Vector3)).normalized()
					lead_desv.conectar_a_via_externa(loc_pt, loc_dir)

			ap_single = to_a

		_registrar_switch_en_escena(ap_single, j_id_int, sector_tramo, root_owner)
		procesados_set[j_id_int] = true

	_reconstruir_conexiones_adaptativas()

	for nid: int in aparatos_de_via.keys():
		if not _switches_ordenados.has(nid):
			_switches_ordenados.append(nid)
	_switches_ordenados.sort_custom(func(a: int, b: int) -> bool:
		var ap_a: BaseTurnout = aparatos_de_via[a] as BaseTurnout
		var ap_b: BaseTurnout = aparatos_de_via[b] as BaseTurnout
		if ap_a == null or ap_b == null:
			return false
		return ap_a.global_position.z < ap_b.global_position.z
	)

	if not _switches_ordenados.is_empty():
		_seleccionar_switch_por_indice(switch_indice_inspeccion)


func _registrar_switch_en_escena(sw: BaseTurnout, node_id: int, sector_tramo: Array[String], root_owner: Node) -> void:
	if sw == null:
		return

	if switch_states.has(node_id):
		var estado_guardado: bool = (str(switch_states[node_id]) == sw.via_desviada_id)
		sw.conmutar_a(1 if estado_guardado else 0)
	else:
		switch_states[node_id] = sw.via_directa_id

	sw.estado_cambiado.connect(func(desv_val: Variant) -> void:
		var desv_b: bool = bool(desv_val)
		var seg_activo: String = sw.get_segmento_activo()
		switch_states[node_id] = seg_activo
		switch_conmutado.emit(node_id, seg_activo)
		switch_movido.emit(node_id, desv_b, seg_activo)
	)

	var contenedor_destino: Node3D = _contenedor_switches
	if organizar_en_nodos_tramos:
		contenedor_destino = _obtener_o_crear_contenedor_switch_tramo(sector_tramo[0], sector_tramo[1])

	var nodo_existente: Node = contenedor_destino.get_node_or_null(NodePath(str(sw.name)))
	if nodo_existente != null and nodo_existente != sw:
		nodo_existente.owner = null
		contenedor_destino.remove_child(nodo_existente)
		nodo_existente.free()
	contenedor_destino.add_child(sw)
	aparatos_de_via[node_id] = sw

	if root_owner != null:
		sw.owner = root_owner


func _reconstruir_conexiones_adaptativas() -> void:
	if _conexiones_switch_segmento.has("_en_proceso"):
		return
	_conexiones_switch_segmento["_en_proceso"] = true
	var t_debug: int = Time.get_ticks_msec()
	_depurar_tramos_invalidos()
	_encajar_extremos_a_uniones()
	_recortes_segmentos.clear()
	_recortes_extra.clear()
	_conflictos_adaptacion_switch.clear()
	_segmentos_reemplazados_por_switch.clear()

	var aparatos_unicos: Dictionary = {}
	var junctions_por_aparato: Dictionary = {}
	# Enclavamientos de escapes gemelos: se detecta UNA vez por reconstrucción
	# (antes nunca se llamaba y la tijera/escape doble no enlazaba sus agujas).
	if _enclavamientos_crossover.is_empty():
		_detectar_enclavamientos_crossover()
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var instance_id: int = sw.get_instance_id()
		aparatos_unicos[instance_id] = sw
		# NOTA: `as Array[int]` sobre un Array sin tipar devuelve null y rompe la
		# reconstrucción completa de conexiones. Se construye la lista tipada a mano.
		var ids: Array[int] = []
		if junctions_por_aparato.has(instance_id):
			for v: Variant in (junctions_por_aparato[instance_id] as Array):
				ids.append(int(v))
		if not ids.has(nid):
			ids.append(nid)
		junctions_por_aparato[instance_id] = ids

	for instance_id: int in aparatos_unicos.keys():
		var sw: BaseTurnout = aparatos_unicos[instance_id] as BaseTurnout
		var jids: Array[int] = []
		for v: Variant in (junctions_por_aparato[instance_id] as Array):
			jids.append(int(v))
		_reconstruir_aparato(sw, jids)

	_conexiones_switch_segmento.erase("_en_proceso")
	if debug_tiempos:
		print("TrackNetwork[t]: reconexión completa en %d ms (%d aparatos)" % [
			Time.get_ticks_msec() - t_debug, aparatos_unicos.size()
		])


## Re-ancla los extremos flexibles de UN aparato y registra los recortes de vía real
## de sus ramas. Extraído de `_reconstruir_conexiones_adaptativas` para poder reusarlo
## en reconstrucciones LOCALES (edición de un tramo) sin tocar toda la red.
func _reconstruir_aparato(sw: BaseTurnout, junction_ids: Array[int]) -> void:
	if sw == null:
		return
	# 1. Mapeo a escala real: el aparato copia la geometría real de las vías.
	if recalibrar_aparatos_con_via_real:
		_reubicar_aparato_sobre_via_real(sw)
	# 2. Metadata de líneas para cruces/tijeras: sin esto, el tren elegía rama al azar.
	_asegurar_metadata_lineas(sw)

	var junction_set: Dictionary = {}
	for jid: int in junction_ids:
		junction_set[jid] = true

	# Los segmentos cuyos dos extremos pertenecen al mismo aparato son internos.
	# Su geometría normal queda completamente absorbida por el cuerpo del switch.
	for jid: int in junction_ids:
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if not (c_raw is Dictionary):
				continue
			var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
			if sid.is_empty() or not paths.has(sid):
				continue
			if _segmento_interno_de_aparato(sid, junction_set):
				# Solo los segmentos internos al aparato se absorben completamente.
				# Los segmentos externos conservan su tramo útil fuera del corte.
				_segmentos_reemplazados_por_switch[sid] = true
				_recortes_segmentos[sid] = Vector2.ZERO

	var leads_usados: Dictionary = {}
	for jid: int in junction_ids:
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if not (c_raw is Dictionary):
				continue
			var c: Dictionary = c_raw as Dictionary
			var sid: String = str(c.get("segment_id", ""))
			if sid.is_empty() or not paths.has(sid) or _segmento_interno_de_aparato(sid, junction_set):
				continue
			var end_tipo: String = str(c.get("end", "start"))
			var p_seg: Path3D = paths[sid] as Path3D
			if p_seg == null or p_seg.curve == null:
				continue
			# El corte pertenece a la conexión topológica, no al éxito de
			# encontrar un nodo visual FlexibleTrackLead. El largo lo aporta
			# el puerto del aparato para no absorber traza real de más.
			var lead: FlexibleTrackLead = _seleccionar_lead_para_conexion(sw, p_seg, end_tipo, leads_usados)
			# Extremo fijado a mano por el usuario: se respeta y sólo se corta la
			# vía real donde ese extremo realmente llega.
			if lead != null and lead.respetar_edicion_manual:
				leads_usados[lead.get_instance_id()] = true
				_registrar_recorte_en_extremo_manual(lead, p_seg, sid, end_tipo)
				continue
			var distancia_corte: float = _calcular_distancia_adaptativa(p_seg, end_tipo, lead)
			_registrar_recorte_segmento(sid, end_tipo, distancia_corte)
			if lead == null:
				continue
			leads_usados[lead.get_instance_id()] = true
			_conectar_lead_a_segmento(sw, lead, p_seg, sid, end_tipo, jid, distancia_corte)


## Devuelve todos los node_id que apuntan a la MISMA instancia de aparato.
## Los aparatos compuestos (tijeras, escapes) registran varios node_id.
func _junctions_de_aparato(sw: BaseTurnout) -> Array[int]:
	var ids: Array[int] = []
	if sw == null:
		return ids
	for nid: int in aparatos_de_via.keys():
		if aparatos_de_via[nid] == sw:
			ids.append(nid)
	return ids


## Reconstruye SOLO el vecindario de aparatos afectado por los tramos editados.
##
## Antes, editar un tramo cualquiera llamaba a `_reconstruir_conexiones_adaptativas()`
## y recalculaba/re-anclaba los ~214 aparatos de TODA la red: el editor quedaba
## congelado varios segundos por cada arrastre. Esta versión toca únicamente:
##   1. los aparatos que referencian un tramo editado,
##   2. sus tramos vecinos (cuyos recortes pueden cambiar),
##   3. los aparatos conectados a esos vecinos (para no perder sus cortes).
func _reconstruir_conexiones_locales(seg_ids: Array[String]) -> void:
	if seg_ids.is_empty() or _conexiones_switch_segmento.has("_en_proceso"):
		return
	_conexiones_switch_segmento["_en_proceso"] = true
	_depurar_tramos_invalidos()

	var segs_afectados: Dictionary = {}
	for s: String in seg_ids:
		if paths.has(s):
			segs_afectados[s] = true

	# 1. Aparatos asentados en las uniones de los tramos editados. Se usa la
	#    topología (node_start/node_end) porque cruces, tijeras y crossovers NO
	#    setean via_comun/directa/desviada y quedarían sin reconstruir.
	var aparatos_afectados: Array[BaseTurnout] = []
	for s: String in seg_ids:
		if not segments_data.has(s):
			continue
		var seg_e: Dictionary = segments_data[s] as Dictionary
		for nid_v: Variant in [int(seg_e.get("node_start", 0)), int(seg_e.get("node_end", 0))]:
			var nid_j: int = int(nid_v)
			if nid_j == 0 or not aparatos_de_via.has(nid_j):
				continue
			var sw_e: BaseTurnout = aparatos_de_via[nid_j] as BaseTurnout
			if sw_e != null and not aparatos_afectados.has(sw_e):
				aparatos_afectados.append(sw_e)
	# Respaldo: aparatos que referencian el tramo por sus vías (desvíos simples).
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null or aparatos_afectados.has(sw):
			continue
		if segs_afectados.has(sw.via_comun_id) or segs_afectados.has(sw.via_directa_id) or segs_afectados.has(sw.via_desviada_id):
			aparatos_afectados.append(sw)

	# 2. Ampliar a las ramas de sus uniones.
	_agregar_ramas_de_aparatos(aparatos_afectados, segs_afectados)

	# 3. Vecinos: cualquier aparato asentado en las uniones de un tramo ya afectado
	#    (p. ej. un tramo corto entre DOS desvíos). Se repite hasta estabilizar la
	#    cadena, porque un recorte perdido en el otro extremo rompería el empalme.
	var iter: int = 0
	var hubo_nuevos: bool = true
	while hubo_nuevos and iter < 8:
		iter += 1
		hubo_nuevos = false
		var nuevos: Array[BaseTurnout] = []
		for s: String in segs_afectados.keys():
			if not segments_data.has(s):
				continue
			var seg_v: Dictionary = segments_data[s] as Dictionary
			for nid_v2: Variant in [int(seg_v.get("node_start", 0)), int(seg_v.get("node_end", 0))]:
				var nid2: int = int(nid_v2)
				if nid2 == 0 or not aparatos_de_via.has(nid2):
					continue
				var sw2: BaseTurnout = aparatos_de_via[nid2] as BaseTurnout
				if sw2 != null and not aparatos_afectados.has(sw2) and not nuevos.has(sw2):
					nuevos.append(sw2)
		if nuevos.is_empty():
			break
		hubo_nuevos = true
		for sw3: BaseTurnout in nuevos:
			aparatos_afectados.append(sw3)
		_agregar_ramas_de_aparatos(nuevos, segs_afectados)

	# 4. Conjunto final de tramos a recalcular.
	_agregar_ramas_de_aparatos(aparatos_afectados, segs_afectados)

	# 5. Limpiar registros SOLO de los tramos afectados.
	for s: String in segs_afectados.keys():
		_recortes_segmentos.erase(s)
		_recortes_extra.erase(s)
		_conflictos_adaptacion_switch.erase(s)
		_segmentos_reemplazados_por_switch.erase(s)
		_borrar_conexiones_de_segmento(s)

	# 6. Reconstruir solo los aparatos afectados.
	for sw: BaseTurnout in aparatos_afectados:
		_reconstruir_aparato(sw, _junctions_de_aparato(sw))

	_conexiones_switch_segmento.erase("_en_proceso")

	# 7. Remallar los tramos afectados (pocos: el costo es acotado).
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("actualizar_geometria_tramo"):
		for s: String in segs_afectados.keys():
			geo.call_deferred("actualizar_geometria_tramo", s)


## Agrega al conjunto todos los segmentos de las uniones de los aparatos dados.
func _agregar_ramas_de_aparatos(aparatos: Array[BaseTurnout], segs: Dictionary) -> void:
	for sw: BaseTurnout in aparatos:
		for jid: int in _junctions_de_aparato(sw):
			var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
			for c_raw: Variant in j_dict.get("segments", []):
				if c_raw is Dictionary:
					var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
					if not sid.is_empty():
						segs[sid] = true


## Borra los registros de conexión asociados a un segmento (clave "seg:end:junction").
func _borrar_conexiones_de_segmento(seg_id: String) -> void:
	var prefijo: String = seg_id + ":"
	var claves: Array = []
	for clave: Variant in _conexiones_switch_segmento.keys():
		if str(clave).begins_with(prefijo):
			claves.append(clave)
	for clave: Variant in claves:
		_conexiones_switch_segmento.erase(clave)


## Rango longitudinal [d_ini, d_fin] oculto por los aparatos (solo para la malla).
## La curva del tramo ya NO se recorta: se respeta la edición del usuario y el
## recorte vive exclusivamente en `_recortes_extra`, consumido por TrackGeometry.
func obtener_recorte_tramo(seg_id: String) -> Vector2:
	var reg: Dictionary = _recortes_extra.get(seg_id, {}) as Dictionary
	if reg.is_empty():
		return Vector2.ZERO
	return Vector2(float(reg.get("ini", 0.0)), float(reg.get("fin", 0.0)))


## Hace que cada tramo EMPIECE y TERMINE exactamente en el punto de unión (junction):
## el extremo de la vía coincide con el extremo del aparato y no se generan formas
## extrañas en el empalme. Sólo corrige diferencias chicas (≤ 6 m) y no marca el
## tramo como "modificado" (es una normalización estructural, no una edición tuya).
func _encajar_extremos_a_uniones() -> void:
	var encajados: int = 0
	for seg_id: String in paths.keys():
		if not segments_data.has(seg_id):
			continue
		var p: Path3D = paths[seg_id] as Path3D
		if p == null or p.curve == null or p.curve.point_count < 2:
			continue
		# Un tramo editado a mano es la fuente de verdad: no se le mueven los extremos.
		if p is EditableTrackSegment and (p as EditableTrackSegment).esta_modificada:
			continue
		var seg: Dictionary = segments_data[seg_id] as Dictionary
		var offset_ini: Vector3 = _delta_a_union(p, 0, int(seg.get("node_start", 0)))
		var offset_fin: Vector3 = _delta_a_union(p, p.curve.point_count - 1, int(seg.get("node_end", 0)))
		if offset_ini.length_squared() < 1e-4 and offset_fin.length_squared() < 1e-4:
			continue
		if p.has_method("set"):
			p.set("_bloqueo_reconstruccion", true)
		if offset_ini.length_squared() >= 1e-4:
			p.curve.set_point_position(0, p.curve.get_point_position(0) + offset_ini)
		if offset_fin.length_squared() >= 1e-4:
			var i_fin: int = p.curve.point_count - 1
			p.curve.set_point_position(i_fin, p.curve.get_point_position(i_fin) + offset_fin)
		if p.has_method("set"):
			p.set("_bloqueo_reconstruccion", false)
		encajados += 1
	if encajados > 0:
		print("TrackNetwork: %d tramos encajados exactamente a su punto de unión." % encajados)


## Desplazamiento (en coordenadas locales del Path3D) para que el punto `idx` caiga
## sobre el junction indicado. Devuelve ZERO si la unión es inválida o el ajuste es
## demasiado grande (para no distorsionar una edición deliberada).
func _delta_a_union(p: Path3D, idx: int, junction_id: int) -> Vector3:
	if junction_id == 0 or p == null or p.curve == null:
		return Vector3.ZERO
	var j_pos: Vector3 = _obtener_posicion_junction(junction_id)
	if j_pos.is_zero_approx():
		return Vector3.ZERO
	var objetivo_local: Vector3 = p.to_local(j_pos)
	var actual: Vector3 = p.curve.get_point_position(idx)
	var delta: Vector3 = objetivo_local - actual
	delta.y = 0.0
	if delta.length() > 6.0:
		return Vector3.ZERO
	return delta


## Devuelve el extremo ("start"/"end") con el que un segmento se conecta a la unión.
func _extremo_de_segmento_en_union(seg_id: String, junction_id: int) -> String:
	var j_dict: Dictionary = junctions.get(str(junction_id), {}) as Dictionary
	for c_raw: Variant in (j_dict.get("segments", []) as Array):
		if c_raw is Dictionary:
			var c: Dictionary = c_raw as Dictionary
			if str(c.get("segment_id", "")) == seg_id:
				return str(c.get("end", "start"))
	# Fallback: el extremo más próximo a la posición nominal de la unión.
	var p: Path3D = paths.get(seg_id) as Path3D
	if p == null or p.curve == null:
		return "start"
	var j_pos: Vector3 = _obtener_posicion_junction(junction_id)
	var p0: Vector3 = p.to_global(p.curve.get_point_position(0))
	var p1: Vector3 = p.to_global(p.curve.get_point_position(p.curve.point_count - 1))
	return "start" if p0.distance_to(j_pos) <= p1.distance_to(j_pos) else "end"


## Empareja las cuatro ramas de un cruce (Tipo C) o centro de tijera (Tipo E) en sus
## dos líneas que se cruzan y lo guarda como metadata del aparato. `get_switch_target`
## ya leía `linea_a_segs`/`linea_b_segs`, pero nadie las escribía: por eso el tren
## elegía la primera rama al azar al pasar un cruce.
func _asegurar_metadata_lineas(sw: BaseTurnout) -> void:
	if sw == null or (sw.has_meta("linea_a_segs") and sw.has_meta("linea_b_segs")):
		return
	var j_dict: Dictionary = junctions.get(str(sw.node_id), {}) as Dictionary
	var conexiones: Array = j_dict.get("segments", []) as Array
	var ids: Array[String] = []
	var dirs: Array[Vector2] = []
	for c_raw: Variant in conexiones:
		if not (c_raw is Dictionary):
			continue
		var c: Dictionary = c_raw as Dictionary
		var sid: String = str(c.get("segment_id", ""))
		if not paths.has(sid):
			continue
		var v: Vector2 = _obtener_vector_salida_segmento(sid, str(c.get("end", "start")))
		if v.length_squared() < 1e-6:
			continue
		ids.append(sid)
		dirs.append(v)
	if ids.size() != 4:
		return
	var mejor: float = 2.0
	var par_a: Array[int] = [0, 1]
	for i: int in 4:
		for k: int in range(i + 1, 4):
			var d: float = dirs[i].dot(dirs[k])
			if d < mejor:
				mejor = d
				par_a = [i, k]
	var par_b: Array[int] = []
	for idx: int in 4:
		if idx != par_a[0] and idx != par_a[1]:
			par_b.append(idx)
	if par_b.size() != 2:
		return
	sw.set_meta("linea_a_segs", [ids[par_a[0]], ids[par_a[1]]])
	sw.set_meta("linea_b_segs", [ids[par_b[0]], ids[par_b[1]]])


## Reubica RÍGIDAMENTE un aparato sobre la vía real (mueve y rota el aparato
## completo). NO toca su geometría interna: la región fija (rieles, espadines,
## corazón/aguja, contrarrieles) queda idéntica al template del tipo. El residuo
## entre la vía real y el aparato lo absorben los extremos flexibles, que son la
## única región adaptativa por diseño.
##
## La corrección es acotada: si el aparato fue movido a mano más allá del tope, se
## respeta (no se lo "imanta" de vuelta).
func _reubicar_aparato_sobre_via_real(sw: BaseTurnout) -> bool:
	if sw.via_comun_id.is_empty() or sw.via_directa_id.is_empty():
		return false
	var p_comun: Path3D = paths.get(sw.via_comun_id) as Path3D
	var p_dir: Path3D = paths.get(sw.via_directa_id) as Path3D
	if p_comun == null or p_dir == null or p_comun.curve == null or p_dir.curve == null:
		return false
	var largo: float = maxf(12.0, sw.get_largo_aparato() * 0.5)
	var end_comun: String = _extremo_de_segmento_en_union(sw.via_comun_id, sw.node_id)
	var end_dir: String = _extremo_de_segmento_en_union(sw.via_directa_id, sw.node_id)
	var pt_comun: Vector3 = _punto_extremo_real(p_comun, end_comun, largo)
	var pt_dir: Vector3 = _punto_extremo_real(p_dir, end_dir, largo)
	if pt_comun.is_zero_approx() and pt_dir.is_zero_approx():
		return false
	var fwd: Vector3 = pt_dir - pt_comun
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		return false
	fwd = fwd.normalized()
	var j_pos: Vector3 = _obtener_posicion_junction(sw.node_id)
	if j_pos.is_zero_approx():
		j_pos = pt_comun
	# El aparato nace EXACTAMENTE en el punto de unión (nodo OSM): así el punto de
	# empalme coincide con el junction y el aparato no queda corrido sobre la vía.
	var origen: Vector3 = j_pos
	origen.y = 0.0
	var lado: Vector3 = Vector3.UP.cross(fwd).normalized()
	if lado.length_squared() < 1e-6:
		return false
	var nuevo: Transform3D = Transform3D(Basis(lado, Vector3.UP, fwd), origen)
	var clave: int = sw.get_instance_id()
	# UNA SOLA VEZ por aparato: después el aparato es tuyo. Si se re-aplicara en cada
	# reconstrucción, "imantaría" el switch de vuelta y parecería que mover no cambia nada.
	if _refit_hecho.has(clave):
		return false
	var desplazamiento: float = sw.global_transform.origin.distance_to(origen)
	var giro: float = rad_to_deg(acos(clampf(sw.global_transform.basis.z.normalized().dot(fwd), -1.0, 1.0)))
	# Tope generoso: no se teletransporta un aparato que moviste a mano lejos.
	if desplazamiento > 12.0 or giro > 25.0:
		_refit_hecho[clave] = true
		return false
	_refit_hecho[clave] = true
	if desplazamiento < 0.02 and giro < 0.2:
		pass
	else:
		sw.global_transform = nuevo
		print("TrackNetwork: aparato %s alineado al junction %d (corrección %.2f m / %.1f°)." % [
			sw.name, sw.node_id, desplazamiento, giro
		])
	_ajustar_escala_aparato_a_via_real(sw)
	return true


## Escala el aparato PROPORCIONALMENTE (misma forma: ángulos y proporciones de
## espadines/corazón intactos) para que su largo entre en la distancia real entre
## uniones. Así no absorbe vía de más ni sobresale, y desaparecen los huecos y las
## formas raras en los extremos.
func _ajustar_escala_aparato_a_via_real(sw: BaseTurnout) -> void:
	var to: ProceduralTurnout = sw as ProceduralTurnout
	if to == null or to.curva_directa == null or to.curva_desviada == null:
		return
	if sw.via_comun_id.is_empty() or sw.via_directa_id.is_empty():
		return
	# El cuerpo del aparato se extiende desde la unión hacia la vía directa: su largo
	# no puede superar el largo real de ese tramo (hasta la unión siguiente).
	var l_dir: float = _largo_real_hasta_union(sw.via_directa_id, sw.node_id)
	var disponible: float = maxf(l_dir, 0.0)
	if disponible < 6.0:
		return
	var nominal: float = to.largo_turnout
	var objetivo: float = clampf(minf(nominal, disponible - 2.0), 14.0, nominal)
	var factor: float = objetivo / maxf(nominal, 0.01)
	if factor > 0.985 or factor < 0.35:
		return
	to._bloqueo_reconstruccion = true
	to.curva_directa = _escalar_curva(to.curva_directa, factor)
	to.curva_desviada = _escalar_curva(to.curva_desviada, factor)
	to.largo_turnout = objetivo
	to.largo_aguja = maxf(3.0, to.largo_aguja * factor)
	to.construir_geometria()
	to._bloqueo_reconstruccion = false
	print("TrackNetwork: aparato %s escalado a %.1f m (real disponible %.1f m, factor %.2f)." % [
		sw.name, objetivo, disponible, factor
	])


## Largo real, en metros, desde el extremo del tramo que toca la unión hasta la otra unión.
func _largo_real_hasta_union(seg_id: String, junction_id: int) -> float:
	var p: Path3D = paths.get(seg_id) as Path3D
	if p == null or p.curve == null:
		return 0.0
	var completa: Curve3D = _curva_completa_de_path(p)
	var largo: float = completa.get_baked_length() if completa != null else 0.0
	var seg: Dictionary = segments_data.get(seg_id, {}) as Dictionary
	var otro: int = int(seg.get("node_end", 0)) if int(seg.get("node_start", 0)) == junction_id else int(seg.get("node_start", 0))
	if otro == 0:
		return largo
	return largo


## Copia proporcional de una curva (escala uniforme: conserva ángulos y forma).
func _escalar_curva(c: Curve3D, factor: float) -> Curve3D:
	var n: Curve3D = Curve3D.new()
	n.bake_interval = c.bake_interval
	for i: int in c.point_count:
		n.add_point(
			c.get_point_position(i) * factor,
			c.get_point_in(i) * factor,
			c.get_point_out(i) * factor
		)
	return n


## Punto real a `largo_m` del extremo de una vía (o el extremo opuesto si es corta).
func _punto_extremo_real(p: Path3D, end_tipo: String, largo_m: float) -> Vector3:
	if p == null or p.curve == null:
		return Vector3.ZERO
	var c: Curve3D = _curva_completa_de_path(p)
	if c == null:
		return Vector3.ZERO
	var l_total: float = c.get_baked_length()
	if l_total < 0.5:
		return Vector3.ZERO
	var d: float = minf(largo_m, l_total * 0.9)
	var offset: float = d if end_tipo == "start" else (l_total - d)
	return p.to_global(c.sample_baked(clampf(offset, 0.0, l_total), true))


func _segmento_interno_de_aparato(seg_id: String, junction_set: Dictionary) -> bool:
	if not segments_data.has(seg_id):
		return false
	var seg: Dictionary = segments_data[seg_id] as Dictionary
	var n_start: int = int(seg.get("node_start", 0))
	var n_end: int = int(seg.get("node_end", 0))
	return junction_set.has(n_start) and junction_set.has(n_end)


func _seleccionar_lead_para_conexion(sw: BaseTurnout, p_seg: Path3D, end_tipo: String, leads_usados: Dictionary) -> FlexibleTrackLead:
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return null
	var salida: Vector3 = _obtener_vector_salida_global(p_seg, end_tipo)
	var origen: Vector3 = _obtener_posicion_extremo_segmento_global(p_seg, end_tipo)
	var mejor: FlexibleTrackLead = null
	var mejor_puntaje: float = INF
	for child: Node in g_ext.get_children():
		if not (child is FlexibleTrackLead):
			continue
		var lead: FlexibleTrackLead = child as FlexibleTrackLead
		if leads_usados.has(lead.get_instance_id()):
			continue
		var borne: Vector3 = lead.global_transform * lead.punto_inicio
		var direccion: Vector3 = (lead.global_transform.basis * lead.direccion_inicio).normalized()
		var alineacion: float = direccion.dot(salida)
		# La alineación manda: un puerto mal asignado produce un flexible que
		# apunta al lado contrario de la vía y queda vacío (hueco). La distancia
		# sólo desempata entre puertos que salen en la misma dirección.
		var penalizacion_alineacion: float = (1.0 - maxf(-1.0, alineacion)) * 250.0
		if alineacion <= 0.0:
			penalizacion_alineacion += 1000.0
		var puntaje: float = penalizacion_alineacion + borne.distance_to(origen)
		if puntaje < mejor_puntaje:
			mejor_puntaje = puntaje
			mejor = lead
	return mejor


func _obtener_posicion_extremo_segmento_global(path: Path3D, end_tipo: String) -> Vector3:
	if path == null or path.curve == null:
		return Vector3.ZERO
	var indice: int = 0 if end_tipo == "start" else path.curve.point_count - 1
	return path.global_transform * path.curve.get_point_position(indice)


func _obtener_vector_salida_global(path: Path3D, end_tipo: String) -> Vector3:
	var salida_2d: Vector2 = _obtener_vector_salida_segmento(path.name, end_tipo)
	return Vector3(salida_2d.x, 0.0, salida_2d.y).normalized()


func _conectar_lead_a_segmento(sw: BaseTurnout, lead: FlexibleTrackLead, path: Path3D, seg_id: String, end_tipo: String, junction_id: int, distancia_forzada: float = -1.0) -> void:
	var distancia: float = distancia_forzada if distancia_forzada >= 0.0 else _calcular_distancia_adaptativa(path, end_tipo, lead)
	distancia = _ajustar_distancia_para_transicion_valida(lead, path, end_tipo, distancia)
	var punto: Dictionary = _obtener_punto_recorte_segmento(path, end_tipo, distancia)
	var pos_world: Vector3 = punto["pos"] as Vector3
	var dir_world: Vector3 = punto["dir"] as Vector3
	# Si el puerto sigue por detrás del borne, la unión no es natural: NO se
	# deforma el flexible hasta el otro extremo del tramo. Se registra el conflicto
	# y se absorbe el tramo para no dibujar geometría superpuesta o retorcida.
	if _avance_local_de_punto(lead, pos_world) < LONGITUD_MINIMA_TRANSICION * 0.5:
		_conflictos_adaptacion_switch[seg_id] = {
			"motivo": "puerto_por_detras_del_borne",
			"avance": _avance_local_de_punto(lead, pos_world),
			"lead": String(lead.name),
			"switch": String(sw.name)
		}
	var pos_local: Vector3 = lead.global_transform.affine_inverse() * pos_world
	var dir_local: Vector3 = (lead.global_transform.basis.inverse() * dir_world).normalized()
	# NO se vuelve a registrar el corte ajustado: el corte de vía plena es el NATURAL
	# (el que ya registró la reconciliación). Registrar el ajustado agrandaba el corte
	# en cada pasada y absorbía tramos de más (415 visibles → 367).
	lead.conectar_a_via_externa(pos_local, dir_local)
	var registro: Dictionary = {
		"switch": sw.get_instance_id(),
		"switch_node_id": sw.node_id,
		"switch_name": String(sw.name),
		"lead": lead.get_instance_id(),
		"lead_name": String(lead.name),
		"segment_id": seg_id,
		"distancia": distancia,
		"end": end_tipo,
		"gap": -1.0,
		"kink_deg": -1.0,
		"p0_local": lead.punto_inicio,
		"d0_local": lead.direccion_inicio,
		"p1_local": pos_local,
		"dir_fin_local": dir_local,
		"lead_ext": lead.longitud_extension
	}
	# Métrica de calidad del empalme: separación real entre el extremo del
	# flexible y el punto de corte, y desalineación tangencial resultante.
	var curva: Curve3D = lead.curve
	if curva != null and curva.point_count >= 2:
		var i_fin: int = curva.point_count - 1
		var p_fin: Vector3 = curva.get_point_position(i_fin)
		registro["gap"] = p_fin.distance_to(pos_local)
		# La tangente final de la curva la define su manija de entrada; es exacta
		# incluso en tramos flexibles muy cortos (donde la cuerda engañaría).
		var manija: Vector3 = -curva.get_point_in(i_fin)
		if manija.length_squared() > 1e-10:
			registro["kink_deg"] = rad_to_deg(acos(clampf(absf(manija.normalized().dot(dir_local)), 0.0, 1.0)))
	_conexiones_switch_segmento["%s:%s:%d" % [seg_id, end_tipo, junction_id]] = registro

## Avance (m) de un punto dado medido sobre el eje de salida de un tramo flexible.
## Se mide en coordenadas locales del flexible (no del aparato).
func _avance_local_de_punto(lead: FlexibleTrackLead, pos_world: Vector3) -> float:
	if lead == null:
		return 0.0
	var d0: Vector3 = lead.direccion_inicio.normalized()
	if d0.length_squared() < 1e-6:
		return 0.0
	var pos_local: Vector3 = lead.global_transform.affine_inverse() * pos_world
	return (pos_local - lead.punto_inicio).dot(d0)


## Ajusta el corte para que la transición exista, pero SIN deformar la geometría:
## el corte nunca supera el largo nominal del propio flexible más
## `MARGEN_MAX_EXTENSION_LEAD`. Así un puerto desalineado puede cerrar el hueco con
## un tramo corto y natural (a escala real), y nunca con una curva gigantesca de
## radio ridículo (antes se estiraba hasta el 100 % del tramo, 157 m en un caso).
func _ajustar_distancia_para_transicion_valida(lead: FlexibleTrackLead, path: Path3D, end_tipo: String, distancia: float) -> float:
	if lead == null or path == null or path.curve == null:
		return distancia
	var p0: Vector3 = lead.punto_inicio
	var d0: Vector3 = lead.direccion_inicio.normalized()
	if d0.length_squared() < 1e-6:
		return distancia
	var largo: float = path.curve.get_baked_length()
	var maximo: float = maxf(0.0, largo - MARGEN_FINAL_SEGMENTO_SWITCH)
	var tope: float = minf(maximo, maxf(MARGEN_FINAL_SEGMENTO_SWITCH, lead.longitud_extension + MARGEN_MAX_EXTENSION_LEAD))
	var candidata: float = clampf(distancia, 0.0, tope)
	var inv_lead: Transform3D = lead.global_transform.affine_inverse()
	var pasos: int = 0
	while pasos < 40:
		var punto: Dictionary = _obtener_punto_recorte_segmento(path, end_tipo, candidata)
		var pos_local: Vector3 = inv_lead * (punto["pos"] as Vector3)
		var avance: float = (pos_local - p0).dot(d0)
		if avance >= LONGITUD_MINIMA_TRANSICION:
			return candidata
		if candidata >= tope:
			return tope
		candidata = minf(tope, candidata + 0.5)
		pasos += 1
	return candidata


## Distancia de recorte, en metros, que hay que ceder de una vía real para dejar
## sitio al aparato y su transición.
##
## Regla natural: se corta la vía real exactamente donde termina el riel del
## aparato (proyección del borne sobre la curva real). Con el aparato calibrado
## contra la vía, ese punto coincide con el borne ⇒ corte ≈ `MARGEN_MINIMO_UNION_M`
## y no hace falta estirar ningún flexible. Los cortes fijos anteriores (120 m o
## el largo nominal del flexible) se comían tramos enteros y deformaban todo.
func _calcular_distancia_adaptativa(path: Path3D, _end_tipo: String, lead: FlexibleTrackLead) -> float:
	if path == null or path.curve == null:
		return MARGEN_FINAL_SEGMENTO_SWITCH
	var completa: Curve3D = _curva_completa_de_path(path)
	if completa == null:
		return MARGEN_FINAL_SEGMENTO_SWITCH
	var longitud: float = completa.get_baked_length()
	var maximo: float = maxf(0.0, longitud - MARGEN_FINAL_SEGMENTO_SWITCH)
	if lead == null:
		return minf(MARGEN_MINIMO_UNION_M, maximo)
	var p_borne_mundo: Vector3 = lead.global_transform * lead.punto_inicio
	var local: Vector3 = path.to_local(p_borne_mundo)
	var offset: float = completa.get_closest_offset(local)
	var distancia: float = offset if _end_tipo == "start" else (longitud - offset)
	return clampf(distancia, MARGEN_MINIMO_UNION_M, maximo)




## Registra un recorte longitudinal en metros para un extremo de segmento que conecta a un switch.
func _registrar_recorte_segmento(seg_id: String, end_tipo: String, largo_recorte_m: float) -> void:
	if not paths.has(seg_id):
		return
	var p: Path3D = paths[seg_id] as Path3D
	if p == null or p.curve == null:
		return
	# OJO: los intervalos excluidos se expresan SIEMPRE en coordenadas de la curva
	# COMPLETA (no de la curva ya recortada). Si se mezclan, cada pasada vuelve a
	# recortar sobre lo recortado y el recorte nunca converge.
	var completa: Curve3D = _curva_completa_de_path(p)
	if completa == null:
		return
	var l_total: float = completa.get_baked_length()
	# La distancia ya fue elegida por la conexión. No volver a elevarla aquí:
	# hacerlo convertiría todos los cortes pequeños en huecos de 120 m.
	largo_recorte_m = clampf(largo_recorte_m, 0.0, maxf(0.0, l_total - MARGEN_FINAL_SEGMENTO_SWITCH))
	var actual: Vector2 = _recortes_segmentos.get(seg_id, Vector2(0.0, l_total)) as Vector2
	# Registro ÚNICO por tramo y por extremo: {"ini", "fin"} en coordenadas de la
	# curva completa. Se acumula con max/min (nunca una lista), así es idempotente:
	# antes la lista juntaba casi-duplicados y el rango oscilaba en cada pasada.
	var reg: Dictionary = _recortes_extra.get(seg_id, {"ini": 0.0, "fin": l_total}) as Dictionary
	if end_tipo == "start":
		reg["ini"] = maxf(float(reg.get("ini", 0.0)), minf(largo_recorte_m, l_total))
	else:
		reg["fin"] = minf(float(reg.get("fin", l_total)), maxf(0.0, l_total - largo_recorte_m))
	_recortes_extra[seg_id] = reg
	if actual == Vector2.ZERO:
		return
	if end_tipo == "start":
		actual.x = maxf(actual.x, minf(largo_recorte_m, l_total))
	else:
		actual.y = minf(actual.y, maxf(0.0, l_total - largo_recorte_m))
	if actual.y - actual.x < 1.5:
		if actual != Vector2.ZERO:
			_conflictos_adaptacion_switch[seg_id] = {
				"longitud": l_total,
				"inicio": actual.x,
				"fin": actual.y,
				"distancia_minima": DISTANCIA_MINIMA_ADAPTACION_SWITCH
			}
			# Se avisa UNA vez por tramo: antes se emitía un warning con backtrace en
			# cada reconstrucción (cientos de líneas por edición y costo real en el Output).
			if not _absorbidos_avisados.has(seg_id):
				_absorbidos_avisados[seg_id] = true
				#print("TrackNetwork: el tramo '%s' queda absorbido por los aparatos de vía (sin separación libre entre extremos)." % seg_id)
		actual = Vector2.ZERO
	_recortes_segmentos[seg_id] = actual


## Rangos de vía plena que SÍ deben dibujarse: [0, largo] menos los intervalos
## excluidos por los aparatos. Permite un tramo con dos aparatos (uno en cada punta)
## conservando el trozo del medio.
func obtener_rangos_utiles_tramo(seg_id: String) -> Array[Vector2]:
	var resultado: Array[Vector2] = []
	if es_segmento_reemplazado_por_switch(seg_id):
		return resultado
	var p: Path3D = paths.get(seg_id) as Path3D
	if p == null or p.curve == null:
		return resultado
	var l_total: float = p.curve.get_baked_length()
	if p.get("anular_recorte_switch") == true:
		resultado.append(Vector2(0.0, l_total))
		return resultado
	# Registro único por tramo: [ini, fin] en coordenadas de la curva completa.
	if _recortes_extra.has(seg_id):
		var reg: Dictionary = _recortes_extra[seg_id] as Dictionary
		var ini: float = clampf(float(reg.get("ini", 0.0)), 0.0, l_total)
		var fin: float = clampf(float(reg.get("fin", l_total)), 0.0, l_total)
		if fin - ini >= 0.2:
			resultado.append(Vector2(ini, fin))
		return resultado
	var r_legacy: Vector2 = _recortes_segmentos.get(seg_id, Vector2(0.0, l_total)) as Vector2
	if r_legacy == Vector2.ZERO:
		return resultado
	resultado.append(Vector2(clampf(r_legacy.x, 0.0, l_total), clampf(r_legacy.y, 0.0, l_total)))
	return resultado


## Registra el recorte de la vía real hasta donde llega un extremo fijado a mano.
func _registrar_recorte_en_extremo_manual(lead: FlexibleTrackLead, path: Path3D, seg_id: String, end_tipo: String) -> void:
	if lead == null or path == null or path.curve == null:
		return
	var p_ext_mundo: Vector3 = lead.global_transform * lead.obtener_posicion_extremo_exterior()
	var longitud: float = path.curve.get_baked_length()
	var offset: float = path.curve.get_closest_offset(path.to_local(p_ext_mundo))
	var d: float = offset if end_tipo == "start" else (longitud - offset)
	_registrar_recorte_segmento(seg_id, end_tipo, clampf(d, 0.0, maxf(0.0, longitud - MARGEN_FINAL_SEGMENTO_SWITCH)))


## Indica si un Path3D no debe tener vía plena porque un aparato lo reemplaza.
## La comprobación usa también la topología viva para no depender del orden de @tool.
func es_segmento_reemplazado_por_switch(seg_id: String) -> bool:
	if _segmentos_reemplazados_por_switch.has(seg_id):
		return true
	return false


## Devuelve la curva local o global activa de un aparato de vía para ruteo fino de trenes.
## Trayectoria INTERNA del aparato para un movimiento concreto (puerto a puerto), en
## coordenadas de mundo. La usa el tren para recorrer los espadines/corazón en vez de
## saltar sobre la zona que la vía real ya no dibuja (curva recortada).
func get_trayectoria_aparato(junction_id: int, seg_origen: String, seg_destino: String) -> Curve3D:
	var ap: BaseTurnout = aparatos_de_via.get(junction_id) as BaseTurnout
	if ap == null:
		return null
	# 1 = ruta por vía directa/principal, 2 = ruta desviada/alterna.
	var via_origen: int = 1
	if not ap.via_desviada_id.is_empty() and (seg_origen == ap.via_desviada_id or seg_destino == ap.via_desviada_id):
		via_origen = 2
	return ap.obtener_trayectoria_completa_global(via_origen)


## Devuelve la curva local o global activa de un aparato de vía para ruteo fino de trenes.
func obtener_curva_activa_switch(nodo_id: int, via_origen: int = 1) -> Curve3D:
	if aparatos_de_via.has(nodo_id):
		var ap: BaseTurnout = aparatos_de_via[nodo_id] as BaseTurnout
		if ap != null:
			return ap.obtener_curva_activa(via_origen)
	return null


## Detecta y asocia parejas de switches de escape que comparten la misma vía diagonal de enlace.
func _detectar_enclavamientos_crossover() -> void:
	_enclavamientos_crossover.clear()
	for nid: int in aparatos_de_via.keys():
		var ap: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if ap == null or ap.via_desviada_id.is_empty():
			continue
		var desv_id: String = ap.via_desviada_id
		if not segments_data.has(desv_id):
			continue
		var seg: Dictionary = segments_data[desv_id] as Dictionary
		var n_start: int = int(seg.get("node_start", 0))
		var n_end: int = int(seg.get("node_end", 0))
		var partner_id: int = n_end if n_start == nid else n_start
		if partner_id != 0 and partner_id != nid and aparatos_de_via.has(partner_id):
			var ap_partner: BaseTurnout = aparatos_de_via[partner_id] as BaseTurnout
			if ap_partner != null and ap_partner.via_desviada_id == desv_id:
				_enclavamientos_crossover[nid] = partner_id
				_enclavamientos_crossover[partner_id] = nid


## Conmuta el estado de un cambio de vía (Directa <-> Desviada) con enclavamiento de crossover coordinado.
func conmutar_switch(nodo_id: int) -> bool:
	if _bloqueo_recursivo:
		return false
	_bloqueo_recursivo = true
	var exito: bool = _conmutar_switch_local(nodo_id)
	if exito and _enclavamientos_crossover.has(nodo_id):
		var partner_id: int = _enclavamientos_crossover[nodo_id]
		var esta_desv: bool = is_switch_desviado(nodo_id)
		_set_switch_desviado_local(partner_id, esta_desv)
	_bloqueo_recursivo = false
	return exito


func _conmutar_switch_local(nodo_id: int) -> bool:
	if aparatos_de_via.has(nodo_id):
		var ap: BaseTurnout = aparatos_de_via[nodo_id] as BaseTurnout
		if ap != null:
			ap.conmutar()
			var activo: String = ap.get_segmento_activo()
			var esta_desv: bool = ap.is_desviado()
			switch_states[nodo_id] = activo
			switch_conmutado.emit(nodo_id, activo)
			switch_movido.emit(nodo_id, esta_desv, activo)
			return true
	elif junctions.has(str(nodo_id)):
		var j: Dictionary = junctions[str(nodo_id)] as Dictionary
		var segs: Array = j.get("segments", []) as Array
		if segs.size() >= 2:
			var tr_dir: String = str((segs[0] as Dictionary).get("segment_id", ""))
			var tr_desv: String = str((segs[1] as Dictionary).get("segment_id", ""))
			var actual: String = str(switch_states.get(nodo_id, tr_dir))
			var nuevo: String = tr_desv if actual == tr_dir else tr_dir
			switch_states[nodo_id] = nuevo
			switch_conmutado.emit(nodo_id, nuevo)
			switch_movido.emit(nodo_id, nuevo == tr_desv, nuevo)
			return true
	return false


## Establece explícitamente el estado de un desvío (false = Directa, true = Desviada).
func set_switch_desviado(nodo_id: int, desviada: bool) -> void:
	if _bloqueo_recursivo:
		return
	_bloqueo_recursivo = true
	_set_switch_desviado_local(nodo_id, desviada)
	if _enclavamientos_crossover.has(nodo_id):
		var partner_id: int = _enclavamientos_crossover[nodo_id]
		_set_switch_desviado_local(partner_id, desviada)
	_bloqueo_recursivo = false


func _set_switch_desviado_local(nodo_id: int, desviada: bool) -> void:
	if aparatos_de_via.has(nodo_id):
		var ap: BaseTurnout = aparatos_de_via[nodo_id] as BaseTurnout
		if ap != null:
			ap.conmutar_a(1 if desviada else 0)
			var activo: String = ap.get_segmento_activo()
			switch_states[nodo_id] = activo
			switch_conmutado.emit(nodo_id, activo)
			switch_movido.emit(nodo_id, desviada, activo)
	elif junctions.has(str(nodo_id)):
		var j: Dictionary = junctions[str(nodo_id)] as Dictionary
		var segs: Array = j.get("segments", []) as Array
		if segs.size() >= 2:
			var target_id: String = str((segs[1 if desviada else 0] as Dictionary).get("segment_id", ""))
			switch_states[nodo_id] = target_id
			switch_conmutado.emit(nodo_id, target_id)
			switch_movido.emit(nodo_id, desviada, target_id)


## Devuelve si un switch está desviado o en vía directa.
func is_switch_desviado(nodo_id: int) -> bool:
	if aparatos_de_via.has(nodo_id):
		var ap: BaseTurnout = aparatos_de_via[nodo_id] as BaseTurnout
		if ap != null:
			return ap.is_desviado()
	if junctions.has(str(nodo_id)):
		var j: Dictionary = junctions[str(nodo_id)] as Dictionary
		var segs: Array = j.get("segments", []) as Array
		if segs.size() >= 2:
			var tr_desv: String = str((segs[1] as Dictionary).get("segment_id", ""))
			return str(switch_states.get(nodo_id, "")) == tr_desv
	return false


## Devuelve la lista de switches con su posición 3D, estado y conexiones.
func get_switches_disponibles() -> Array[Dictionary]:
	var lista: Array[Dictionary] = []
	for nid: int in _switches_ordenados:
		var ap: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if ap == null:
			continue
		var esta_desv: bool = ap.is_desviado()
		var tipo_aparato: String = ap.get_tipo_aparato()
		var ang_desv_rad: float = float(ap.get("angulo_desvio_rad")) if ap.get("angulo_desvio_rad") != null else 0.0
		lista.append({
			"node_id": nid,
			"position": ap.position,
			"desviada": esta_desv,
			"tipo": tipo_aparato,
			"via_comun": ap.via_comun_id,
			"via_directa": ap.via_directa_id,
			"via_desviada": ap.via_desviada_id,
			"es_desvio_izquierda": bool(ap.get("es_desvio_izquierda")),
			"angulo_desvio_deg": rad_to_deg(ang_desv_rad),
			"segmento_activo": ap.get_segmento_activo()
		})
	return lista


## Devuelve el nodo del switch dado (BaseTurnout, o null si no existe).




func _seleccionar_switch_por_indice(idx: int) -> void:
	if _bloqueo_recursivo:
		return
	if _switches_ordenados.is_empty():
		info_switch_actual = "No hay cambios de vía instanciados en la red."
		return

	var idx_clamped: int = clampi(idx, 0, _switches_ordenados.size() - 1)
	var target_id: int = _switches_ordenados[idx_clamped]

	_bloqueo_recursivo = true
	switch_indice_inspeccion = idx_clamped
	switch_id_inspeccion = target_id
	aguja_desviada = is_switch_desviado(target_id)
	_actualizar_texto_info_switch()
	_bloqueo_recursivo = false


func _ir_siguiente_switch() -> void:
	if _switches_ordenados.is_empty():
		return
	var sig: int = (switch_indice_inspeccion + 1) % _switches_ordenados.size()
	_seleccionar_switch_por_indice(sig)


func _ir_anterior_switch() -> void:
	if _switches_ordenados.is_empty():
		return
	var ant: int = (switch_indice_inspeccion - 1 + _switches_ordenados.size()) % _switches_ordenados.size()
	_seleccionar_switch_por_indice(ant)


func _seleccionar_switch_cercano() -> void:
	if _switches_ordenados.is_empty():
		return
	var mejor_idx: int = 0
	var menor_dist: float = INF
	for i: int in _switches_ordenados.size():
		var ap: BaseTurnout = aparatos_de_via[_switches_ordenados[i]] as BaseTurnout
		if ap == null:
			continue
		var d2: float = ap.position.length_squared()
		if d2 < menor_dist:
			menor_dist = d2
			mejor_idx = i
	_seleccionar_switch_por_indice(mejor_idx)


func _actualizar_inspeccion_switch() -> void:
	if _bloqueo_recursivo:
		return
	if switch_id_inspeccion == 0 or not aparatos_de_via.has(switch_id_inspeccion):
		info_switch_actual = "Ningún cambio de vía seleccionado."
		return

	_bloqueo_recursivo = true
	var idx_encontrado: int = _switches_ordenados.find(switch_id_inspeccion)
	if idx_encontrado != -1:
		switch_indice_inspeccion = idx_encontrado
	aguja_desviada = is_switch_desviado(switch_id_inspeccion)
	_actualizar_texto_info_switch()
	_bloqueo_recursivo = false


func _actualizar_texto_info_switch() -> void:
	if switch_id_inspeccion == 0 or not aparatos_de_via.has(switch_id_inspeccion):
		info_switch_actual = "Ningún cambio de vía seleccionado."
		return

	var ap: BaseTurnout = aparatos_de_via[switch_id_inspeccion] as BaseTurnout
	if ap == null:
		info_switch_actual = "Error: switch nulo."
		return
	var pos_sw: Vector3 = ap.position
	var v_comun: String = ap.via_comun_id
	var v_dir: String = ap.via_directa_id
	var v_desv: String = ap.via_desviada_id
	var seg_act: String = ap.get_segmento_activo()
	var tipo_str: String = ap.get_tipo_aparato()
	var desc_str: String = ap.get_estado_descripcion()

	var sector_tramo: Array[String] = _determinar_sector_tramo_switch(pos_sw, [v_comun, v_dir, v_desv])

	info_switch_actual = (
		"=== CAMBIO DE VÍA [%d / %d] (%s) ===\n" % [switch_indice_inspeccion + 1, _switches_ordenados.size(), tipo_str] +
		"Sector: %s | Tramo: %s\n" % [sector_tramo[0], sector_tramo[1]] +
		"Nodo OSM ID: %d\n" % switch_id_inspeccion +
		"Posición 3D: X=%.1f m | Y=%.1f m | Z=%.1f m\n" % [pos_sw.x, pos_sw.y, pos_sw.z] +
		"Vía Común (Entrada / Stem): %s\n" % (v_comun if not v_comun.is_empty() else "N/A") +
		"Vía Directa (Recta): %s\n" % (v_dir if not v_dir.is_empty() else "N/A") +
		"Vía Desviada (Curva): %s\n" % (v_desv if not v_desv.is_empty() else "N/A") +
		"Estado Aguja: %s\n" % desc_str +
		"Segmento de Salida Conectado: %s" % seg_act
	)


func _excluir_tramo_manual() -> void:
	var t: String = tramo_a_excluir.strip_edges()
	if t.is_empty():
		return
	if not tramos_excluidos.has(t):
		var arr: PackedStringArray = tramos_excluidos
		arr.append(t)
		tramo_a_excluir = ""
		tramos_excluidos = arr


func _excluir_desviada_actual() -> void:
	if switch_id_inspeccion != 0 and aparatos_de_via.has(switch_id_inspeccion):
		var ap: BaseTurnout = aparatos_de_via[switch_id_inspeccion] as BaseTurnout
		if ap != null:
			var desv_id: String = ap.via_desviada_id
			if not desv_id.is_empty() and not tramos_excluidos.has(desv_id):
				var arr: PackedStringArray = tramos_excluidos
				arr.append(desv_id)
				tramos_excluidos = arr


## Devuelve las opciones disponibles al llegar al extremo ("start" o "end") del segmento actual.
## Excluye el propio segmento. Cada opción indica el próximo segmento_id y si hay
## que recorrerlo "forward" o "reversed" según cómo esté orientado.
func get_opciones_siguientes(segment_id: String, extremo_actual: String) -> Array[Dictionary]:
	if not segments_data.has(segment_id):
		return []

	var seg: Dictionary = segments_data[segment_id] as Dictionary
	var node_id: int = int(seg.get("node_end", 0)) if extremo_actual == "end" else int(seg.get("node_start", 0))

	var junction_raw: Variant = junctions.get(str(node_id))
	if junction_raw == null or not (junction_raw is Dictionary):
		return []

	var junction: Dictionary = junction_raw as Dictionary
	var opciones: Array[Dictionary] = []
	var conexiones: Array = junction.get("segments", []) as Array

	for con_raw: Variant in conexiones:
		if not (con_raw is Dictionary):
			continue
		var con: Dictionary = con_raw as Dictionary
		var otro_id: String = str(con.get("segment_id", ""))
		if otro_id == segment_id:
			continue
		# Un tramo eliminado/excluido no existe en la red: no debe ofrecerse como
		# continuación (antes el tren elegía un segmento borrado y daba la vuelta).
		if not paths.has(otro_id):
			continue

		var otro_extremo: String = str(con.get("end", "start"))
		var direccion: String = "forward" if otro_extremo == "start" else "reversed"
		opciones.append({
			"segment_id": otro_id,
			"direccion": direccion,
			"node_id": node_id,
			"end": otro_extremo,
			"vector": _obtener_vector_salida_segmento(otro_id, otro_extremo)
		})

	return opciones


## Indica si el extremo de un segmento desemboca en un cambio de vía (switch).
func es_switch(segment_id: String, extremo_actual: String) -> bool:
	if not segments_data.has(segment_id):
		return false

	var seg: Dictionary = segments_data[segment_id] as Dictionary
	var node_id: int = int(seg.get("node_end", 0)) if extremo_actual == "end" else int(seg.get("node_start", 0))

	var junction_raw: Variant = junctions.get(str(node_id))
	if junction_raw == null or not (junction_raw is Dictionary):
		return false

	var junction: Dictionary = junction_raw as Dictionary
	var es_tag_switch: bool = bool(junction.get("is_switch", false))
	var conexiones: Array = junction.get("segments", []) as Array

	return es_tag_switch or conexiones.size() > 2


## Establece la posición/rama activa de una aguja (switch).
func set_switch_target(node_id: int, target_segment_id: String) -> void:
	switch_states[node_id] = target_segment_id
	if aparatos_de_via.has(node_id):
		var ap: BaseTurnout = aparatos_de_via[node_id] as BaseTurnout
		if ap != null:
			ap.conmutar_a(1 if target_segment_id == ap.via_desviada_id else 0)
	switch_conmutado.emit(node_id, target_segment_id)


## Obtiene la opción seleccionada para un switch. Si no está definida, devuelve la primera disponible.
func get_switch_target(node_id: int, opciones: Array[Dictionary], segmento_origen: String = "") -> Dictionary:
	if aparatos_de_via.has(node_id):
		var ap: BaseTurnout = aparatos_de_via[node_id] as BaseTurnout
		if ap != null:
			# Si es un Cruce Diamante (Tipo C o centro de Tijera Tipo E)
			if ap.has_meta("linea_a_segs") and ap.has_meta("linea_b_segs"):
				var l_a: Array = ap.get_meta("linea_a_segs") as Array
				var l_b: Array = ap.get_meta("linea_b_segs") as Array
				var seg_target: String = ""
				if segmento_origen == str(l_a[0]):
					seg_target = str(l_a[1])
				elif segmento_origen == str(l_a[1]):
					seg_target = str(l_a[0])
				elif segmento_origen == str(l_b[0]):
					seg_target = str(l_b[1])
				elif segmento_origen == str(l_b[1]):
					seg_target = str(l_b[0])

				if not seg_target.is_empty():
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == seg_target:
							return op

			if not segmento_origen.is_empty():
				# Si el tren viene desde una de las ramas (directa o desviada),
				# la única continuación física y segura es la vía común (stem)
				if segmento_origen == ap.via_directa_id or segmento_origen == ap.via_desviada_id:
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == ap.via_comun_id:
							return op
				elif segmento_origen == ap.via_comun_id:
					# Si viene desde la vía común (stem), sigue la posición activa del aparato
					var target: String = ap.get_segmento_activo()
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == target:
							return op

			# Fallback con estado activo del aparato
			var target_id: String = ap.get_segmento_activo()
			for op: Dictionary in opciones:
				if str(op.get("segment_id", "")) == target_id:
					return op
			# Si target_id no está en opciones (porque es el segmento del que venimos),
			# dirigir a la vía común
			for op: Dictionary in opciones:
				if str(op.get("segment_id", "")) == ap.via_comun_id:
					return op

	if switch_states.has(node_id):
		var target_id: String = str(switch_states[node_id])
		for op: Dictionary in opciones:
			if str(op.get("segment_id", "")) == target_id:
				return op

	# Continuidad geométrica (uniones sin `via_comun/directa/desviada` ni metadata:
	# cruces, tijeras en cadena, escapes). Antes caía a `opciones[0]` y elegía una
	# rama al azar; ahora continúa lo más recto posible respecto de la llegada.
	var dir_llegada: Vector2 = _direccion_llegada_union(segmento_origen, node_id)
	if dir_llegada != Vector2.ZERO:
		var mejor_dot: float = -2.0
		var mejor_op: Dictionary = {}
		for op: Dictionary in opciones:
			var v: Vector2 = op.get("vector", Vector2.ZERO) as Vector2
			if v.length_squared() < 1e-6:
				continue
			var d: float = dir_llegada.dot(v)
			if d > mejor_dot:
				mejor_dot = d
				mejor_op = op
		if not mejor_op.is_empty() and mejor_dot >= -0.5:
			return mejor_op

	if opciones.size() > 0:
		return opciones[0]
	return {}


## Dirección (2D) con la que un tren LLEGA a la unión viniendo por `seg_origen`.
func _direccion_llegada_union(seg_origen: String, node_id: int) -> Vector2:
	if seg_origen.is_empty():
		return Vector2.ZERO
	var j_dict: Dictionary = junctions.get(str(node_id), {}) as Dictionary
	for c_raw: Variant in j_dict.get("segments", []):
		if not (c_raw is Dictionary):
			continue
		var c: Dictionary = c_raw as Dictionary
		if str(c.get("segment_id", "")) == seg_origen:
			var v: Vector2 = _obtener_vector_salida_segmento(seg_origen, str(c.get("end", "start")))
			return -v
	return Vector2.ZERO


## Obtiene el nodo Path3D asociado a un segmento.
func get_segment_path(segment_id: String) -> Path3D:
	if paths.has(segment_id):
		return paths[segment_id] as Path3D
	return null


## Obtiene los datos de una unión por su ID de nodo OSM.


## Encuentra el ID del segmento más cercano a una posición 3D global de MUNDO.
func get_closest_segment(posicion_global: Vector3) -> String:
	var mejor_id: String = ""
	var menor_distancia_cuad: float = INF

	for seg_id: String in paths.keys():
		var p: Path3D = paths[seg_id] as Path3D
		if p == null or p.curve == null or p.curve.point_count < 2:
			continue
		# Cada Path3D puede tener su propio transform: proyectar en su espacio local.
		var pos_local: Vector3 = p.to_local(posicion_global)
		var punto_cercano: Vector3 = p.curve.get_closest_point(pos_local)
		var d2: float = pos_local.distance_squared_to(punto_cercano)
		if d2 < menor_distancia_cuad:
			menor_distancia_cuad = d2
			mejor_id = seg_id

	return mejor_id


## Construye un Curve3D calculando tangentes Catmull-Rom para una curvatura suave y continua,
## respetando tangentes de empalme continuas (C1) en los extremos cuando se especifican.
func _construir_curva_suave(puntos: Array[Vector3], tangente_inicio: Vector3 = Vector3.ZERO, tangente_fin: Vector3 = Vector3.ZERO) -> Curve3D:
	var c: Curve3D = Curve3D.new()
	var n: int = puntos.size()
	if n < 2:
		return c

	for i: int in n:
		var pos: Vector3 = puntos[i]
		var anterior: Vector3 = puntos[i - 1] if i > 0 else puntos[0]
		var siguiente: Vector3 = puntos[i + 1] if i < n - 1 else puntos[n - 1]

		var tangente: Vector3 = Vector3.FORWARD
		if i == 0 and tangente_inicio != Vector3.ZERO:
			tangente = tangente_inicio.normalized()
		elif i == n - 1 and tangente_fin != Vector3.ZERO:
			tangente = tangente_fin.normalized()
		else:
			tangente = (siguiente - anterior)
			if tangente.length_squared() < 1e-6:
				tangente = Vector3.FORWARD
			tangente = tangente.normalized()

		var d_atras: float = pos.distance_to(anterior)
		var d_adelante: float = pos.distance_to(siguiente)

		var in_control: Vector3 = - tangente * d_atras * factor_suavizado if i > 0 else Vector3.ZERO
		var out_control: Vector3 = tangente * d_adelante * factor_suavizado if i < n - 1 else Vector3.ZERO

		c.add_point(pos, in_control, out_control)

	return c


func _obtener_otro_extremo_segmento(seg_id: String, j_id: int) -> int:
	if segments_data.has(seg_id):
		var seg: Dictionary = segments_data[seg_id] as Dictionary
		var n_s: int = int(seg.get("node_start", 0))
		var n_e: int = int(seg.get("node_end", 0))
		return n_e if n_s == j_id else n_s
	return 0


func _obtener_posicion_junction(j_id: int) -> Vector3:
	var j_dict: Dictionary = junctions.get(str(j_id), {}) as Dictionary
	var p_dict: Dictionary = j_dict.get("position", {}) as Dictionary
	if p_dict.has("x"):
		return Vector3(float(p_dict.get("x", 0.0)), float(p_dict.get("y", 0.0)), float(p_dict.get("z", 0.0)))
	return Vector3.ZERO


# ==============================================================================
# SISTEMA DE EDICIÓN VISUAL Y PERSISTENCIA DE VÍAS
# ==============================================================================

## Hace visibles y seleccionables en el árbol de escena y viewport todos los tramos de vía.
func habilitar_edicion_en_arbol() -> void:
	mostrar_en_arbol_editor = true
	var root_owner: Node = _obtener_root_owner()
	if root_owner == null:
		return
	if _contenedor_vias != null:
		_contenedor_vias.owner = root_owner
		_asignar_owner_recursivo(_contenedor_vias, root_owner)
	if _contenedor_switches != null:
		_contenedor_switches.owner = root_owner
		_asignar_owner_recursivo(_contenedor_switches, root_owner)
	print("TrackNetwork: Edición de vías habilitada en el árbol de escena. Ahora puedes seleccionar y editar cualquier tramo en el viewport 3D.")


func _asignar_owner_recursivo(nodo: Node, root_owner: Node) -> void:
	for c: Node in nodo.get_children():
		# Los aparatos de vía son escenas instanciadas; no asignar owner a sus componentes internos
		if c is BaseTurnout:
			c.owner = root_owner
			continue
		if c.name in ["GeometriaFija", "MecanismoAgujas", "ExtremosFlexibles"] or c is MeshInstance3D:
			continue
		c.owner = root_owner
		if c.get_child_count() > 0:
			_asignar_owner_recursivo(c, root_owner)


## Devuelve la ruta al archivo JSON de persistencia de ediciones.
func obtener_ruta_ediciones_json() -> String:
	if not ruta_archivo_ediciones.is_empty():
		return ruta_archivo_ediciones
	var ruta_base: String = _obtener_ruta_red_json()
	if ruta_base.ends_with(".json"):
		return ruta_base.substr(0, ruta_base.length() - 5) + "_edits.json"
	return ruta_base + "_edits.json"


## Carga las ediciones previas guardadas en disco.
func cargar_ediciones_guardadas() -> Dictionary:
	var ruta: String = obtener_ruta_ediciones_json()
	if not FileAccess.file_exists(ruta):
		return {}

	var f: FileAccess = FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return {}

	var texto: String = f.get_as_text()
	f.close()

	var test_json: JSON = JSON.new()
	var err: Error = test_json.parse(texto)
	if err != OK or not (test_json.data is Dictionary):
		return {}

	var dict: Dictionary = test_json.data as Dictionary
	return dict.get("segments", {}) as Dictionary


## Guarda las modificaciones geométricas de un tramo específico en el archivo persistente.
func guardar_edicion_segmento(seg_id: String) -> void:
	if not paths.has(seg_id):
		return
	var p: Node = paths[seg_id]
	if p != null and p.has_method("serializar_datos"):
		_ediciones_guardadas[seg_id] = p.call("serializar_datos") as Dictionary
		_sincronizar_lista_eliminados_en_ediciones()
		_persistir_diccionario_switches()
		_escribir_archivo_ediciones()
		total_vias_editadas = _contar_ediciones_reales()


## Descarta las modificaciones guardadas de un tramo específico.
func descartar_edicion_segmento(seg_id: String) -> void:
	if _ediciones_guardadas.has(seg_id):
		_ediciones_guardadas.erase(seg_id)
		_escribir_archivo_ediciones()
		total_vias_editadas = _contar_ediciones_reales()


## Guarda la posición/ajustes de una estación en el journal de la red.
func guardar_edicion_estacion(estacion: Node) -> void:
	if estacion == null or not estacion.has_method("serializar_datos") or not estacion.has_method("obtener_id_edicion"):
		return
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	ests[str(estacion.call("obtener_id_edicion"))] = estacion.call("serializar_datos") as Dictionary
	_ediciones_guardadas["_estaciones"] = ests
	_escribir_archivo_ediciones()


## Descarta la edición guardada de una estación.
func descartar_edicion_estacion(id_estacion: String) -> void:
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	if ests.has(id_estacion):
		ests.erase(id_estacion)
		_ediciones_guardadas["_estaciones"] = ests
		_escribir_archivo_ediciones()


## Aplica a las estaciones de la escena las ediciones guardadas en el journal.
func aplicar_estaciones_guardadas() -> void:
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	if ests.is_empty() or not is_inside_tree():
		return
	var lista: Array[Node] = get_tree().get_nodes_in_group("estaciones")
	var aplicadas: int = 0
	for e: Node in lista:
		if not is_instance_valid(e) or not e.has_method("obtener_id_edicion") or not e.has_method("deserializar_datos"):
			continue
		var id_est: String = str(e.call("obtener_id_edicion"))
		if ests.has(id_est):
			e.call("deserializar_datos", ests[id_est] as Dictionary)
			aplicadas += 1
	if aplicadas > 0:
		print("TrackNetwork: %d estaciones restauradas desde el journal." % aplicadas)


## Guarda todas las vías y switches que hayan sido modificados en el archivo persistente.
func guardar_todas_las_ediciones() -> void:
	var total_guardadas: int = 0
	for seg_id: String in paths.keys():
		var p: Node = paths[seg_id]
		if p != null and p.get("esta_modificada") == true and p.has_method("serializar_datos"):
			_ediciones_guardadas[seg_id] = p.call("serializar_datos") as Dictionary
			p.set("estado_edicion", "Modificado (Guardado)")
			total_guardadas += 1

	# Bajas persistentes (tramos y aparatos de vía) y estado de los switches.
	_sincronizar_lista_eliminados_en_ediciones()
	_persistir_diccionario_switches()

	# Estaciones editadas (misma mecánica que los tramos).
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	if is_inside_tree():
		for e: Node in get_tree().get_nodes_in_group("estaciones"):
			if not is_instance_valid(e):
				continue
			if e.get("esta_editada") == true and e.has_method("serializar_datos") and e.has_method("obtener_id_edicion"):
				ests[str(e.call("obtener_id_edicion"))] = e.call("serializar_datos") as Dictionary
	_ediciones_guardadas["_estaciones"] = ests

	_escribir_archivo_ediciones()
	total_vias_editadas = _contar_ediciones_reales()
	var sw_total: int = (_ediciones_guardadas.get("_switches", {}) as Dictionary).size()
	print("TrackNetwork: Guardadas %d vías modificadas, %d eliminadas y %d switches en %s" % [
		total_guardadas,
		_eliminados_persistentes.size(),
		sw_total,
		obtener_ruta_ediciones_json()
	])


## Cuenta las ediciones reales de tramos, excluyendo las claves internas del journal.
func _contar_ediciones_reales() -> int:
	var total: int = 0
	for clave: Variant in _ediciones_guardadas.keys():
		if str(clave).begins_with("_"):
			continue
		total += 1
	return total


## Restaura todas las vías a su forma original base y descarta el archivo de ediciones.
func resetear_todas_las_ediciones() -> void:
	for seg_id: String in paths.keys():
		var p: Node = paths[seg_id]
		if p != null and p.has_method("resetear_a_original"):
			if p.get("esta_modificada") == true:
				p.call("resetear_a_original")

	_ediciones_guardadas.clear()
	_eliminados_persistentes.clear()
	_switches_eliminados_persistentes.clear()
	_escribir_archivo_ediciones()
	total_vias_editadas = 0

	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
	print("TrackNetwork: Todas las vías fueron restauradas a su forma original base.")


func _escribir_archivo_ediciones() -> void:
	var ruta: String = obtener_ruta_ediciones_json()
	# SEGURO: el JSON base de la red (OSM) es de sólo lectura. Si por configuración
	# la ruta del journal coincidiera con la del JSON base, no se escribe nada.
	var ruta_base: String = _obtener_ruta_red_json()
	if ruta == ruta_base:
		push_error("TrackNetwork: se abortó la escritura sobre el JSON base de la red (%s). Las ediciones van al journal '*_edits.json'." % ruta)
		return
	if FileAccess.file_exists(ruta):
		var f_prev: FileAccess = FileAccess.open(ruta, FileAccess.READ)
		if f_prev != null:
			var texto_prev: String = f_prev.get_as_text()
			f_prev.close()
			var j_prev: JSON = JSON.new()
			if j_prev.parse(texto_prev) == OK and j_prev.data is Dictionary:
				var d_prev: Dictionary = j_prev.data as Dictionary
				if d_prev.has("segments") and (d_prev["segments"] is Array):
					push_error("TrackNetwork: '%s' parece el JSON base de la red; se abortó la escritura." % ruta)
					return
	var contenido: Dictionary = {
		"version": 1,
		"red_origen": _obtener_ruta_red_json(),
		"total_ediciones": _contar_ediciones_reales(),
		"segments": _ediciones_guardadas
	}
	var f: FileAccess = FileAccess.open(ruta, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(contenido, "\t"))
		f.close()


## Encaja milimétricamente el extremo ("start" o "end") de un tramo con el switch o tramo vecino conectado.
func encajar_segmento_con_vecino(seg_id: String, extremo: String) -> void:
	if not paths.has(seg_id) or not segments_data.has(seg_id):
		return
	var p_seg: Path3D = paths[seg_id] as Path3D
	if p_seg == null or p_seg.curve == null or p_seg.curve.point_count < 2:
		return

	var seg: Dictionary = segments_data[seg_id] as Dictionary
	var nid: int = int(seg.get("node_start" if extremo == "start" else "node_end", 0))

	# 1. Caso A: En esta unión hay un Aparato de Vía (Switch)
	if aparatos_de_via.has(nid):
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw != null:
			var lead_conectado: FlexibleTrackLead = _buscar_lead_de_switch_para_segmento(sw, seg_id)
			if lead_conectado != null:
				_recalcular_conexion_switch_segmento(sw, p_seg, seg_id, extremo, lead_conectado)
				print("TrackNetwork: Extremo '%s' de vía '%s' encajado con switch '%s' (%s)." % [extremo, seg_id, sw.name, lead_conectado.name])
				return

	# 2. Caso B: En esta unión hay otro tramo de vía conectado
	if junctions.has(str(nid)):
		var j_dict: Dictionary = junctions[str(nid)] as Dictionary
		var conns: Array = j_dict.get("segments", []) as Array
		for c_raw: Variant in conns:
			var c: Dictionary = c_raw as Dictionary
			var other_id: String = str(c.get("segment_id", ""))
			if other_id != seg_id and paths.has(other_id):
				var other_path: Path3D = paths[other_id] as Path3D
				if other_path != null and other_path.curve != null and other_path.curve.point_count >= 2:
					var other_end: String = str(c.get("end", "start"))
					var other_idx: int = 0 if other_end == "start" else (other_path.curve.point_count - 1)
					var other_pt_local: Vector3 = other_path.curve.get_point_position(other_idx)
					var pos_world: Vector3 = other_path.to_global(other_pt_local)
					var pos_local_seg: Vector3 = p_seg.global_transform.affine_inverse() * pos_world

					p_seg.set("_bloqueo_reconstruccion", true)
					if extremo == "start":
						p_seg.curve.set_point_position(0, pos_local_seg)
						p_seg.curve.set_point_in(0, Vector3.ZERO)
					else:
						var last_idx: int = p_seg.curve.point_count - 1
						p_seg.curve.set_point_position(last_idx, pos_local_seg)
						p_seg.curve.set_point_out(last_idx, Vector3.ZERO)

					p_seg.set("_bloqueo_reconstruccion", false)
					p_seg.set("esta_modificada", true)
					p_seg.set("estado_edicion", "Modificado")
					if p_seg.has_method("notificar_geometria_actualizada"):
						p_seg.call("notificar_geometria_actualizada")
					print("TrackNetwork: Extremo '%s' de vía '%s' encajado con vía vecina '%s'." % [extremo, seg_id, other_id])
					return

	# 3. Caso C: Ajustar a la posición nominal de la unión del JSON
	var j_pos: Vector3 = _obtener_posicion_junction(nid)
	if not j_pos.is_zero_approx():
		var pos_local: Vector3 = p_seg.global_transform.affine_inverse() * j_pos
		p_seg.set("_bloqueo_reconstruccion", true)
		if extremo == "start":
			p_seg.curve.set_point_position(0, pos_local)
		else:
			p_seg.curve.set_point_position(p_seg.curve.point_count - 1, pos_local)
		p_seg.set("_bloqueo_reconstruccion", false)
		p_seg.set("esta_modificada", true)
		p_seg.set("estado_edicion", "Modificado")
		if p_seg.has_method("notificar_geometria_actualizada"):
			p_seg.call("notificar_geometria_actualizada")
		print("TrackNetwork: Extremo '%s' de vía '%s' encajado a nodo de unión %d." % [extremo, seg_id, nid])


## Recibida al editar un tramo. Se AGRUPA por frame y se resuelve de forma local:
## varias señales del mismo arrastre se procesan una sola vez y sólo se reconstruye
## el vecindario del tramo, no la red entera (que congelaba el editor por segundos).
func _on_segmento_geometria_modificada(seg_id: String) -> void:
	if not paths.has(seg_id) or not is_inside_tree():
		return
	_segmentos_edicion_pendientes[seg_id] = true
	if _edicion_diferida_programada:
		return
	_edicion_diferida_programada = true
	call_deferred("_procesar_ediciones_pendientes")


func _procesar_ediciones_pendientes() -> void:
	_edicion_diferida_programada = false
	if _segmentos_edicion_pendientes.is_empty() or not is_inside_tree():
		_segmentos_edicion_pendientes.clear()
		return
	var segs: Array[String] = []
	for k: Variant in _segmentos_edicion_pendientes.keys():
		segs.append(str(k))
	_segmentos_edicion_pendientes.clear()
	_reconstruir_conexiones_locales(segs)


func _recalcular_conexion_switch_segmento(sw: BaseTurnout, p_seg: Path3D, seg_id: String, extremo: String, lead: FlexibleTrackLead) -> void:
	if sw == null or p_seg == null or p_seg.curve == null or lead == null:
		return
	_conectar_lead_a_segmento(sw, lead, p_seg, seg_id, extremo, sw.node_id)


func _buscar_lead_de_switch_para_segmento(sw: BaseTurnout, seg_id: String) -> FlexibleTrackLead:
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return null

	if sw.via_comun_id == seg_id:
		var l: FlexibleTrackLead = g_ext.get_node_or_null("Extremo_Entrada_Comun") as FlexibleTrackLead
		if l != null: return l
		l = g_ext.get_node_or_null("Extremo_Via_1_Entrada") as FlexibleTrackLead
		if l != null: return l
	if sw.via_directa_id == seg_id:
		var l: FlexibleTrackLead = g_ext.get_node_or_null("Extremo_Salida_Directa") as FlexibleTrackLead
		if l != null: return l
		l = g_ext.get_node_or_null("Extremo_Via_1_Salida") as FlexibleTrackLead
		if l != null: return l
	if sw.via_desviada_id == seg_id:
		var l: FlexibleTrackLead = g_ext.get_node_or_null("Extremo_Salida_Desviada") as FlexibleTrackLead
		if l != null: return l
		l = g_ext.get_node_or_null("Extremo_Salida_Izquierda") as FlexibleTrackLead
		if l != null: return l
		l = g_ext.get_node_or_null("Extremo_Salida_Derecha") as FlexibleTrackLead
		if l != null: return l
		l = g_ext.get_node_or_null("Extremo_Via_2_Salida") as FlexibleTrackLead
		if l != null: return l

	# Fallback: buscar el lead más cercano geométricamente al segmento
	var p_seg: Path3D = paths.get(seg_id) as Path3D
	if p_seg != null and p_seg.curve != null and p_seg.curve.point_count > 0:
		var pt_seg_w: Vector3 = p_seg.to_global(p_seg.curve.get_point_position(0))
		var mejor_lead: FlexibleTrackLead = null
		var mejor_dist: float = 1e9
		for ch: Node in g_ext.get_children():
			if ch is FlexibleTrackLead:
				var lead: FlexibleTrackLead = ch as FlexibleTrackLead
				var p_lead_w: Vector3 = lead.global_transform * lead.obtener_posicion_extremo_exterior()
				var d: float = p_lead_w.distance_to(pt_seg_w)
				if d < mejor_dist:
					mejor_dist = d
					mejor_lead = lead
		if mejor_dist < 60.0:
			return mejor_lead
	return null
## Crea una curva desviada estándar a derecha (espejada de Tipo A canónico).
func _crear_curva_desviada_estandar_derecha() -> Curve3D:
	var c: Curve3D = Curve3D.new()
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, 10.5))
	c.add_point(Vector3(2.8, 0.0, 28.0), Vector3(-0.98, 0.0, -10.5), Vector3.ZERO)
	return c
