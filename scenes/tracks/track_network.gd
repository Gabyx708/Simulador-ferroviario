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
const GENERAR_SWITCHES_COMPUESTOS_D_E: bool = false
const PROPIEDADES_SWITCH_JOURNAL = ["largo_turnout", "largo_aguja", "largo_zona_cruce", "angulo_cruce_rad", "trocha_media", "luz_pestana", "paso_durmientes", "generar_extremos_flexibles", "mostrar_marmita", "distancia_culling_cuerpo", "distancia_culling_detalles"]
const CURVAS_SWITCH_JOURNAL = ["curva_directa", "curva_desviada", "curva_izquierda", "curva_derecha", "curva_a", "curva_b"]
const EDITABLE_TRACK_SEGMENT_SCRIPT = preload("res://scenes/tracks/editable_track_segment.gd")
const DISTANCIA_MINIMA_ADAPTACION_SWITCH: float = 120.0
const MARGEN_FINAL_SEGMENTO_SWITCH: float = 2.0
## Solape mínimo entre la vía completa y el extremo flexible. Ambos usan el
## mismo punto de corte, pero esta tolerancia evita una grieta por la precisión
## del bake o por la interpolación de dos mallas independientes.
const SOLAPE_VISUAL_UNION_SWITCH: float = 0.020
const PASO_BUSQUEDA_ADAPTACION_SWITCH: float = 10.0
const DOT_TANGENTE_ADAPTACION_SWITCH: float = 0.985
signal red_cargada(total_segmentos: int, total_uniones: int)
signal switch_conmutado(nodo_id: int, segmento_destino: String)
signal reservas_cambiadas()
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

## Distancia máxima entre extremos de Path3D para considerarlos una unión
## creada manualmente en el editor.
@export_range(0.05, 5.0, 0.05, "suffix:m") var tolerancia_union_manual: float = 2.0

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
## Exclusión mutua por tramo y por aparato. Las reservas se mantienen hasta
## que la cola completa del tren despeja el recurso.
var _propietarios_recursos: Dictionary = {}
var _reservas_por_tren: Dictionary = {}
var _cola_solicitudes_reserva: Array[Dictionary] = []
## Intenciones de circulación para bifurcaciones paralelas. A diferencia de
## una reserva física, no bloquean el tramo: sólo impiden que el planificador
## mande todas las formaciones a la misma rama antes de que lleguen a la aguja.
var _itinerarios_ramas_tren: Dictionary = {}
const RAMAS_IDA_BALANCEADAS: Array[String] = ["seg_735", "seg_737"]
const PENALIZACION_RAMA_OCUPADA_M: float = 750.0
## Diccionario de aparatos de vía instanciados: node_id (int) -> BaseTurnout
var aparatos_de_via: Dictionary = {}
## Marcador efímero de la aguja que el usuario está inspeccionando desde el HUD.
## No participa de la topología, reservas ni colisiones.
var _indicador_switch_hud: Node3D = null
var _indicador_switch_hud_id: int = 0
## Rango métrico útil de vía plena por segmento [d_inicio, d_fin] libre de solapes con switches
var _recortes_segmentos: Dictionary = {}
## Intervalos EXCLUIDOS por segmento (uno por cada unión): permite que un tramo
## entre DOS aparatos conserve vía plena en el medio en vez de colapsar a absorbido.
var _recortes_extra: Dictionary = {}
## Huecos interiores ocupados por un crossover D en Path3D que lo atraviesan.
## Se mantienen ambos lados de la vía; no se modifica la Curve3D de ruteo.
var _recortes_internos_switch: Dictionary = {}
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
var _huellas_estaciones: Dictionary = {}
var _huellas_config_switches: Dictionary = {}
# Huella de las curvas reales copiadas por cada aparato (evita recalibrar de más).
var _hash_recalibracion: Dictionary = {}
# Aparatos ya alineados al junction (el ajuste se aplica una sola vez por sesión).
var _refit_hecho: Dictionary = {}
var _switch_movido_pendiente: bool = false
var _acum_polling_switches: float = 0.0
## Instancias que el usuario modificó durante esta sesión. Complementa la
## marca serializada de BaseTurnout para no reemplazarlas al generar switches.
var _switches_editados_manualmente: Dictionary = {}
# Edición incremental: tramos cuya geometría cambió y se resolverán agrupados.
var _segmentos_edicion_pendientes: Dictionary = {}
var _edicion_diferida_programada: bool = false
var _autoguardado_pendiente: bool = false
var _tiempo_autoguardado: float = 0.0
const RETARDO_AUTOGUARDADO: float = 0.8
## Respaldo de topología JSON mientras se añaden uniones temporales detectadas
## directamente desde los extremos de los Path3D del editor.
var _datos_segmentos_previos_uniones_manuales: Dictionary = {}
## Respaldo de junctions existentes mientras se les agregan extremos creados
## desde el editor. Así la detección es reversible y no modifica el JSON.
var _junctions_previas_uniones_manuales: Dictionary = {}

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
		_integrar_topologia_de_switches_serializados()
		_integrar_empalmes_de_escena()
		_sincronizar_expansion_guardada_de_switches()
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

		if Engine.is_editor_hint():
			_sincronizar_ediciones_serializadas_con_journal()
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


func _exit_tree() -> void:
	# Las ediciones ya capturadas en memoria no se pierden al cerrar la escena
	# antes de que venza el retardo de escritura.
	if Engine.is_editor_hint() and _autoguardado_pendiente:
		_escribir_archivo_ediciones()


## Propaga la expansión serializada del switch a sus hijos flexibles después
## de que el árbol de escena esté completo. Debe ocurrir antes de calcular los
## recortes que generan la geometría visible de los Path3D.
func _sincronizar_expansion_guardada_de_switches() -> void:
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw != null:
			sw.sincronizar_expansion_extremos_flexibles()


## La escena guardada es la fuente principal. Actualiza el respaldo JSON con
## sus vías modificadas y switches antes de aceptar nuevas ediciones del editor.
func _sincronizar_ediciones_serializadas_con_journal() -> void:
	var cambio: bool = false
	for seg_id: String in paths.keys():
		var via: EditableTrackSegment = paths[seg_id] as EditableTrackSegment
		if via == null or not via.esta_modificada:
			continue
		var datos: Dictionary = via.serializar_datos()
		if _ediciones_guardadas.get(seg_id, {}) != datos:
			_ediciones_guardadas[seg_id] = datos
			cambio = true
	var switches_previos: Dictionary = (_ediciones_guardadas.get("_switches", {}) as Dictionary).duplicate(true)
	_persistir_diccionario_switches()
	if switches_previos != (_ediciones_guardadas.get("_switches", {}) as Dictionary):
		cambio = true
	if cambio:
		_autoguardado_pendiente = true
		_tiempo_autoguardado = 0.0


## La generación manual puede crear una unión temporal que no existe en el
## JSON base. Al guardar, Godot conserva el switch y sus IDs de vías, pero no
## esa tabla temporal de junctions. Reconstruimos aquí la topología necesaria
## desde los switches serializados para que TODOS sus leads y Path3D reciban
## los mismos recortes al reabrir la escena.
func _integrar_topologia_de_switches_serializados() -> void:
	_reasignar_ramas_eliminadas_de_switches()
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw == null or sw.node_id == 0:
			continue
		var clave_junction: String = str(sw.node_id)
		var junction: Dictionary = junctions.get(clave_junction, {
			"id": sw.node_id,
			"position": {"x": sw.position.x, "y": sw.position.y, "z": sw.position.z},
			"segments": []
		}) as Dictionary
		var conexiones: Array = junction.get("segments", []) as Array
		for sid: String in [sw.via_comun_id, sw.via_directa_id, sw.via_desviada_id]:
			if sid.is_empty() or not paths.has(sid):
				continue
			var extremo: String = _extremo_de_segmento_para_switch_serializado(sid, conexiones, sw)
			var existe: bool = false
			for conexion_raw: Variant in conexiones:
				if conexion_raw is Dictionary:
					var conexion: Dictionary = conexion_raw as Dictionary
					if str(conexion.get("segment_id", "")) == sid and str(conexion.get("end", "")) == extremo:
						existe = true
						break
			if not existe:
				conexiones.append({"segment_id": sid, "end": extremo})
			if segments_data.has(sid):
				var datos: Dictionary = (segments_data[sid] as Dictionary).duplicate(true)
				if extremo == "start":
					datos["node_start"] = sw.node_id
				else:
					datos["node_end"] = sw.node_id
				segments_data[sid] = datos
		junction["segments"] = conexiones
		junctions[clave_junction] = junction


## Empalmes dibujados a mano en la escena que la topología JSON no conoce: dos
## extremos de Path3D que coinciden y continúan uno en el otro. Se guardan aparte
## de `junctions` para que sólo los use el ruteo y no alteren los recortes de
## los aparatos. Clave: str(node_id) -> Array[{segment_id, end}].
var _empalmes_escena: Dictionary = {}
const TOLERANCIA_EMPALME_ESCENA_M: float = 1.0


func _integrar_empalmes_de_escena() -> void:
	_empalmes_escena.clear()
	var extremos: Array[Dictionary] = []
	for sid: String in paths.keys():
		var via: Path3D = paths[sid] as Path3D
		if via == null or not is_instance_valid(via) or via.curve == null or via.curve.point_count < 2 or not segments_data.has(sid):
			continue
		var datos: Dictionary = segments_data[sid] as Dictionary
		for extremo_local: String in ["start", "end"]:
			var extremo: String = _extremo_topologico_de_local(sid, extremo_local)
			var indice: int = 0 if extremo_local == "start" else via.curve.point_count - 1
			extremos.append({
				"segment_id": sid, "end": extremo,
				"node": int(datos.get("node_start" if extremo == "start" else "node_end", 0)),
				"posicion": via.to_global(via.curve.get_point_position(indice)),
				"vector": _obtener_vector_salida_segmento(sid, extremo_local)
			})
	var agregados: int = 0
	for a: Dictionary in extremos:
		for b: Dictionary in extremos:
			if a["segment_id"] == b["segment_id"] or int(a["node"]) == int(b["node"]):
				continue
			if (a["posicion"] as Vector3).distance_to(b["posicion"] as Vector3) > TOLERANCIA_EMPALME_ESCENA_M:
				continue
			# Sólo una continuación: los dos tramos salen del punto en sentidos opuestos.
			if (a["vector"] as Vector2).dot(b["vector"] as Vector2) > -0.5:
				continue
			var clave: String = str(a["node"])
			var lista: Array = _empalmes_escena.get(clave, []) as Array
			lista.append({"segment_id": b["segment_id"], "end": b["end"]})
			_empalmes_escena[clave] = lista
			agregados += 1
	if agregados > 0:
		print("TrackNetwork: %d empalmes de la escena incorporados al grafo de ruteo." % agregados)


## Un aparato puede seguir nombrando una rama cuyo Path3D se borró después de
## estirar la vía vecina hasta el aparato (seg_74 → seg_75 en Rafael Calzada).
## Esa vía queda con un extremo suelto junto al switch y la red se corta; se la
## adopta como la rama faltante para conservar la continuidad.
func _reasignar_ramas_eliminadas_de_switches() -> void:
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw == null or not is_instance_valid(sw) or sw.node_id == 0 or not sw.is_inside_tree():
			continue
		for propiedad: String in ["via_comun_id", "via_directa_id", "via_desviada_id"]:
			var sid: String = str(sw.get(propiedad))
			if sid.is_empty() or paths.has(sid):
				continue
			var reemplazo: String = _buscar_extremo_suelto_junto_a_switch(sw)
			if reemplazo.is_empty():
				continue
			sw.set(propiedad, reemplazo)
			print("TrackNetwork: el aparato %d reemplaza la rama eliminada %s por %s." % [sw.node_id, sid, reemplazo])


## Devuelve el tramo más cercano al switch cuyo extremo no enlaza con ninguna
## otra vía existente. Los extremos ya conectados nunca se reasignan.
func _buscar_extremo_suelto_junto_a_switch(sw: BaseTurnout) -> String:
	var mejor: String = ""
	var mejor_distancia: float = tolerancia_union_manual
	for sid: String in paths.keys():
		if sid in [sw.via_comun_id, sw.via_directa_id, sw.via_desviada_id]:
			continue
		var via: Path3D = paths[sid] as Path3D
		if via == null or not is_instance_valid(via) or via.curve == null or via.curve.point_count < 2:
			continue
		for extremo_local: String in ["start", "end"]:
			var indice: int = 0 if extremo_local == "start" else via.curve.point_count - 1
			var distancia: float = via.to_global(via.curve.get_point_position(indice)).distance_to(sw.global_position)
			if distancia > mejor_distancia:
				continue
			var extremo: String = _extremo_topologico_de_local(sid, extremo_local)
			var datos: Dictionary = segments_data.get(sid, {}) as Dictionary
			var jid: int = int(datos.get("node_start" if extremo == "start" else "node_end", 0))
			if jid == sw.node_id or _junction_tiene_otras_vias(jid, sid):
				continue
			mejor = sid
			mejor_distancia = distancia
	return mejor


func _junction_tiene_otras_vias(jid: int, sid_excluido: String) -> bool:
	for conexion_raw: Variant in (junctions.get(str(jid), {}) as Dictionary).get("segments", []):
		if conexion_raw is Dictionary:
			var otro: String = str((conexion_raw as Dictionary).get("segment_id", ""))
			if otro != sid_excluido and paths.has(otro):
				return true
	return false


## Prefiere el extremo que ya estaba asignado a la junction. Para una rama
## generada manualmente, toma el extremo del Path3D más cercano al switch.
func _extremo_de_segmento_para_switch_serializado(seg_id: String, conexiones: Array, sw: BaseTurnout) -> String:
	for conexion_raw: Variant in conexiones:
		if conexion_raw is Dictionary:
			var conexion: Dictionary = conexion_raw as Dictionary
			if str(conexion.get("segment_id", "")) == seg_id:
				return str(conexion.get("end", "start"))
	var via: Path3D = paths.get(seg_id) as Path3D
	if via == null or via.curve == null or via.curve.point_count < 2:
		return "start"
	var p_inicio: Vector3 = via.to_global(via.curve.get_point_position(0))
	var p_fin: Vector3 = via.to_global(via.curve.get_point_position(via.curve.point_count - 1))
	return "start" if p_inicio.distance_squared_to(sw.global_position) <= p_fin.distance_squared_to(sw.global_position) else "end"


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
	# Las eliminaciones hechas desde el árbol de escena ya las conserva el
	# UndoRedo del editor. Persistirlas desde un callback diferido puede liberar
	# la misma instancia que el editor intenta restaurar con Ctrl+Z.
	if Engine.is_editor_hint():
		_bajas_tramos_pendientes.clear()
		return
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
			if not ed.datos_modificados.is_connected(_on_segmento_datos_modificados):
				ed.datos_modificados.connect(_on_segmento_datos_modificados)
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
	_huellas_config_switches.clear()
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw != null:
			_huellas_switches[nid] = _huella_switch(sw)
			_huellas_config_switches[nid] = _huella_config_switch(sw)


## Huella estable de un aparato: transform + estado de agujas.
func _huella_switch(sw: BaseTurnout) -> int:
	var h: int = hash(sw.transform)
	h = hash(h ^ hash(sw.is_desviado()))
	h = hash(h ^ hash(sw.via_comun_id) ^ hash(sw.via_directa_id) ^ hash(sw.via_desviada_id))
	return h


## Detecta cambios de inspector y de extremos flexibles que no mueven el nodo.
func _huella_config_switch(sw: BaseTurnout) -> int:
	var h: int = 0
	var campos: Dictionary = {}
	for propiedad_raw: Variant in sw.get_property_list():
		var propiedad: Dictionary = propiedad_raw as Dictionary
		campos[str(propiedad.get("name", ""))] = true
	for nombre: String in ["largo_turnout", "largo_aguja", "largo_zona_cruce", "angulo_cruce_rad", "trocha_media", "luz_pestana", "paso_durmientes", "generar_extremos_flexibles", "mostrar_marmita", "distancia_culling_cuerpo", "distancia_culling_detalles", "expansion_extremos_flexibles", "curva_directa", "curva_desviada", "curva_izquierda", "curva_derecha", "curva_a", "curva_b"]:
		if not campos.has(nombre):
			continue
		var valor: Variant = sw.get(nombre)
		if valor is Curve3D:
			var curva: Curve3D = valor as Curve3D
			h = hash(h ^ curva.point_count)
			for i: int in curva.point_count:
				h = hash(h ^ hash(curva.get_point_position(i)) ^ hash(curva.get_point_in(i)) ^ hash(curva.get_point_out(i)))
		else:
			h = hash(h ^ hash(valor))
	var grupo: Node = sw.get_node_or_null("ExtremosFlexibles")
	if grupo != null:
		for hijo: Node in grupo.get_children():
			if not (hijo is FlexibleTrackLead):
				continue
			var lead: FlexibleTrackLead = hijo as FlexibleTrackLead
			h = hash(h ^ hash(lead.name) ^ hash(lead.expansion_sobre_path))
			h = hash(h ^ hash(lead.longitud_extension) ^ hash(lead.offset_lateral) ^ hash(lead.offset_vertical))
			h = hash(h ^ hash(lead.angulo_curva_deg) ^ hash(lead.factor_tangente))
			h = hash(h ^ hash(lead.usar_extremo_manual) ^ hash(lead.respetar_edicion_manual))
			if lead.respetar_edicion_manual:
				h = hash(h ^ hash(lead.punto_inicio) ^ hash(lead.direccion_inicio))
				h = hash(h ^ hash(lead.punto_fin_manual) ^ hash(lead.direccion_fin_manual))
	return h


func _process(delta: float) -> void:
	# Las bajas de tramos se confirman siempre (editor y juego): la ventana de
	# gracia evita registrar bajas por operaciones transitorias del editor.
	_procesar_bajas_segmentos_pendientes()
	if Engine.is_editor_hint() and _autoguardado_pendiente:
		_tiempo_autoguardado += delta
		if _tiempo_autoguardado >= RETARDO_AUTOGUARDADO:
			_autoguardado_pendiente = false
			_tiempo_autoguardado = 0.0
			_sincronizar_lista_eliminados_en_ediciones()
			_persistir_diccionario_switches()
			_escribir_archivo_ediciones()
	if not Engine.is_editor_hint():
		return
	# El sondeo de huellas de aparatos se limita a ~0.25 s: recorrer los ~200 switches
	# cada frame (hashear transform+estado y comprobar ancestros) es costoso en el editor.
	_acum_polling_switches += delta
	if _acum_polling_switches < INTERVALO_POLLING_SWITCHES:
		return
	_acum_polling_switches = 0.0
	_sincronizar_estaciones_serializadas_con_journal()
	if aparatos_de_via.is_empty():
		return
	var cambio: bool = false
	var cambio_config: bool = false
	for nid: int in aparatos_de_via.keys():
		var sw: BaseTurnout = aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var h: int = _huella_switch(sw)
		if not _huellas_switches.has(nid) or int(_huellas_switches[nid]) != h:
			_huellas_switches[nid] = h
			sw.marcar_editado_para_regeneracion()
			_switches_editados_manualmente[sw.get_instance_id()] = true
			cambio = true
		var config_h: int = _huella_config_switch(sw)
		if not _huellas_config_switches.has(nid) or int(_huellas_config_switches[nid]) != config_h:
			_huellas_config_switches[nid] = config_h
			sw.marcar_editado_para_regeneracion()
			_switches_editados_manualmente[sw.get_instance_id()] = true
			_autoguardado_pendiente = true
			_tiempo_autoguardado = 0.0
			cambio_config = true
	if cambio_config:
		_persistir_diccionario_switches()
	if not cambio:
		_detectar_switches_removidos()
		return
	# El sondeo cada `INTERVALO_POLLING_SWITCHES` ya actúa de debounce.
	reintegrar_switches_editados()


## Detecta aparatos que el usuario quitó del contenedor en el editor y persiste su baja.
## Sólo se ejecuta en el editor: si la escena entera se desmonta, este proceso no corre.
func _detectar_switches_removidos() -> void:
	# En el editor una baja visual puede ser una operación reversible. La baja
	# persistente se hace sólo mediante eliminar_switch(), no desde el sondeo.
	if Engine.is_editor_hint():
		return
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
			"expansion_extremos_flexibles": sw.expansion_extremos_flexibles,
			"tipo_aparato": sw.get_tipo_aparato(),
			"desviada": sw.is_desviado()
		}
		var nombres_propiedades: Dictionary = {}
		for propiedad_raw: Variant in sw.get_property_list():
			var propiedad: Dictionary = propiedad_raw as Dictionary
			nombres_propiedades[str(propiedad.get("name", ""))] = true
		var propiedades: Dictionary = {}
		for nombre_propiedad: String in PROPIEDADES_SWITCH_JOURNAL:
			if nombres_propiedades.has(nombre_propiedad):
				propiedades[nombre_propiedad] = sw.get(nombre_propiedad)
		(sw_dict[str(nid)] as Dictionary)["propiedades"] = propiedades
		var curvas: Dictionary = {}
		for nombre_curva: String in CURVAS_SWITCH_JOURNAL:
			if nombres_propiedades.has(nombre_curva) and sw.get(nombre_curva) is Curve3D:
				curvas[nombre_curva] = EditableTrackSegment.curva_a_dict(sw.get(nombre_curva) as Curve3D)
		if not curvas.is_empty():
			(sw_dict[str(nid)] as Dictionary)["curvas"] = curvas
		# Extremos flexibles fijados a mano (edición de los extremos del switch).
		var extremos: Dictionary = {}
		var expansiones: Dictionary = {}
		var ajustes: Dictionary = {}
		var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
		if g_ext != null:
			for h: Node in g_ext.get_children():
				if not (h is FlexibleTrackLead):
					continue
				var l: FlexibleTrackLead = h as FlexibleTrackLead
				expansiones[String(l.name)] = l.expansion_sobre_path
				ajustes[String(l.name)] = {
					"expansion_sobre_path": l.expansion_sobre_path,
					"longitud_extension": l.longitud_extension,
					"offset_lateral": l.offset_lateral,
					"offset_vertical": l.offset_vertical,
					"angulo_curva_deg": l.angulo_curva_deg,
					"factor_tangente": l.factor_tangente,
					"usar_extremo_manual": l.usar_extremo_manual,
					"respetar_edicion_manual": l.respetar_edicion_manual
				}
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
		if not expansiones.is_empty():
			(sw_dict[str(nid)] as Dictionary)["expansiones_extremos"] = expansiones
		if not ajustes.is_empty():
			(sw_dict[str(nid)] as Dictionary)["ajustes_extremos"] = ajustes
	_ediciones_guardadas["_switches"] = sw_dict


## Aplica a los aparatos recién generados las posiciones/estados guardados en el
## journal. Se usa únicamente al regenerar la red desde el JSON base.
func _aplicar_switches_guardados(omitidos: Dictionary = {}) -> void:
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
		if omitidos.has(sw.get_instance_id()):
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
		var propiedades: Dictionary = datos.get("propiedades", {}) as Dictionary
		for nombre_propiedad: String in propiedades.keys():
			if nombre_propiedad in PROPIEDADES_SWITCH_JOURNAL and sw.get(nombre_propiedad) != propiedades[nombre_propiedad]:
				sw.set(nombre_propiedad, propiedades[nombre_propiedad])
		var curvas: Dictionary = datos.get("curvas", {}) as Dictionary
		for nombre_curva: String in curvas.keys():
			if nombre_curva in CURVAS_SWITCH_JOURNAL and curvas[nombre_curva] is Dictionary:
				var curva_restaurada: Curve3D = EditableTrackSegment.dict_a_curva(curvas[nombre_curva] as Dictionary)
				if curva_restaurada.point_count >= 2:
					sw.set(nombre_curva, curva_restaurada)
		if datos.has("expansion_extremos_flexibles"):
			sw.expansion_extremos_flexibles = float(datos["expansion_extremos_flexibles"])
		sw.conmutar_a(1 if bool(datos.get("desviada", false)) else 0)
		if datos.has("ajustes_extremos"):
			_aplicar_ajustes_extremos_guardados(sw, datos)
		else:
			_aplicar_expansiones_extremos_guardadas(sw, datos)
		_aplicar_extremos_guardados(sw, datos)
		aplicados += 1
	if aplicados > 0:
		print("TrackNetwork: %d switches restaurados desde el journal de ediciones." % aplicados)


## Aplica a un aparato los extremos flexibles fijados a mano guardados en el journal.
## Devuelve cuántos extremos restauró.
func _aplicar_extremos_guardados(sw: BaseTurnout, datos: Dictionary, solo_faltantes: bool = false) -> int:
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
		if solo_faltantes and lead.respetar_edicion_manual:
			continue
		var ajustes: Dictionary = datos.get("ajustes_extremos", {}) as Dictionary
		if ajustes.has(nombre) and not bool((ajustes[nombre] as Dictionary).get("respetar_edicion_manual", true)):
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


func _aplicar_ajustes_extremos_guardados(sw: BaseTurnout, datos: Dictionary, restaurar_expansion: bool = true, omitidos: Dictionary = {}) -> int:
	var ajustes: Dictionary = datos.get("ajustes_extremos", {}) as Dictionary
	var grupo: Node = sw.get_node_or_null("ExtremosFlexibles")
	if grupo == null:
		return 0
	var aplicados: int = 0
	for nombre: String in ajustes.keys():
		if omitidos.has(nombre):
			continue
		var lead: FlexibleTrackLead = grupo.get_node_or_null(nombre) as FlexibleTrackLead
		if lead == null:
			continue
		var a: Dictionary = ajustes[nombre] as Dictionary
		lead._bloqueo_reconstruccion = true
		if restaurar_expansion:
			lead.expansion_sobre_path = maxf(0.0, float(a.get("expansion_sobre_path", lead.expansion_sobre_path)))
		lead.longitud_extension = float(a.get("longitud_extension", lead.longitud_extension))
		lead.offset_lateral = float(a.get("offset_lateral", lead.offset_lateral))
		lead.offset_vertical = float(a.get("offset_vertical", lead.offset_vertical))
		lead.angulo_curva_deg = float(a.get("angulo_curva_deg", lead.angulo_curva_deg))
		lead.factor_tangente = float(a.get("factor_tangente", lead.factor_tangente))
		lead.usar_extremo_manual = bool(a.get("usar_extremo_manual", lead.usar_extremo_manual))
		lead.respetar_edicion_manual = bool(a.get("respetar_edicion_manual", lead.respetar_edicion_manual))
		lead._bloqueo_reconstruccion = false
		lead.reconstruir_tramo()
		aplicados += 1
	return aplicados


## Restaura la expansión de TODOS los leads del aparato, incluidos los que no
## tienen una edición manual. Así cada Path3D recibe al cargar el mismo recorte
## que tenía al guardar la escena.
func _aplicar_expansiones_extremos_guardadas(sw: BaseTurnout, datos: Dictionary) -> int:
	var expansiones: Dictionary = datos.get("expansiones_extremos", {}) as Dictionary
	if expansiones.is_empty():
		return 0
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return 0
	var aplicados: int = 0
	for nombre: String in expansiones.keys():
		var lead: FlexibleTrackLead = g_ext.get_node_or_null(nombre) as FlexibleTrackLead
		if lead == null:
			continue
		lead.expansion_sobre_path = maxf(0.0, float(expansiones[nombre]))
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
		var datos: Dictionary = sw_dict[nid_str] as Dictionary
		if str(datos.get("tipo_aparato", "")) != sw.get_tipo_aparato():
			continue
		if not str(datos.get("via_comun_id", "")).is_empty() and str(datos.get("via_comun_id", "")) != sw.via_comun_id:
			continue
		var manuales_escena: Dictionary = {}
		var grupo: Node = sw.get_node_or_null("ExtremosFlexibles")
		if grupo != null:
			for hijo: Node in grupo.get_children():
				if hijo is FlexibleTrackLead and (hijo as FlexibleTrackLead).respetar_edicion_manual:
					manuales_escena[String(hijo.name)] = true
		var expansion_coincide: bool = is_equal_approx(float(datos.get("expansion_extremos_flexibles", sw.expansion_extremos_flexibles)), sw.expansion_extremos_flexibles)
		total += _aplicar_extremos_guardados(sw, datos, true)
		if datos.has("ajustes_extremos"):
			total += _aplicar_ajustes_extremos_guardados(sw, datos, expansion_coincide, manuales_escena)
		elif expansion_coincide:
			total += _aplicar_expansiones_extremos_guardadas(sw, datos)
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
	_recortes_internos_switch.clear()
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
				if not ed.datos_modificados.is_connected(_on_segmento_datos_modificados):
					ed.datos_modificados.connect(_on_segmento_datos_modificados)
			paths[sid] = hijo as Path3D
		elif hijo.get_child_count() > 0:
			_recolectar_paths_recursivo(hijo)


## Recorre recursivamente _contenedor_switches para sincronizar 'aparatos_de_via' con los nodos existentes.
func recolectar_switches_desde_arbol() -> void:
	aparatos_de_via.clear()
	_switches_ordenados.clear()
	if _contenedor_switches != null:
		_recolectar_switches_recursivo(_contenedor_switches)
	_eliminar_switches_duplicados()
	#print("TrackNetwork: Sincronizados %d aparatos de vía desde el árbol de escena." % aparatos_de_via.size())


## Dos IDs de junction pueden describir la misma terna de vías. Conservar los
## dos aparatos superpone sus mallas y además los vuelve a preservar al regenerar.
func _eliminar_switches_duplicados() -> void:
	var por_vias: Dictionary = {}
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw == null or not is_instance_valid(sw):
			continue
		var firma: String = _firma_vias_switch(sw)
		if firma.is_empty():
			continue
		var previo: BaseTurnout = por_vias.get(firma) as BaseTurnout
		if previo == sw:
			continue
		if previo == null:
			por_vias[firma] = sw
		elif sw.expansion_extremos_flexibles > previo.expansion_extremos_flexibles:
			_quitar_aparato_del_registro(previo)
			por_vias[firma] = sw
		else:
			_quitar_aparato_del_registro(sw)


func _firma_vias_switch(sw: BaseTurnout) -> String:
	var ids: Array[String] = [sw.via_comun_id, sw.via_directa_id, sw.via_desviada_id]
	var firma: String = _firma_segmentos_switch(ids)
	if not firma.is_empty():
		return firma
	if sw.get_tipo_aparato() == "TIPO_C" and sw.has_meta("linea_a_segs") and sw.has_meta("linea_b_segs"):
		ids.clear()
		for sid_raw: Variant in (sw.get_meta("linea_a_segs") as Array):
			ids.append(str(sid_raw))
		for sid_raw: Variant in (sw.get_meta("linea_b_segs") as Array):
			ids.append(str(sid_raw))
		return _firma_segmentos_switch(ids)
	return ""


func _firma_segmentos_switch(ids: Array[String]) -> String:
	if ids.size() < 3 or ids.size() > 4:
		return ""
	for sid: String in ids:
		if sid.is_empty():
			return ""
	ids.sort()
	for i: int in range(1, ids.size()):
		if ids[i] == ids[i - 1]:
			return ""
	var firma: String = str(ids.size())
	for sid: String in ids:
		firma += ":" + sid
	return firma


func _recolectar_switches_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	for hijo: Node in nodo.get_children():
		if hijo is BaseTurnout:
			var sw: BaseTurnout = hijo as BaseTurnout
			for nid: int in sw.obtener_ids_uniones():
				if nid == 0:
					continue
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
	_recortes_extra.clear()
	_recortes_internos_switch.clear()
	_conflictos_adaptacion_switch.clear()
	_conexiones_switch_segmento.clear()
	_segmentos_reemplazados_por_switch.clear()
	_enclavamientos_crossover.clear()
	_switches_editados_manualmente.clear()
	# Limpiar significa descartar también las restauraciones de switches para
	# que una generación posterior parta de una red de aparatos nueva.
	_ediciones_guardadas.erase("_switches")
	_switches_eliminados_persistentes.clear()
	_sincronizar_lista_eliminados_en_ediciones()
	_escribir_archivo_ediciones()
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")


## Genera switches exclusivamente adaptados sobre los tramos Path3D que existen en la escena.
func generar_switches_desde_paths_existentes() -> void:
	recolectar_paths_desde_arbol()
	recolectar_switches_desde_arbol()
	_asegurar_topologia_cargada()
	# Primero se descarta la unión temporal de la pasada anterior: puede haber
	# restaurado posiciones históricas en su junction de origen.
	_limpiar_uniones_manuales_detectadas()
	_actualizar_posiciones_junctions_desde_paths()
	_detectar_uniones_manuales_entre_paths()
	var preservar: Dictionary = _obtener_switches_a_conservar_al_regenerar()

	_generar_aparatos_de_via(preservar)
	# Se reponen las poses/estados guardados sólo de los aparatos que conservaron
	# su tipo (si cambió, la pose vieja no tiene sentido).
	_aplicar_switches_guardados(preservar)
	_aplicar_bajas_switches_persistentes()
	_reconstruir_conexiones_adaptativas()
	habilitar_edicion_en_arbol()
	_persistir_diccionario_switches()
	_escribir_archivo_ediciones()

	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")

	print("TrackNetwork: Generados %d switches a partir de los %d tramos existentes." % [aparatos_de_via.size(), paths.size()])


## El JSON conserva la topología, pero el usuario puede mover los extremos de
## sus Path3D en el editor. Antes de generar, cada junction toma el centro de
## sus extremos actuales para que ningún aparato nazca en su posición histórica.
func _actualizar_posiciones_junctions_desde_paths() -> void:
	for clave: Variant in junctions.keys():
		var junction: Dictionary = junctions[clave] as Dictionary
		var suma: Vector3 = Vector3.ZERO
		var cantidad: int = 0
		for conexion_raw: Variant in junction.get("segments", []):
			if not (conexion_raw is Dictionary):
				continue
			var conexion: Dictionary = conexion_raw as Dictionary
			var sid: String = str(conexion.get("segment_id", ""))
			var via: Path3D = paths.get(sid) as Path3D
			if via == null or via.curve == null or via.curve.point_count < 2:
				continue
			var extremo: String = str(conexion.get("end", "start"))
			var indice: int = 0 if extremo == "start" else via.curve.point_count - 1
			suma += to_local(via.to_global(via.curve.get_point_position(indice)))
			cantidad += 1
		if cantidad <= 0:
			continue
		var centro: Vector3 = suma / float(cantidad)
		junction["position"] = {"x": centro.x, "y": centro.y, "z": centro.z}
		junctions[clave] = junction


## Recopila una vez cada instancia modificada. Los aparatos sin la marca se
## pueden regenerar para incorporar Path3D nuevos; los editados se mantienen.
func _obtener_switches_a_conservar_al_regenerar() -> Dictionary:
	var preservar: Dictionary = {}
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw == null or preservar.has(sw.get_instance_id()):
			continue
		if sw.get_tipo_aparato() in ["TIPO_D", "TIPO_E"]:
			continue
		if _huellas_switches.has(sw.node_id) and int(_huellas_switches[sw.node_id]) != _huella_switch(sw):
			sw.marcar_editado_para_regeneracion()
		if _huellas_config_switches.has(sw.node_id) and int(_huellas_config_switches[sw.node_id]) != _huella_config_switch(sw):
			sw.marcar_editado_para_regeneracion()
		if sw.conservar_al_regenerar or _switches_editados_manualmente.has(sw.get_instance_id()):
			preservar[sw.get_instance_id()] = sw
	return preservar


## Retira únicamente las instancias sin edición para que la detección vuelva a
## crearlas con la topología actual. Los nodos contenedores se conservan porque
## pueden alojar aparatos editados en otros sectores.
func _eliminar_switches_no_preservados(preservar: Dictionary) -> void:
	var a_eliminar: Array[BaseTurnout] = []
	for sw_raw: Variant in aparatos_de_via.values():
		var sw: BaseTurnout = sw_raw as BaseTurnout
		if sw != null and not preservar.has(sw.get_instance_id()) and not a_eliminar.has(sw):
			a_eliminar.append(sw)
	for sw: BaseTurnout in a_eliminar:
		_quitar_aparato_del_registro(sw)


## Construye o amplía junctions temporales desde los extremos cercanos de los
## Path3D. Una vía nueva puede terminar junto a una unión ya existente: en ese
## caso se agrega como tercera rama de esa unión y se genera su switch.
func _detectar_uniones_manuales_entre_paths() -> void:
	_limpiar_uniones_manuales_detectadas()
	if paths.size() < 3:
		return
	var extremos: Array[Dictionary] = []
	for sid: String in paths.keys():
		var via: Path3D = paths[sid] as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		for extremo in ["start", "end"]:
			var indice: int = 0 if extremo == "start" else via.curve.point_count - 1
			extremos.append({
				"segment_id": sid,
				"end": extremo,
				"posicion": via.to_global(via.curve.get_point_position(indice))
			})
	var grupos: Array[Array] = _agrupar_extremos_cercanos(extremos)
	var siguiente_id: int = 2100000000
	for grupo_raw: Array in grupos:
		var grupo: Array[Dictionary] = []
		var ids_vistos: Dictionary = {}
		for conexion_raw: Variant in grupo_raw:
			var conexion: Dictionary = conexion_raw as Dictionary
			var sid: String = str(conexion["segment_id"])
			if ids_vistos.has(sid):
				continue
			ids_vistos[sid] = true
			grupo.append(conexion)
		# Un switch necesita al menos tres ramas. No se reasignan pares aislados:
		# podrían ser los dos extremos de una vía y cortar una junction existente.
		if grupo.size() < 3:
			continue

		var claves_grupo: Dictionary = {}
		for conexion: Dictionary in grupo:
			claves_grupo["%s|%s" % [str(conexion["segment_id"]), str(conexion["end"])]] = true

		var junctions_existentes: Dictionary = {}
		for conexion: Dictionary in grupo:
			var jid_existente: int = _obtener_junction_de_extremo(str(conexion["segment_id"]), str(conexion["end"]))
			if jid_existente != 0:
				junctions_existentes[jid_existente] = true
		var id_union: int = 0
		var reutilizar_junction: bool = false
		if junctions_existentes.size() == 1:
			var posible_id: int = int(junctions_existentes.keys()[0])
			var conexiones_existentes: Array = (junctions.get(str(posible_id), {}) as Dictionary).get("segments", []) as Array
			var claves_existentes: Dictionary = {}
			for existente_raw: Variant in conexiones_existentes:
				if existente_raw is Dictionary:
					var existente: Dictionary = existente_raw as Dictionary
					claves_existentes["%s|%s" % [str(existente.get("segment_id", "")), str(existente.get("end", ""))]] = true
			if claves_existentes.size() == claves_grupo.size():
				reutilizar_junction = true
				for clave_grupo: String in claves_grupo.keys():
					if not claves_existentes.has(clave_grupo):
						reutilizar_junction = false
						break

		if reutilizar_junction:
			id_union = int(junctions_existentes.keys()[0])
			var clave_reutilizada: String = str(id_union)
			if not _junctions_previas_uniones_manuales.has(clave_reutilizada):
				_junctions_previas_uniones_manuales[clave_reutilizada] = (junctions[clave_reutilizada] as Dictionary).duplicate(true)
		else:
			while junctions.has(str(siguiente_id)):
				siguiente_id -= 1
			id_union = siguiente_id
			siguiente_id -= 1
			# Unir extremos de junctions viejos no debe arrastrar sus otras ramas:
			# se retiran sólo los extremos que el usuario acercó y se conserva el
			# resto de cada junction original para que se regenere por separado.
			for jid_raw: Variant in junctions_existentes.keys():
				var jid: int = int(jid_raw)
				var clave_jid: String = str(jid)
				var junction_previa: Dictionary = junctions[clave_jid] as Dictionary
				if not _junctions_previas_uniones_manuales.has(clave_jid):
					_junctions_previas_uniones_manuales[clave_jid] = junction_previa.duplicate(true)
				var restantes: Array[Dictionary] = []
				for existente_raw: Variant in junction_previa.get("segments", []):
					if not (existente_raw is Dictionary):
						continue
					var existente: Dictionary = existente_raw as Dictionary
					var clave_existente: String = "%s|%s" % [str(existente.get("segment_id", "")), str(existente.get("end", ""))]
					if not claves_grupo.has(clave_existente):
						restantes.append(existente.duplicate(true))
				junction_previa["segments"] = restantes
				junctions[clave_jid] = junction_previa

		var promedio: Vector3 = Vector3.ZERO
		for conexion: Dictionary in grupo:
			promedio += conexion["posicion"] as Vector3
		promedio /= float(grupo.size())
		junctions[str(id_union)] = {
			"id": id_union,
			"position": {"x": to_local(promedio).x, "y": to_local(promedio).y, "z": to_local(promedio).z},
			"segments": grupo,
			"_editor_detectada": true
		}
		for conexion: Dictionary in grupo:
			_asignar_extremo_a_union_temporal(str(conexion["segment_id"]), str(conexion["end"]), id_union)


## Agrupa extremos por conectividad espacial, no sólo por su distancia al primer
## extremo. Así tres extremos encadenados dentro de la tolerancia siguen siendo
## una sola unión aunque el primero y el último estén más alejados entre sí.
func _agrupar_extremos_cercanos(extremos: Array[Dictionary]) -> Array[Array]:
	var usados: Dictionary = {}
	var grupos: Array[Array] = []
	for i in extremos.size():
		if usados.has(i):
			continue
		var pendientes: Array[int] = [i]
		var grupo: Array = []
		usados[i] = true
		while not pendientes.is_empty():
			var actual: int = pendientes.pop_front()
			grupo.append(extremos[actual])
			var pos_actual: Vector3 = extremos[actual]["posicion"] as Vector3
			for j in extremos.size():
				if usados.has(j):
					continue
				if pos_actual.distance_to(extremos[j]["posicion"] as Vector3) <= tolerancia_union_manual:
					usados[j] = true
					pendientes.append(j)
		grupos.append(grupo)
	return grupos


func _asignar_extremo_a_union_temporal(sid: String, extremo: String, id_union: int) -> void:
	if not _datos_segmentos_previos_uniones_manuales.has(sid):
		_datos_segmentos_previos_uniones_manuales[sid] = segments_data.get(sid, null)
	var datos: Dictionary = (segments_data.get(sid, {"id": sid}) as Dictionary).duplicate(true)
	if extremo == "start":
		datos["node_start"] = id_union
	else:
		datos["node_end"] = id_union
	segments_data[sid] = datos


func _limpiar_uniones_manuales_detectadas() -> void:
	for clave: Variant in junctions.keys():
		var juncion: Dictionary = junctions[clave] as Dictionary
		if bool(juncion.get("_editor_detectada", false)):
			junctions.erase(clave)
	for sid: String in _datos_segmentos_previos_uniones_manuales.keys():
		var previo: Variant = _datos_segmentos_previos_uniones_manuales[sid]
		if previo == null:
			segments_data.erase(sid)
		else:
			segments_data[sid] = (previo as Dictionary).duplicate(true)
	_datos_segmentos_previos_uniones_manuales.clear()
	for clave: String in _junctions_previas_uniones_manuales.keys():
		junctions[clave] = (_junctions_previas_uniones_manuales[clave] as Dictionary).duplicate(true)
	_junctions_previas_uniones_manuales.clear()


func _extremo_tiene_union_topologica(seg_id: String, extremo: String) -> bool:
	return _obtener_junction_de_extremo(seg_id, extremo) != 0


func _obtener_junction_de_extremo(seg_id: String, extremo: String) -> int:
	for clave: Variant in junctions.keys():
		var juncion: Dictionary = junctions[clave] as Dictionary
		for conexion_raw: Variant in juncion.get("segments", []):
			if conexion_raw is Dictionary:
				var conexion: Dictionary = conexion_raw as Dictionary
				if str(conexion.get("segment_id", "")) == seg_id and str(conexion.get("end", "")) == extremo:
					return int(clave)
	return 0


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
## Devuelve la curva completa y vigente de un tramo. El recorte de un switch no
## modifica nunca este recurso: sólo limita el rango que TrackGeometry dibuja.
##
## No se debe usar `curva_original` aquí. Esa curva es la referencia para los
## botones de edición de EditableTrackSegment y puede quedar atrás de los ajustes
## de extremo aplicados en el Inspector. Si el flexible se ancla allí y la malla
## se extruye desde `p.curve`, ambos extremos quedan separados visualmente.
func _curva_completa_de_path(p: Path3D) -> Curve3D:
	if p == null:
		return null
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
			if not segmento_editable.datos_modificados.is_connected(_on_segmento_datos_modificados):
				segmento_editable.datos_modificados.connect(_on_segmento_datos_modificados)

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
func _generar_aparatos_de_via(preservar: Dictionary = {}) -> void:
	_asegurar_topologia_cargada()
	if preservar.is_empty():
		if _contenedor_switches != null:
			_limpiar_nodo_recursivo(_contenedor_switches)
		aparatos_de_via.clear()
		_switches_ordenados.clear()
	else:
		_eliminar_switches_no_preservados(preservar)
	_recortes_segmentos.clear()
	_enclavamientos_crossover.clear()
	var root_owner: Node = _obtener_root_owner()
	var procesados_set: Dictionary = {}
	var firmas_procesadas: Dictionary = {}
	for sw_raw: Variant in preservar.values():
		var sw_preservado: BaseTurnout = sw_raw as BaseTurnout
		if sw_preservado == null:
			continue
		for nid_preservado: int in sw_preservado.obtener_ids_uniones():
			procesados_set[nid_preservado] = true
		var firma_preservada: String = _firma_vias_switch(sw_preservado)
		if not firma_preservada.is_empty():
			firmas_procesadas[firma_preservada] = true

	# -------------------------------------------------------------------------
	# 1. PRE-ANÁLISIS TOPOLÓGICO: Tijeras (Tipo E) y Crossovers (Tipo D)
	# -------------------------------------------------------------------------
	var scissors_4way_set: Dictionary = {} # 4way_jid (int) -> Array[int] (turnouts vinculados)
	var scissors_turnout_set: Dictionary = {} # turnout_jid (int) -> 4way_jid (int)
	var crossover_pair_map: Dictionary = {} # turnout_jid (int) -> Array [partner_jid (int), diag_sid (String)]

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

	# Los compuestos D/E están deshabilitados por ahora. Sus junctions quedan
	# libres para que las etapas siguientes creen cruces C y desvíos A/B.
	if not GENERAR_SWITCHES_COMPUESTOS_D_E:
		scissors_4way_set.clear()
		crossover_pair_map.clear()

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
		var x1_e: float = - dist_ejes * 0.5
		var x2_e: float = dist_ejes * 0.5
		var z_in_e: float = - largo_crossover_e * 0.5
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
				dir_2d = - dir_2d
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
		to_d.node_id_secundario = j2_int
		to_d.transform = trans_sw
		to_d.distancia_ejes = dist_ejes
		to_d.largo_crossover = largo_crossover_d
		to_d.diagonal_invertida = es_diagonal_inv
		to_d.tipo_aparato_override = "TIPO_D"
		to_d.generar_extremos_flexibles = true
		to_d.construir_geometria()

		# Reajustar bornes fijos a las dimensiones reales del crossover
		var x1_d: float = - dist_ejes * 0.5
		var x2_d: float = dist_ejes * 0.5
		var z_in_d: float = - largo_crossover_d * 0.5
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
		var ids_cruce: Array[String] = []
		for i: int in 4:
			ids_cruce.append(str(datos_conns[i]["segment_id"]))
		var firma_cruce: String = _firma_segmentos_switch(ids_cruce)
		if not firma_cruce.is_empty() and firmas_procesadas.has(firma_cruce):
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
			dir_b_2d = - dir_b_2d
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
			{"conn": c_b_in, "lead": "Extremo_Via_B_Entrada", "fwd_def": - dir_b_loc},
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
		if not firma_cruce.is_empty():
			firmas_procesadas[firma_cruce] = true

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
		var ids_desvio: Array[String] = [stem_id, tr_dir, tr_desv]
		var firma_desvio: String = _firma_segmentos_switch(ids_desvio)
		if not firma_desvio.is_empty() and firmas_procesadas.has(firma_desvio):
			continue

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

		var fwd_stem_2d: Vector2 = - (stem_conn["vector"] as Vector2)
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
		if not firma_desvio.is_empty():
			firmas_procesadas[firma_desvio] = true

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
	for nid: int in sw.obtener_ids_uniones():
		aparatos_de_via[nid] = sw

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
	_recortes_internos_switch.clear()
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
		for nid_propio: int in sw.obtener_ids_uniones():
			if nid_propio != 0 and not ids.has(nid_propio):
				ids.append(nid_propio)
		junctions_por_aparato[instance_id] = ids

	for instance_id: int in aparatos_unicos.keys():
		var sw: BaseTurnout = aparatos_unicos[instance_id] as BaseTurnout
		var jids: Array[int] = []
		for v: Variant in (junctions_por_aparato[instance_id] as Array):
			jids.append(int(v))
		_reconstruir_aparato(sw, jids)

	_conexiones_switch_segmento.erase("_en_proceso")
	# Los recortes de cada Path3D pueden cambiar al alargar un extremo flexible.
	# La malla de vías se calcula aparte, por lo que debe regenerarse después de
	# actualizar los leads para reflejar ese nuevo punto de encuentro.
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("construir_geometria"):
		geo.call_deferred("construir_geometria")
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
	if recalibrar_aparatos_con_via_real and not sw.conservar_al_regenerar:
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

	# Un crossover tipo D tiene cuatro puertos físicos. El selector genérico
	# puede empatar dos puertos paralelos y dejar los otros dos con su longitud
	# automática; se usa su topología de entrada/salida para anclar cada rama a
	# su extremo inequívoco.
	if sw is ProceduralCrossover:
		_reconstruir_extremos_crossover_tipo_d(sw as ProceduralCrossover, junction_ids, junction_set)
		return
	# El cruce diamante tipo C también tiene cuatro puertos físicos. Asignarlos
	# por proximidad deja dos extremos sin rama cuando las dos vías se cruzan,
	# por lo que se resuelven de forma explícita como en el tipo D.
	if sw is ProceduralCrossing:
		_reconstruir_extremos_cruce_tipo_c(sw as ProceduralCrossing, junction_ids, junction_set)
		return

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
			if lead == null:
				_registrar_recorte_segmento(sid, end_tipo, distancia_corte)
				continue
			leads_usados[lead.get_instance_id()] = true
			# El recorte de la malla debe llegar exactamente al extremo exterior
			# del flexible. La conexión puede ajustar la distancia para que la
			# transición sea válida; usar el valor anterior dejaba vía plena debajo
			# del flexible y ambos modelos se superponían.
			var distancia_final: float = _conectar_lead_a_segmento(sw, lead, p_seg, sid, end_tipo, jid, distancia_corte)
			_registrar_recorte_segmento(sid, end_tipo, distancia_final)


## Reancla los cuatro extremos de un crossover en H sin depender de una
## comparación de distancias entre puertos paralelos. Cada unión aporta la vía
## izquierda/derecha y su sentido; con eso se obtiene un único lead de entrada
## o salida de Vía 1/Vía 2.
func _reconstruir_extremos_crossover_tipo_d(sw: ProceduralCrossover, junction_ids: Array[int], junction_set: Dictionary) -> void:
	if sw == null:
		return
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return
	# Cada unión tiene dos ramas exteriores: una hacia -Z y otra hacia +Z.
	# La posición transversal de la unión identifica la vía. Esta topología
	# prevalece sobre la proximidad al borne, ya que los aparatos conservados
	# pueden tener una separación lateral mayor que su distancia_ejes nominal.
	var candidatos: Array[Dictionary] = _candidatos_crossover_tipo_d(sw, junction_ids, junction_set)
	var parejas: Array[Dictionary] = []
	for hijo: Node in g_ext.get_children():
		if not (hijo is FlexibleTrackLead):
			continue
		var lead: FlexibleTrackLead = hijo as FlexibleTrackLead
		var borne: Vector3 = lead.global_transform * lead.punto_inicio
		var direccion: Vector3 = (lead.global_transform.basis * lead.direccion_inicio).normalized()
		for candidato: Dictionary in candidatos:
			var pos: Vector3 = candidato["pos"] as Vector3
			var salida: Vector3 = candidato["salida"] as Vector3
			var alineacion: float = direccion.dot(salida)
			var lateral: float = (pos - borne).cross(direccion).length()
			var avance: float = (pos - borne).dot(direccion)
			var topologica: bool = bool(candidato["topologica"])
			if topologica:
				var local: Vector3 = sw.to_local(pos) - sw.posicion_centro
				var salida_local: Vector3 = sw.global_transform.basis.inverse() * salida
				var via_1: bool = local.x < 0.0
				var entrada: bool = salida_local.z < 0.0
				var nombre_puerto: String = "Extremo_Via_%d_%s" % [1 if via_1 else 2, "Entrada" if entrada else "Salida"]
				if String(lead.name) != nombre_puerto:
					continue
			else:
				# Sólo las conexiones de rescate dependen de tolerancias espaciales.
				if alineacion < 0.35 or lateral > maxf(3.0, sw.distancia_ejes * 0.65):
					continue
				if avance < -sw.largo_crossover * 0.75:
					continue
			var puntaje: float = lateral * 12.0 + absf(avance) * 0.08 + (1.0 - alineacion) * 35.0
			parejas.append({"lead": lead, "candidato": candidato, "puntaje": puntaje, "topologica": topologica})
	parejas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["topologica"]) != bool(b["topologica"]):
			return bool(a["topologica"])
		return float(a["puntaje"]) < float(b["puntaje"]))
	var leads_usados: Dictionary = {}
	var conexiones_usadas: Dictionary = {}
	for pareja: Dictionary in parejas:
		var lead: FlexibleTrackLead = pareja["lead"] as FlexibleTrackLead
		var candidato: Dictionary = pareja["candidato"] as Dictionary
		var clave: String = str(candidato["clave"])
		if leads_usados.has(lead.get_instance_id()) or conexiones_usadas.has(clave):
			continue
		var sid: String = str(candidato["sid"])
		var extremo: String = str(candidato["extremo"])
		var continuidad: Dictionary = _resolver_continuacion_crossover_d(sw, lead, sid, extremo)
		if continuidad.is_empty():
			continue
		for sid_absorbido_raw: Variant in continuidad["absorbidos"]:
			var sid_absorbido: String = str(sid_absorbido_raw)
			_segmentos_reemplazados_por_switch[sid_absorbido] = true
			_recortes_segmentos[sid_absorbido] = Vector2.ZERO
			_recortes_extra.erase(sid_absorbido)
		sid = str(continuidad["sid"])
		extremo = str(continuidad["extremo"])
		var via: Path3D = paths.get(sid) as Path3D
		if via == null:
			continue
		if lead.respetar_edicion_manual:
			_registrar_recorte_en_extremo_manual(lead, via, sid, extremo)
		else:
			var distancia: float = _calcular_distancia_adaptativa(via, extremo, lead)
			var distancia_final: float = _conectar_lead_a_segmento(sw, lead, via, sid, extremo, int(candidato["jid"]), distancia)
			_registrar_recorte_segmento(sid, extremo, distancia_final)
		leads_usados[lead.get_instance_id()] = true
		conexiones_usadas[clave] = true
		conexiones_usadas["%s:%s" % [sid, extremo]] = true
	_recortar_vias_bajo_crossover_d(sw)


## Incluye las conexiones topológicas y los extremos de vía próximos al cuerpo.
## Estos últimos recuperan aparatos D antiguos cuya segunda unión no quedó en
## el JSON, sin buscar una vía distante en cualquier punto del mapa.
func _candidatos_crossover_tipo_d(sw: ProceduralCrossover, junction_ids: Array[int], junction_set: Dictionary) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	var claves_topologicas: Dictionary = {}
	for jid: int in junction_ids:
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if c_raw is Dictionary:
				var c: Dictionary = c_raw as Dictionary
				claves_topologicas["%s:%s" % [str(c.get("segment_id", "")), str(c.get("end", ""))]] = jid
	var inv_sw: Transform3D = sw.global_transform.affine_inverse()
	for sid: String in paths.keys():
		if _segmento_interno_de_aparato(sid, junction_set):
			continue
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		for extremo: String in ["start", "end"]:
			var clave: String = "%s:%s" % [sid, extremo]
			var pos: Vector3 = _obtener_posicion_extremo_segmento_global(via, extremo)
			var local: Vector3 = inv_sw * pos
			var topologica: bool = claves_topologicas.has(clave)
			if not topologica and (absf(local.x - sw.posicion_centro.x) > sw.distancia_ejes + 4.0 or absf(local.z - sw.posicion_centro.z) > sw.largo_crossover * 0.75 + 20.0):
				continue
			resultado.append({
				"clave": clave, "sid": sid, "extremo": extremo, "pos": pos,
				"salida": _direccion_real_segmento_extremo(sid, extremo),
				"jid": int(claves_topologicas.get(clave, sw.node_id)),
				"topologica": topologica
			})
	return resultado


func _crossover_d_cerca_de_segmentos(sw: ProceduralCrossover, seg_ids: Array[String]) -> bool:
	var inv_sw: Transform3D = sw.global_transform.affine_inverse()
	for sid: String in seg_ids:
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		for extremo: String in ["start", "end"]:
			var local: Vector3 = inv_sw * _obtener_posicion_extremo_segmento_global(via, extremo)
			if absf(local.x - sw.posicion_centro.x) <= sw.distancia_ejes + 4.0 and absf(local.z - sw.posicion_centro.z) <= sw.largo_crossover * 0.75 + 20.0:
				return true
	return false


## Sigue una vía corta a través de uniones continuas hasta hallar un Path3D
## cuyo punto de recorte quede realmente delante del borne. El flexible ocupa
## los tramos intermedios completos; dejarlos dibujados producía el solapamiento
## de dos de los cuatro puertos D.
func _resolver_continuacion_crossover_d(sw: ProceduralCrossover, lead: FlexibleTrackLead, sid_inicial: String, extremo_inicial: String) -> Dictionary:
	var sid: String = sid_inicial
	var extremo: String = extremo_inicial
	var absorbidos: Array[String] = []
	var visitados: Dictionary = {}
	var dir_lead: Vector3 = (lead.global_transform.basis * lead.direccion_inicio).normalized()
	for _paso: int in 8:
		if visitados.has(sid):
			break
		visitados[sid] = true
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			break
		var distancia: float = _calcular_distancia_adaptativa(via, extremo, lead)
		var distancia_final: float = _ajustar_distancia_para_transicion_valida(lead, via, extremo, distancia)
		var punto: Dictionary = _obtener_punto_recorte_segmento(via, extremo, distancia_final)
		if _avance_local_de_punto(lead, punto["pos"] as Vector3) >= LONGITUD_MINIMA_TRANSICION:
			return {"sid": sid, "extremo": extremo, "absorbidos": absorbidos}
		var datos: Dictionary = segments_data.get(sid, {}) as Dictionary
		var jid_siguiente: int = int(datos.get("node_end", 0)) if extremo == "start" else int(datos.get("node_start", 0))
		if jid_siguiente == 0:
			break
		var extremo_opuesto: String = _extremo_opuesto(extremo)
		var pos_union: Vector3 = _obtener_posicion_extremo_segmento_global(via, extremo_opuesto)
		var dir_continuidad: Vector3 = -_direccion_real_segmento_extremo(sid, extremo_opuesto)
		var mejor_sid: String = ""
		var mejor_extremo: String = ""
		var mejor_puntaje: float = -INF
		var j_dict: Dictionary = junctions.get(str(jid_siguiente), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if not (c_raw is Dictionary):
				continue
			var c: Dictionary = c_raw as Dictionary
			var sid_vecino: String = str(c.get("segment_id", ""))
			var extremo_vecino: String = str(c.get("end", "start"))
			if sid_vecino == sid or visitados.has(sid_vecino):
				continue
			var via_vecina: Path3D = paths.get(sid_vecino) as Path3D
			if via_vecina == null or via_vecina.curve == null or via_vecina.curve.point_count < 2:
				continue
			var pos_vecina: Vector3 = _obtener_posicion_extremo_segmento_global(via_vecina, extremo_vecino)
			if pos_vecina.distance_to(pos_union) > 5.0:
				continue
			var salida: Vector3 = _direccion_real_segmento_extremo(sid_vecino, extremo_vecino)
			var continuidad: float = dir_continuidad.dot(salida)
			var alineacion: float = dir_lead.dot(salida)
			if continuidad < 0.5 or alineacion < 0.35:
				continue
			var puntaje: float = continuidad + alineacion - pos_vecina.distance_to(pos_union) * 0.1
			if puntaje > mejor_puntaje:
				mejor_puntaje = puntaje
				mejor_sid = sid_vecino
				mejor_extremo = extremo_vecino
		if mejor_sid.is_empty():
			break
		absorbidos.append(sid)
		sid = mejor_sid
		extremo = mejor_extremo
	return {}


## El recorte por extremo no cubre un Path3D que cruza el cuerpo del D sin
## terminar en sus junctions. Se excluye sólo el intervalo interior y se dejan
## visibles las secciones de vía a ambos lados.
func _recortar_vias_bajo_crossover_d(sw: ProceduralCrossover) -> void:
	var vias_de_puertos: Dictionary = _vias_de_puertos_crossover_d(sw)
	for sid: String in paths.keys():
		if vias_de_puertos.has(sid) or _segmentos_reemplazados_por_switch.has(sid):
			continue
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		_registrar_recorte_interno_switch(sid, _intervalo_via_bajo_crossover_d(sw, via))


## Las vías que llegan a un puerto ya se recortan en el punto exacto donde
## termina su flexible. El hueco geométrico interior sólo corresponde a vías
## continuas sin puerto en este D.
func _vias_de_puertos_crossover_d(sw: ProceduralCrossover) -> Dictionary:
	var resultado: Dictionary = {}
	for jid: int in _junctions_de_aparato(sw):
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if c_raw is Dictionary:
				resultado[str((c_raw as Dictionary).get("segment_id", ""))] = true
	for registro_raw: Variant in _conexiones_switch_segmento.values():
		if registro_raw is Dictionary:
			var registro: Dictionary = registro_raw as Dictionary
			if int(registro.get("switch", 0)) == sw.get_instance_id():
				resultado[str(registro.get("segment_id", ""))] = true
	return resultado


func _registrar_recorte_interno_switch(sid: String, intervalo: Vector2) -> void:
	if intervalo.y - intervalo.x < 0.2:
		return
	var intervalos: Array[Vector2] = []
	for previo: Variant in _recortes_internos_switch.get(sid, []):
		intervalos.append(previo as Vector2)
	intervalos.append(intervalo)
	_recortes_internos_switch[sid] = intervalos


func _intervalo_via_bajo_crossover_d(sw: ProceduralCrossover, via: Path3D) -> Vector2:
	var curva: Curve3D = via.curve
	var largo: float = curva.get_baked_length()
	if largo < 0.2 or not _via_puede_cruzar_crossover_d(sw, via):
		return Vector2.ZERO
	var centro_mundo: Vector3 = sw.global_transform * sw.posicion_centro
	var medio: float = curva.get_closest_offset(via.to_local(centro_mundo))
	if not _punto_via_dentro_crossover_d(sw, via, medio):
		return Vector2.ZERO
	var inicio: float = medio
	while inicio > 0.0:
		var anterior: float = maxf(0.0, inicio - 1.0)
		if not _punto_via_dentro_crossover_d(sw, via, anterior):
			var fuera: float = anterior
			var dentro: float = inicio
			for _i: int in 7:
				var mitad: float = (fuera + dentro) * 0.5
				if _punto_via_dentro_crossover_d(sw, via, mitad):
					dentro = mitad
				else:
					fuera = mitad
			inicio = minf(largo, dentro + SOLAPE_VISUAL_UNION_SWITCH)
			break
		inicio = anterior
	var fin: float = medio
	while fin < largo:
		var siguiente: float = minf(largo, fin + 1.0)
		if not _punto_via_dentro_crossover_d(sw, via, siguiente):
			var dentro_fin: float = fin
			var fuera_fin: float = siguiente
			for _j: int in 7:
				var mitad_fin: float = (dentro_fin + fuera_fin) * 0.5
				if _punto_via_dentro_crossover_d(sw, via, mitad_fin):
					dentro_fin = mitad_fin
				else:
					fuera_fin = mitad_fin
			fin = maxf(0.0, dentro_fin - SOLAPE_VISUAL_UNION_SWITCH)
			break
		fin = siguiente
	return Vector2(inicio, fin)


## El Bézier queda contenido en la caja de sus anclas y manijas. Este filtro
## evita buscar offsets a lo largo de cientos de vías lejanas en cada edición.
func _via_puede_cruzar_crossover_d(sw: ProceduralCrossover, via: Path3D) -> bool:
	var xmin: float = INF
	var xmax: float = -INF
	var zmin: float = INF
	var zmax: float = -INF
	var curva: Curve3D = via.curve
	for i: int in curva.point_count:
		var ancla: Vector3 = curva.get_point_position(i)
		for control: Vector3 in [ancla, ancla + curva.get_point_in(i), ancla + curva.get_point_out(i)]:
			var local: Vector3 = sw.to_local(via.to_global(control)) - sw.posicion_centro
			xmin = minf(xmin, local.x)
			xmax = maxf(xmax, local.x)
			zmin = minf(zmin, local.z)
			zmax = maxf(zmax, local.z)
	var limite_x: float = sw.distancia_ejes * 0.5 + 1.8
	var limite_z: float = sw.largo_crossover * 0.5 + 0.25
	return xmin <= limite_x and xmax >= -limite_x and zmin <= limite_z and zmax >= -limite_z


func _punto_via_dentro_crossover_d(sw: ProceduralCrossover, via: Path3D, distancia: float) -> bool:
	var mundo: Vector3 = via.to_global(via.curve.sample_baked(distancia, true))
	var local: Vector3 = sw.to_local(mundo) - sw.posicion_centro
	return absf(local.x) <= sw.distancia_ejes * 0.5 + 1.8 and absf(local.z) <= sw.largo_crossover * 0.5 + 0.25


## Reancla los cuatro puertos de un cruce diamante. La vía se determina por
## el eje local más alineado (A o B), y el signo define su entrada o salida.
## Así la expansión llega a los cuatro extremos, incluso luego de recargar.
func _reconstruir_extremos_cruce_tipo_c(sw: ProceduralCrossing, junction_ids: Array[int], junction_set: Dictionary) -> void:
	if sw == null:
		return
	sw._asegurar_geometria()
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return
	var fwd_a: Vector3 = sw._obtener_fwd_a()
	var fwd_b: Vector3 = sw._obtener_fwd_b()
	if fwd_a.dot(fwd_b) < 0.0:
		fwd_b = -fwd_b
	var leads_conectados: Dictionary = {}
	var conexiones_usadas: Dictionary = {}
	for jid: int in junction_ids:
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if not (c_raw is Dictionary):
				continue
			var conexion: Dictionary = c_raw as Dictionary
			var sid: String = str(conexion.get("segment_id", ""))
			if sid.is_empty() or not paths.has(sid) or _segmento_interno_de_aparato(sid, junction_set):
				continue
			var extremo: String = str(conexion.get("end", "start"))
			var via: Path3D = paths.get(sid) as Path3D
			if via == null or via.curve == null:
				continue
			var salida_mundo: Vector3 = _obtener_vector_salida_global(via, extremo)
			var salida_local: Vector3 = (sw.global_transform.basis.inverse() * salida_mundo).normalized()
			var dot_a: float = salida_local.dot(fwd_a)
			var dot_b: float = salida_local.dot(fwd_b)
			var usa_via_a: bool = absf(dot_a) >= absf(dot_b)
			var es_entrada: bool = (dot_a if usa_via_a else dot_b) < 0.0
			var nombre_lead: String = ""
			if usa_via_a:
				nombre_lead = "Extremo_Via_A_Entrada" if es_entrada else "Extremo_Via_A_Salida"
			else:
				nombre_lead = "Extremo_Via_B_Entrada" if es_entrada else "Extremo_Via_B_Salida"
			var lead: FlexibleTrackLead = g_ext.get_node_or_null(nombre_lead) as FlexibleTrackLead
			if lead == null or leads_conectados.has(lead.get_instance_id()):
				continue
			if lead.respetar_edicion_manual:
				_registrar_recorte_en_extremo_manual(lead, via, sid, extremo)
			else:
				var distancia: float = _calcular_distancia_adaptativa(via, extremo, lead)
				var distancia_final: float = _conectar_lead_a_segmento(sw, lead, via, sid, extremo, jid, distancia)
				_registrar_recorte_segmento(sid, extremo, distancia_final)
			leads_conectados[lead.get_instance_id()] = true
			conexiones_usadas["%s:%s" % [sid, extremo]] = true

	# Escenas anteriores pueden contener topología incompleta; los extremos que
	# falten usan el mismo respaldo geométrico que los aparatos compuestos.
	for hijo: Node in g_ext.get_children():
		if hijo is FlexibleTrackLead:
			var lead_sin_rama: FlexibleTrackLead = hijo as FlexibleTrackLead
			if not leads_conectados.has(lead_sin_rama.get_instance_id()):
				_reanclar_lead_compuesto_por_geometria(sw, lead_sin_rama, junction_set, conexiones_usadas)


## Fallback para puertos históricos sin conexión topológica completa.
func _reanclar_lead_compuesto_por_geometria(sw: BaseTurnout, lead: FlexibleTrackLead, junction_set: Dictionary, conexiones_usadas: Dictionary) -> void:
	if sw == null or lead == null:
		return
	var punto_contacto: Vector3 = lead.global_transform * lead.obtener_posicion_extremo_exterior()
	var dir_lead: Vector3 = (lead.global_transform.basis * lead.direccion_inicio).normalized()
	var mejor_sid: String = ""
	var mejor_extremo: String = ""
	var mejor_puntaje: float = INF
	for sid: String in paths.keys():
		if _segmento_interno_de_aparato(sid, junction_set):
			continue
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		var largo: float = via.curve.get_baked_length()
		if largo < MARGEN_FINAL_SEGMENTO_SWITCH:
			continue
		var offset: float = via.curve.get_closest_offset(via.to_local(punto_contacto))
		var p_via: Vector3 = via.to_global(via.curve.sample_baked(offset, true))
		for extremo: String in ["start", "end"]:
			var clave: String = "%s:%s" % [sid, extremo]
			if conexiones_usadas.has(clave):
				continue
			var dir_via: Vector3 = _direccion_real_segmento_extremo(sid, extremo)
			var alineacion: float = dir_lead.dot(dir_via)
			if alineacion <= 0.05:
				continue
			var distancia_extremo: float = offset if extremo == "start" else largo - offset
			var puntaje: float = punto_contacto.distance_to(p_via) + distancia_extremo * 0.04 + (1.0 - alineacion) * 8.0
			if puntaje < mejor_puntaje:
				mejor_puntaje = puntaje
				mejor_sid = sid
				mejor_extremo = extremo
	if mejor_sid.is_empty():
		return
	var via_elegida: Path3D = paths.get(mejor_sid) as Path3D
	if via_elegida == null:
		return
	if lead.respetar_edicion_manual:
		_registrar_recorte_en_extremo_manual(lead, via_elegida, mejor_sid, mejor_extremo)
	else:
		var distancia: float = _calcular_distancia_adaptativa(via_elegida, mejor_extremo, lead)
		var distancia_final: float = _conectar_lead_a_segmento(sw, lead, via_elegida, mejor_sid, mejor_extremo, sw.node_id, distancia)
		_registrar_recorte_segmento(mejor_sid, mejor_extremo, distancia_final)
	conexiones_usadas["%s:%s" % [mejor_sid, mejor_extremo]] = true


## Devuelve todos los node_id que apuntan a la MISMA instancia de aparato.
## Los aparatos compuestos (tijeras, escapes) registran varios node_id.
func _junctions_de_aparato(sw: BaseTurnout) -> Array[int]:
	var ids: Array[int] = []
	if sw == null:
		return ids
	# La fuente de verdad es el aparato: un crossover D representa dos uniones
	# incluso durante el frame de carga en que su segundo ID todavía no figura
	# en el diccionario temporal de la red.
	for nid_propio: int in sw.obtener_ids_uniones():
		if nid_propio != 0 and not ids.has(nid_propio):
			ids.append(nid_propio)
	for nid: int in aparatos_de_via.keys():
		if aparatos_de_via[nid] == sw and not ids.has(nid):
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
		elif sw is ProceduralCrossover and _crossover_d_cerca_de_segmentos(sw as ProceduralCrossover, seg_ids):
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
		_recortes_internos_switch.erase(s)
		_conflictos_adaptacion_switch.erase(s)
		_segmentos_reemplazados_por_switch.erase(s)
		_borrar_conexiones_de_segmento(s)

	# 6. Reconstruir solo los aparatos afectados.
	for sw: BaseTurnout in aparatos_afectados:
		_reconstruir_aparato(sw, _junctions_de_aparato(sw))
	# Un mismo Path3D puede atravesar dos D. Al limpiar sus recortes para la
	# actualización local, se recuperan también los del D que no cambió.
	var d_recuperados: Dictionary = {}
	for sw_raw: Variant in aparatos_de_via.values():
		var sw_d: ProceduralCrossover = sw_raw as ProceduralCrossover
		if sw_d == null or aparatos_afectados.has(sw_d) or d_recuperados.has(sw_d.get_instance_id()):
			continue
		d_recuperados[sw_d.get_instance_id()] = true
		var vias_de_puertos: Dictionary = _vias_de_puertos_crossover_d(sw_d)
		for sid: String in segs_afectados.keys():
			if vias_de_puertos.has(sid) or _segmentos_reemplazados_por_switch.has(sid):
				continue
			var via: Path3D = paths.get(sid) as Path3D
			if via != null and via.curve != null:
				_registrar_recorte_interno_switch(sid, _intervalo_via_bajo_crossover_d(sw_d, via))

	_conexiones_switch_segmento.erase("_en_proceso")

	# 7. Remallar los tramos afectados (pocos: el costo es acotado).
	var geo: Node = get_node_or_null("GeometriaVias")
	if geo != null and geo.has_method("actualizar_geometria_tramo"):
		for s: String in segs_afectados.keys():
			geo.call_deferred("actualizar_geometria_tramo", s)


## Actualiza sólo las vías que tocan al switch editado desde el inspector. Se
## usa para expandir sus extremos flexibles sin reconstruir toda la red.
func actualizar_expansion_extremos_switch(sw: BaseTurnout) -> void:
	if sw == null or not is_instance_valid(sw):
		return
	sw.marcar_editado_para_regeneracion()
	_switches_editados_manualmente[sw.get_instance_id()] = true
	var segmentos: Dictionary = {}
	for jid: int in _junctions_de_aparato(sw):
		var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
		for conexion_raw: Variant in j_dict.get("segments", []):
			if conexion_raw is Dictionary:
				var sid: String = str((conexion_raw as Dictionary).get("segment_id", ""))
				if not sid.is_empty() and paths.has(sid):
					segmentos[sid] = true
	if sw is ProceduralCrossover:
		_agregar_ramas_crossover_d_para_actualizar(sw as ProceduralCrossover, segmentos)
	if segmentos.is_empty():
		return
	var ids: Array[String] = []
	for sid: String in segmentos.keys():
		ids.append(sid)
	# Se incluye el aparato pedido explícitamente. Así sus extremos traseros se
	# recalculan aunque el editor esté terminando de registrar el segundo nodo
	# topológico de un crossover tipo D.
	for nid: int in sw.obtener_ids_uniones():
		aparatos_de_via[nid] = sw
	_reconstruir_conexiones_locales(ids)
	_persistir_diccionario_switches()
	_escribir_archivo_ediciones()


## Agrega al conjunto todos los segmentos de las uniones de los aparatos dados.
func _agregar_ramas_de_aparatos(aparatos: Array[BaseTurnout], segs: Dictionary) -> void:
	for sw: BaseTurnout in aparatos:
		if sw is ProceduralCrossover:
			_agregar_ramas_crossover_d_para_actualizar(sw as ProceduralCrossover, segs)
		for jid: int in _junctions_de_aparato(sw):
			var j_dict: Dictionary = junctions.get(str(jid), {}) as Dictionary
			for c_raw: Variant in j_dict.get("segments", []):
				if c_raw is Dictionary:
					var sid: String = str((c_raw as Dictionary).get("segment_id", ""))
					if not sid.is_empty():
						segs[sid] = true


func _agregar_ramas_crossover_d_para_actualizar(sw: ProceduralCrossover, segs: Dictionary) -> void:
	var ids_d: Array[int] = _junctions_de_aparato(sw)
	var conjunto_d: Dictionary = {}
	for jid_d: int in ids_d:
		conjunto_d[jid_d] = true
	for candidato: Dictionary in _candidatos_crossover_tipo_d(sw, ids_d, conjunto_d):
		var sid: String = str(candidato["sid"])
		segs[sid] = true
		var via: Path3D = paths.get(sid) as Path3D
		if via == null or via.curve == null or via.curve.get_baked_length() > sw.largo_crossover + sw.expansion_extremos_flexibles + 20.0:
			continue
		var datos: Dictionary = segments_data.get(sid, {}) as Dictionary
		var jid_siguiente: int = int(datos.get("node_end", 0)) if str(candidato["extremo"]) == "start" else int(datos.get("node_start", 0))
		var j_dict: Dictionary = junctions.get(str(jid_siguiente), {}) as Dictionary
		for c_raw: Variant in j_dict.get("segments", []):
			if c_raw is Dictionary:
				var sid_vecino: String = str((c_raw as Dictionary).get("segment_id", ""))
				if paths.has(sid_vecino):
					segs[sid_vecino] = true
	# También remallar las vías continuas que atraviesan el cuerpo del D sin
	# tener un extremo en sus dos junctions.
	for sid: String in paths.keys():
		if segs.has(sid):
			continue
		var via: Path3D = paths.get(sid) as Path3D
		if via != null and via.curve != null and _intervalo_via_bajo_crossover_d(sw, via).y > 0.0:
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


func _conectar_lead_a_segmento(sw: BaseTurnout, lead: FlexibleTrackLead, path: Path3D, seg_id: String, end_tipo: String, junction_id: int, distancia_forzada: float = -1.0) -> float:
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
		"gap": - 1.0,
		"kink_deg": - 1.0,
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
		var manija: Vector3 = - curva.get_point_in(i_fin)
		if manija.length_squared() > 1e-10:
			registro["kink_deg"] = rad_to_deg(acos(clampf(absf(manija.normalized().dot(dir_local)), 0.0, 1.0)))
	_conexiones_switch_segmento["%s:%s:%d" % [seg_id, end_tipo, junction_id]] = registro
	return distancia

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
## el corte se limita al alcance del flexible. Un crossover D necesita más
## margen cuando sus uniones quedan dentro de su cuerpo nominal: de otro modo
## el punto de recorte nunca llega delante de dos de sus cuatro bornes.
func _ajustar_distancia_para_transicion_valida(lead: FlexibleTrackLead, path: Path3D, end_tipo: String, distancia: float) -> float:
	if lead == null or path == null or path.curve == null:
		return distancia
	var p0: Vector3 = lead.punto_inicio
	var d0: Vector3 = lead.direccion_inicio.normalized()
	if d0.length_squared() < 1e-6:
		return distancia
	var largo: float = path.curve.get_baked_length()
	var maximo: float = maxf(0.0, largo - MARGEN_FINAL_SEGMENTO_SWITCH)
	var alcance_solicitado: float = maxf(
		lead.longitud_extension + MARGEN_MAX_EXTENSION_LEAD,
		lead.expansion_sobre_path + MARGEN_FINAL_SEGMENTO_SWITCH
	)
	var aparato: Node = lead.get_parent().get_parent() if lead.get_parent() != null else null
	if aparato is ProceduralCrossover:
		alcance_solicitado = maxf(alcance_solicitado, lead.longitud_extension * 2.0 + MARGEN_MAX_EXTENSION_LEAD)
	var tope: float = minf(maximo, maxf(MARGEN_FINAL_SEGMENTO_SWITCH, alcance_solicitado))
	# La expansión se mide sobre la vía real y no en línea recta. El flexible
	# conserva así su adaptación automática al Path3D aunque el usuario pida
	# una transición más larga desde el inspector del switch.
	var candidata: float = clampf(maxf(distancia, lead.expansion_sobre_path), 0.0, tope)
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
			resultado.append(_aplicar_solape_visual_recorte(ini, fin, l_total))
		return _restar_recortes_internos_switch(seg_id, resultado)
	var r_legacy: Vector2 = _recortes_segmentos.get(seg_id, Vector2(0.0, l_total)) as Vector2
	if r_legacy == Vector2.ZERO:
		return resultado
	resultado.append(_aplicar_solape_visual_recorte(
		clampf(r_legacy.x, 0.0, l_total),
		clampf(r_legacy.y, 0.0, l_total),
		l_total
	))
	return _restar_recortes_internos_switch(seg_id, resultado)


func _restar_recortes_internos_switch(seg_id: String, rangos: Array[Vector2]) -> Array[Vector2]:
	if not _recortes_internos_switch.has(seg_id):
		return rangos
	for hueco_raw: Variant in _recortes_internos_switch[seg_id]:
		var hueco: Vector2 = hueco_raw as Vector2
		var restantes: Array[Vector2] = []
		for rango: Vector2 in rangos:
			if hueco.y <= rango.x or hueco.x >= rango.y:
				restantes.append(rango)
			else:
				if hueco.x - rango.x >= 0.2:
					restantes.append(Vector2(rango.x, hueco.x))
				if rango.y - hueco.y >= 0.2:
					restantes.append(Vector2(hueco.y, rango.y))
		rangos = restantes
	return rangos


## Extiende sólo el extremo que fue recortado, manteniendo el solape dentro de
## la curva de vía. Así los rieles y el balasto del Path3D se encuentran con los
## del flexible sin modificar la ruta que usan los trenes.
func _aplicar_solape_visual_recorte(ini: float, fin: float, l_total: float) -> Vector2:
	var inicio: float = ini
	var final: float = fin
	if inicio > 0.0:
		inicio = maxf(0.0, inicio - SOLAPE_VISUAL_UNION_SWITCH)
	if final < l_total:
		final = minf(l_total, final + SOLAPE_VISUAL_UNION_SWITCH)
	return Vector2(inicio, final)


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


## Devuelve a qué extremo topológico corresponde un extremo local de la curva.
## Al editar un Path3D en el Inspector se pueden invertir sus puntos sin cambiar
## `node_start`/`node_end` en la red. Se resuelve por cercanía para que el grafo
## siga siendo válido sin deshacer la geometría del diseñador.
func _extremo_topologico_de_local(segment_id: String, extremo_local: String) -> String:
	if not segments_data.has(segment_id):
		return extremo_local
	var path: Path3D = get_segment_path(segment_id)
	if path == null or path.curve == null or path.curve.point_count < 2:
		return extremo_local
	var segmento: Dictionary = segments_data[segment_id] as Dictionary
	var node_start: int = int(segmento.get("node_start", 0))
	var node_end: int = int(segmento.get("node_end", 0))
	var datos_start: Dictionary = junctions.get(str(node_start), {}) as Dictionary
	var datos_end: Dictionary = junctions.get(str(node_end), {}) as Dictionary
	if not datos_start.has("position") or not datos_end.has("position"):
		return extremo_local
	var pos_start: Dictionary = datos_start.get("position", {}) as Dictionary
	var pos_end: Dictionary = datos_end.get("position", {}) as Dictionary
	var punto_local: Vector3 = path.curve.get_point_position(0 if extremo_local == "start" else path.curve.point_count - 1)
	var punto_global: Vector3 = path.to_global(punto_local)
	var topo_start := Vector3(float(pos_start.get("x", 0.0)), float(pos_start.get("y", 0.0)), float(pos_start.get("z", 0.0)))
	var topo_end := Vector3(float(pos_end.get("x", 0.0)), float(pos_end.get("y", 0.0)), float(pos_end.get("z", 0.0)))
	var directo: float = punto_global.distance_to(topo_start if extremo_local == "start" else topo_end)
	var invertido: float = punto_global.distance_to(topo_end if extremo_local == "start" else topo_start)
	if invertido + 0.05 < directo:
		return "end" if extremo_local == "start" else "start"
	return extremo_local


## Dirección local que aleja la formación de un extremo topológico concreto.
func _direccion_local_desde_extremo_topologico(segment_id: String, extremo_topologico: String) -> String:
	return "forward" if _extremo_topologico_de_local(segment_id, "start") == extremo_topologico else "reversed"


## Devuelve las opciones disponibles al llegar al extremo ("start" o "end") del segmento actual.
## Excluye el propio segmento. Cada opción indica el próximo segmento_id y si hay
## que recorrerlo "forward" o "reversed" según cómo esté orientado.
func get_opciones_siguientes(segment_id: String, extremo_actual: String) -> Array[Dictionary]:
	if not segments_data.has(segment_id):
		return []

	var seg: Dictionary = segments_data[segment_id] as Dictionary
	var extremo_topologico: String = _extremo_topologico_de_local(segment_id, extremo_actual)
	var node_id: int = int(seg.get("node_end", 0)) if extremo_topologico == "end" else int(seg.get("node_start", 0))

	var junction_raw: Variant = junctions.get(str(node_id))
	var empalmes: Array = _empalmes_escena.get(str(node_id), []) as Array
	if (junction_raw == null or not (junction_raw is Dictionary)) and empalmes.is_empty():
		return []

	var junction: Dictionary = junction_raw as Dictionary if junction_raw is Dictionary else {}
	var opciones: Array[Dictionary] = []
	var conexiones: Array = (junction.get("segments", []) as Array) + empalmes

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
		var direccion: String = _direccion_local_desde_extremo_topologico(otro_id, otro_extremo)
		opciones.append({
			"segment_id": otro_id,
			"direccion": direccion,
			"node_id": node_id,
			"end": otro_extremo,
			"vector": _obtener_vector_salida_segmento(otro_id, otro_extremo)
		})

	return opciones


## Recorre la continuidad física inmediata de una vía sin tomar ninguna
## bifurcación. Cada paso conserva el sentido local y el intervalo métrico que
## queda por delante de la cabecera. Es la referencia autoritativa para decidir
## si una estación se puede atender antes de una aguja.
func obtener_corredor_inmediato(segmento_inicial: String, offset_inicial: float, sentido_invertido: bool, max_pasos: int = 64) -> Array[Dictionary]:
	var corredor: Array[Dictionary] = []
	if not paths.has(segmento_inicial):
		return corredor
	var segmento: String = segmento_inicial
	var direccion: String = "reversed" if sentido_invertido else "forward"
	var entrada: float = offset_inicial
	var distancia_acumulada := 0.0
	var visitados: Dictionary = {}
	for _paso: int in max_pasos:
		var clave: String = "%s|%s" % [segmento, direccion]
		if visitados.has(clave):
			break
		visitados[clave] = true
		var path: Path3D = get_segment_path(segmento)
		if path == null or path.curve == null:
			break
		var largo: float = path.curve.get_baked_length()
		var desde: float = clampf(entrada, 0.0, largo)
		var hasta: float = 0.0 if direccion == "reversed" else largo
		corredor.append({
			"segmento": segmento,
			"direccion": direccion,
			"desde": desde,
			"hasta": hasta,
			"distancia_inicio": distancia_acumulada,
		})
		distancia_acumulada += absf(hasta - desde)
		var extremo: String = "start" if direccion == "reversed" else "end"
		var opciones: Array[Dictionary] = get_opciones_siguientes(segmento, extremo)
		# La primera decisión pertenece a la siguiente sección; no se la atraviesa.
		if opciones.size() != 1:
			break
		var siguiente: Dictionary = opciones[0]
		segmento = str(siguiente.get("segment_id", ""))
		direccion = str(siguiente.get("direccion", "forward"))
		var siguiente_path: Path3D = get_segment_path(segmento)
		if siguiente_path == null or siguiente_path.curve == null:
			break
		entrada = siguiente_path.curve.get_baked_length() if direccion == "reversed" else 0.0
	return corredor


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
func set_switch_target(node_id: int, target_segment_id: String, solicitante_id: int = 0) -> void:
	var propietario: int = int(_propietarios_recursos.get("switch:%d" % node_id, 0))
	if propietario != 0 and propietario != solicitante_id:
		push_warning("TrackNetwork: no se cambia la aguja %d; está reservada por el tren %d." % [node_id, propietario])
		return
	switch_states[node_id] = target_segment_id
	if aparatos_de_via.has(node_id):
		var ap: BaseTurnout = aparatos_de_via[node_id] as BaseTurnout
		if ap != null:
			ap.conmutar_a(1 if target_segment_id == ap.via_desviada_id else 0)
	switch_conmutado.emit(node_id, target_segment_id)


## Reserva el switch de entrada al próximo Path3D. Sólo las agujas son un
## recurso exclusivo: las vías, por largas que sean, admiten varios trenes y la
## separación entre ellos la resuelve la detección de conflictos del tren. Las
## solicitudes se ordenan FIFO para que ningún tren saltee a otro que llegó antes.
##
## Excepción: las vías de uso común y los andenes en vía muerta se recorren en
## los dos sentidos. Se reservan como un bloque (`bloque` = tramos que siguen
## en el itinerario) y se liberan recién cuando la cola sale de cada uno.
func solicitar_reserva_seccion(tren_id: int, segmento: String, nodo_switch: int, odometro: float, largo_tren: float, bloque: Array[String] = []) -> bool:
	if tren_id <= 0 or not paths.has(segmento):
		return false
	var recursos: Array[String] = []
	if nodo_switch > 0 and _nodo_tiene_aguja(nodo_switch):
		recursos.append("switch:%d" % nodo_switch)
	if es_via_exclusiva(segmento):
		recursos.append("via:%s" % segmento)
		for extra: String in bloque:
			if paths.has(extra) and es_via_exclusiva(extra) and not recursos.has("via:%s" % extra):
				recursos.append("via:%s" % extra)
	if recursos.is_empty():
		return true
	if not _adquirir_recursos_fifo(tren_id, recursos):
		return false
	for recurso: String in recursos:
		_agregar_reserva_tren(tren_id, recurso, INF if recurso.begins_with("via:") else odometro + largo_tren + 8.0)
	reservas_cambiadas.emit()
	return true


## Vía que admite trenes en ambos sentidos: de uso común o andén en vía muerta
## (se entra y se sale por el mismo extremo).
func es_via_exclusiva(segmento: String) -> bool:
	if not paths.has(segmento):
		return false
	if segmento_permite_sentido(segmento, true) and segmento_permite_sentido(segmento, false):
		return true
	return get_opciones_siguientes(segmento, "start").is_empty() or get_opciones_siguientes(segmento, "end").is_empty()


## La formación dejó `segmento`: su reserva vence cuando la cola termina de salir.
func liberar_via_al_salir(tren_id: int, segmento: String, limite_odometro: float) -> void:
	for reserva_raw: Variant in _reservas_por_tren.get(tren_id, []) as Array:
		var reserva: Dictionary = reserva_raw as Dictionary
		if str(reserva.get("recurso", "")) == "via:%s" % segmento:
			reserva["limite"] = minf(float(reserva.get("limite", INF)), limite_odometro)


func _nodo_tiene_aguja(nodo: int) -> bool:
	if aparatos_de_via.has(nodo):
		return true
	return ((junctions.get(str(nodo), {}) as Dictionary).get("segments", []) as Array).size() > 2


## Reserva la vía bajo una formación que empieza detenida en Constitución.
func reservar_tramo_inicial(tren_id: int, segmento: String, offset: float, invertido: bool, odometro: float, largo_tren: float) -> bool:
	if tren_id <= 0 or not paths.has(segmento):
		return false
	var path: Path3D = get_segment_path(segmento)
	if path == null or path.curve == null:
		return false
	var largo: float = path.curve.get_baked_length()
	var hasta_salida: float = offset if invertido else largo - offset
	var recurso: String = "via:%s" % segmento
	var recursos: Array[String] = [recurso]
	if not _adquirir_recursos_fifo(tren_id, recursos):
		return false
	_propietarios_recursos[recurso] = tren_id
	_agregar_reserva_tren(tren_id, recurso, odometro + hasta_salida + largo_tren)
	reservas_cambiadas.emit()
	return true


func _agregar_reserva_tren(tren_id: int, recurso: String, limite_odometro: float) -> void:
	var reservas: Array = _reservas_por_tren.get(tren_id, []) as Array
	for reserva_raw: Variant in reservas:
		var reserva: Dictionary = reserva_raw as Dictionary
		if str(reserva.get("recurso", "")) == recurso:
			reserva["limite"] = maxf(float(reserva.get("limite", 0.0)), limite_odometro)
			reservas_cambiadas.emit()
			return
	reservas.append({"recurso": recurso, "limite": limite_odometro})
	_reservas_por_tren[tren_id] = reservas


func _adquirir_recursos_fifo(tren_id: int, recursos: Array[String]) -> bool:
	var solicitud_indice: int = -1
	for indice: int in _cola_solicitudes_reserva.size():
		if int(_cola_solicitudes_reserva[indice].get("tren", 0)) == tren_id:
			solicitud_indice = indice
			_cola_solicitudes_reserva[indice]["recursos"] = recursos.duplicate()
			break
	if solicitud_indice < 0:
		solicitud_indice = _cola_solicitudes_reserva.size()
		_cola_solicitudes_reserva.append({"tren": tren_id, "recursos": recursos.duplicate()})
	# FIFO por recurso: una solicitud anterior sólo detiene ésta si necesita
	# alguno de los mismos recursos; solicitudes independientes no se bloquean.
	# Un recurso que ya es de este tren no se cede a los que esperan: el dueño
	# vuelve a pedir su sección al cruzar la unión y, si quedara detrás de otro
	# en la cola, ambos se esperarían para siempre.
	# Tampoco espera a una solicitud anterior que necesita algo de este tren: esa
	# no puede avanzar hasta que éste libere (andén en vía muerta en Bosques).
	for indice: int in solicitud_indice:
		var anteriores: Array = _cola_solicitudes_reserva[indice].get("recursos", []) as Array
		var anterior_depende_de_este: bool = false
		for recurso_anterior: Variant in anteriores:
			if int(_propietarios_recursos.get(str(recurso_anterior), 0)) == tren_id:
				anterior_depende_de_este = true
				break
		if anterior_depende_de_este:
			continue
		for recurso: String in recursos:
			if anteriores.has(recurso) and int(_propietarios_recursos.get(recurso, 0)) != tren_id:
				return false
	for recurso: String in recursos:
		var propietario: int = int(_propietarios_recursos.get(recurso, 0))
		if propietario != 0 and propietario != tren_id:
			return false
	for recurso: String in recursos:
		_propietarios_recursos[recurso] = tren_id
	_cola_solicitudes_reserva.remove_at(solicitud_indice)
	return true


## Libera las reservas que la cola del tren ya despejó.
func actualizar_reservas_tren(tren_id: int, odometro: float) -> void:
	var reservas: Array = _reservas_por_tren.get(tren_id, []) as Array
	var restantes: Array = []
	var hubo_cambios := false
	for reserva_raw: Variant in reservas:
		var reserva: Dictionary = reserva_raw as Dictionary
		var recurso: String = str(reserva.get("recurso", ""))
		if odometro >= float(reserva.get("limite", INF)) and int(_propietarios_recursos.get(recurso, 0)) == tren_id:
			_propietarios_recursos.erase(recurso)
			hubo_cambios = true
		else:
			restantes.append(reserva)
	if restantes.is_empty():
		_reservas_por_tren.erase(tren_id)
	else:
		_reservas_por_tren[tren_id] = restantes
	if hubo_cambios:
		reservas_cambiadas.emit()


func liberar_reservas_tren(tren_id: int) -> void:
	for recurso: Variant in _propietarios_recursos.keys():
		if int(_propietarios_recursos[recurso]) == tren_id:
			_propietarios_recursos.erase(recurso)
	_cola_solicitudes_reserva = _cola_solicitudes_reserva.filter(func(solicitud: Dictionary) -> bool: return int(solicitud.get("tren", 0)) != tren_id)
	_reservas_por_tren.erase(tren_id)
	_itinerarios_ramas_tren.erase(tren_id)
	reservas_cambiadas.emit()


## Actualiza la rama paralela prevista por una formación. La intención se
## reemplaza cada vez que el tren calcula su siguiente ruta.
func registrar_itinerario_tren(tren_id: int, segmentos: Array[String]) -> void:
	if tren_id <= 0:
		return
	var ramas: Array[String] = []
	for segmento: String in segmentos:
		if segmento in RAMAS_IDA_BALANCEADAS:
			ramas.append(segmento)
	_itinerarios_ramas_tren[tren_id] = ramas


func _penalizacion_rama_balanceada(segmento: String) -> float:
	if not segmento in RAMAS_IDA_BALANCEADAS:
		return 0.0
	var cantidad: int = 0
	for ramas_raw: Variant in _itinerarios_ramas_tren.values():
		var ramas: Array = ramas_raw as Array
		if ramas.has(segmento):
			cantidad += 1
	return float(cantidad) * PENALIZACION_RAMA_OCUPADA_M


func recurso_reservado_por_otro(tren_id: int, segmento: String = "", nodo_switch: int = 0) -> bool:
	if not segmento.is_empty() and int(_propietarios_recursos.get("via:%s" % segmento, 0)) not in [0, tren_id]:
		return true
	if nodo_switch > 0 and int(_propietarios_recursos.get("switch:%d" % nodo_switch, 0)) not in [0, tren_id]:
		return true
	return false


func segmento_reservado(segmento: String) -> bool:
	return int(_propietarios_recursos.get("via:%s" % segmento, 0)) != 0


func propietario_via(segmento: String) -> int:
	return int(_propietarios_recursos.get("via:%s" % segmento, 0))


func nombre_opcion_switch(nodo_id: int, segmento: String) -> String:
	if aparatos_de_via.has(nodo_id):
		var aparato: BaseTurnout = aparatos_de_via[nodo_id] as BaseTurnout
		if aparato != null:
			if segmento == aparato.via_directa_id:
				return "Directa · %s" % segmento
			if segmento == aparato.via_desviada_id:
				return "Desviada · %s" % segmento
	return segmento


## Muestra un marcador de inspección liviano sobre una aguja. El HUD sólo pasa
## IDs de topología: la red mantiene la relación con la geometría física.
func mostrar_indicador_switch_hud(nodo_id: int, segmento_activo: String = "") -> void:
	_ocultar_indicador_switch_hud()
	var aparato: BaseTurnout = aparatos_de_via.get(nodo_id) as BaseTurnout
	if aparato == null or not is_instance_valid(aparato):
		return
	var indicador := Node3D.new()
	indicador.name = "IndicadorSwitchHUD"
	indicador.global_position = aparato.global_position + Vector3.UP * 0.18
	add_child(indicador)
	_indicador_switch_hud = indicador
	_indicador_switch_hud_id = nodo_id

	var aro := MeshInstance3D.new()
	var aro_mesh := TorusMesh.new()
	aro_mesh.inner_radius = 2.4
	aro_mesh.outer_radius = 2.55
	aro.mesh = aro_mesh
	aro.material_override = _material_indicador_switch(Color(1.0, 0.756863, 0.278431, 0.82), false)
	aro.rotation_degrees.x = 90.0
	indicador.add_child(aro)

	var texto := Label3D.new()
	texto.text = "AGUJA %d" % nodo_id
	texto.font_size = 32
	texto.outline_size = 4
	texto.modulate = Color(0.65, 0.68, 0.75, 0.96)
	texto.position = Vector3(0, 1.4, 0)
	texto.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	indicador.add_child(texto)

	var directa: String = aparato.via_directa_id
	var desviada: String = aparato.via_desviada_id
	_agregar_guia_indicador_switch(indicador, directa, directa == segmento_activo, Color(1.0, 0.756863, 0.278431, 0.92))
	_agregar_guia_indicador_switch(indicador, desviada, desviada == segmento_activo, Color(0.65, 0.68, 0.75, 0.60))


func ocultar_indicador_switch_hud() -> void:
	_ocultar_indicador_switch_hud()


func _ocultar_indicador_switch_hud() -> void:
	if _indicador_switch_hud != null and is_instance_valid(_indicador_switch_hud):
		_indicador_switch_hud.queue_free()
	_indicador_switch_hud = null
	_indicador_switch_hud_id = 0


func _material_indicador_switch(color: Color, transparente: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	if transparente:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _agregar_guia_indicador_switch(indicador: Node3D, segmento: String, activa: bool, color: Color) -> void:
	if segmento.is_empty():
		return
	var path: Path3D = get_segment_path(segmento)
	if path == null or path.curve == null or path.curve.get_baked_length() < 0.1:
		return
	var largo: float = path.curve.get_baked_length()
	var inicio: bool = path.to_global(path.curve.sample_baked(0.0)).distance_squared_to(indicador.global_position) <= path.to_global(path.curve.sample_baked(largo)).distance_squared_to(indicador.global_position)
	var pasos := 10
	var alcance: float = minf(28.0, largo)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	mesh.surface_set_color(color if activa else Color(color.r, color.g, color.b, color.a * 0.65))
	for indice: int in range(pasos + 1):
		var distancia: float = alcance * float(indice) / float(pasos)
		var offset: float = distancia if inicio else largo - distancia
		mesh.surface_add_vertex(path.to_global(path.curve.sample_baked(offset)) - indicador.global_position)
	mesh.surface_end()
	var guia := MeshInstance3D.new()
	guia.mesh = mesh
	guia.material_override = _material_indicador_switch(color if activa else Color(color.r, color.g, color.b, color.a * 0.65), true)
	indicador.add_child(guia)


## Comprueba si un tramo Path3D es compatible con el sentido operativo de un tren (IDA o VUELTA).
## Vías de USO_COMUN son aptas para ambos sentidos.
func segmento_permite_sentido(segment_id: String, sentido_ida: bool) -> bool:
	var path: Path3D = get_segment_path(segment_id)
	if path == null:
		return false
	if path.has_method("permite_sentido_servicio"):
		return bool(path.call("permite_sentido_servicio", sentido_ida))
	return true


## Obtiene la opción seleccionada para un switch. Si no está definida, devuelve la primera disponible compatible con sentido_ida.
func get_switch_target(node_id: int, opciones: Array[Dictionary], segmento_origen: String = "", sentido_ida: Variant = null) -> Dictionary:
	# Filtrar antes de evaluar el aparato: su estado activo puede apuntar a una
	# rama prohibida para este tren. Esta consulta no debe conmutar la aguja.
	if sentido_ida != null:
		var permitidas: Array[Dictionary] = []
		for opcion: Dictionary in opciones:
			if segmento_permite_sentido(str(opcion.get("segment_id", "")), bool(sentido_ida)):
				permitidas.append(opcion)
		opciones = permitidas
	if opciones.is_empty():
		return {}
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
					# Si viene desde la vía común (stem), selecciona según el sentido operativo del tren
					if sentido_ida != null:
						var permite_dir: bool = segmento_permite_sentido(ap.via_directa_id, bool(sentido_ida))
						var permite_desv: bool = segmento_permite_sentido(ap.via_desviada_id, bool(sentido_ida))
						if permite_dir and not permite_desv:
							for op: Dictionary in opciones:
								if str(op.get("segment_id", "")) == ap.via_directa_id:
									return op
						elif permite_desv and not permite_dir:
							for op: Dictionary in opciones:
								if str(op.get("segment_id", "")) == ap.via_desviada_id:
									return op

					var target: String = ap.get_segmento_activo()
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == target:
							return op

			# Fallback con sentido en el aparato
			if sentido_ida != null:
				var permite_dir_fb: bool = segmento_permite_sentido(ap.via_directa_id, bool(sentido_ida))
				var permite_desv_fb: bool = segmento_permite_sentido(ap.via_desviada_id, bool(sentido_ida))
				if permite_dir_fb and not permite_desv_fb:
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == ap.via_directa_id:
							return op
				elif permite_desv_fb and not permite_dir_fb:
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == ap.via_desviada_id:
							return op

			var target_id: String = ap.get_segmento_activo()
			if sentido_ida != null:
				if not segmento_permite_sentido(target_id, bool(sentido_ida)):
					var otra_rama: String = ap.via_desviada_id if target_id == ap.via_directa_id else ap.via_directa_id
					if segmento_permite_sentido(otra_rama, bool(sentido_ida)):
						for op: Dictionary in opciones:
							if str(op.get("segment_id", "")) == otra_rama:
								return op
					if segmento_permite_sentido(ap.via_comun_id, bool(sentido_ida)):
						for op: Dictionary in opciones:
							if str(op.get("segment_id", "")) == ap.via_comun_id:
								return op
				else:
					for op: Dictionary in opciones:
						if str(op.get("segment_id", "")) == target_id:
							return op
			else:
				for op: Dictionary in opciones:
					if str(op.get("segment_id", "")) == target_id:
						return op

			# Si target_id no está en opciones o no es compatible, intentar vía común
			if sentido_ida == null or segmento_permite_sentido(ap.via_comun_id, bool(sentido_ida)):
				for op: Dictionary in opciones:
					if str(op.get("segment_id", "")) == ap.via_comun_id:
						return op

	if switch_states.has(node_id):
		var target_id: String = str(switch_states[node_id])
		if sentido_ida == null or segmento_permite_sentido(target_id, bool(sentido_ida)):
			for op: Dictionary in opciones:
				if str(op.get("segment_id", "")) == target_id:
					return op

	var opciones_evaluadas: Array[Dictionary] = opciones

	# Continuidad geométrica (uniones sin `via_comun/directa/desviada` ni metadata:
	# cruces, tijeras en cadena, escapes). Antes caía a `opciones[0]` y elegía una
	# rama al azar; ahora continúa lo más recto posible respecto de la llegada.
	var dir_llegada: Vector2 = _direccion_llegada_union(segmento_origen, node_id)
	if dir_llegada != Vector2.ZERO:
		var mejor_dot: float = -2.0
		var mejor_op: Dictionary = {}
		for op: Dictionary in opciones_evaluadas:
			var v: Vector2 = op.get("vector", Vector2.ZERO) as Vector2
			if v.length_squared() < 1e-6:
				continue
			var d: float = dir_llegada.dot(v)
			if d > mejor_dot:
				mejor_dot = d
				mejor_op = op
		if not mejor_op.is_empty() and mejor_dot >= -0.5:
			return mejor_op

	if opciones_evaluadas.size() > 0:
		return opciones_evaluadas[0]
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


## Calcula un itinerario por la topología, no por el orden de los nodos de la
## escena. El resultado contiene los IDs de tramos, en el orden de circulación,
## y la distancia métrica hasta el offset de destino.
func planificar_ruta(segmento_origen: String, offset_origen: float, sentido_invertido: bool, segmento_destino: String, offset_destino: float, override_segmentos: Array[String] = [], switches_forzados: Dictionary = {}, sentido_ida: Variant = null, permitir_origen_terminal: bool = false) -> Dictionary:
	if not paths.has(segmento_origen) or not paths.has(segmento_destino):
		return {"ok": false, "motivo": "segmento inexistente", "segmentos": []}
	if sentido_ida != null and ((not permitir_origen_terminal and not segmento_permite_sentido(segmento_origen, bool(sentido_ida))) or not segmento_permite_sentido(segmento_destino, bool(sentido_ida))):
		return {"ok": false, "motivo": "segmento no permitido para el sentido", "segmentos": []}
	if not override_segmentos.is_empty():
		return _planificar_override_dirigido(segmento_origen, offset_origen, sentido_invertido, segmento_destino, offset_destino, override_segmentos, sentido_ida, permitir_origen_terminal)

	var dir_inicial: String = "reversed" if sentido_invertido else "forward"
	var cola: Array[Dictionary] = [ {"seg": segmento_origen, "dir": dir_inicial, "entrada": offset_origen, "costo": 0.0}]
	var costos: Dictionary = {"%s|%s" % [segmento_origen, dir_inicial]: 0.0}
	var anterior: Dictionary = {}
	var visitados: Dictionary = {}
	var estado_final: String = ""

	while not cola.is_empty():
		cola.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["costo"]) < float(b["costo"]))
		var actual: Dictionary = cola.pop_front()
		var seg_id: String = str(actual["seg"])
		var dir: String = str(actual["dir"])
		var clave: String = "%s|%s" % [seg_id, dir]
		if visitados.has(clave):
			continue
		visitados[clave] = true
		var path: Path3D = get_segment_path(seg_id)
		if path == null or path.curve == null:
			continue
		var largo: float = path.curve.get_baked_length()
		var entrada: float = clampf(float(actual["entrada"]), 0.0, largo)
		var destino_adelante: bool = seg_id == segmento_destino and ((dir == "forward" and offset_destino >= entrada) or (dir == "reversed" and offset_destino <= entrada))
		if destino_adelante:
			estado_final = clave
			break

		var distancia_salida: float = (largo - entrada) if dir == "forward" else entrada
		var extremo: String = "end" if dir == "forward" else "start"
		var opciones: Array[Dictionary] = get_opciones_siguientes(seg_id, extremo)
		var nodo_union: int = int(opciones[0].get("node_id", 0)) if not opciones.is_empty() else 0
		var segmento_forzado: String = str(switches_forzados.get(nodo_union, switches_forzados.get(str(nodo_union), "")))
		for opcion: Dictionary in opciones:
			var prox_id: String = str(opcion.get("segment_id", ""))
			if not segmento_forzado.is_empty() and prox_id != segmento_forzado:
				continue
			if sentido_ida != null and not segmento_permite_sentido(prox_id, bool(sentido_ida)):
				continue
			if _es_paso_entre_ramas(nodo_union, seg_id, prox_id):
				continue
			var prox_dir: String = str(opcion.get("direccion", "forward"))
			var prox_clave: String = "%s|%s" % [prox_id, prox_dir]
			# Cuando dos rutas IDA usan las ramas paralelas 735/737, la rama que
			# ya fue elegida por otras formaciones recibe un costo temporal. Así
			# la siguiente planificación toma la alternativa libre si existe.
			var nuevo_costo: float = float(actual["costo"]) + distancia_salida + _penalizacion_rama_balanceada(prox_id)
			if costos.has(prox_clave) and float(costos[prox_clave]) <= nuevo_costo:
				continue
			costos[prox_clave] = nuevo_costo
			anterior[prox_clave] = clave
			var prox_path: Path3D = get_segment_path(prox_id)
			if prox_path == null or prox_path.curve == null:
				continue
			var prox_largo: float = prox_path.curve.get_baked_length()
			cola.append({"seg": prox_id, "dir": prox_dir, "entrada": 0.0 if prox_dir == "forward" else prox_largo, "costo": nuevo_costo})

	if estado_final.is_empty():
		return {"ok": false, "motivo": "no existe conexión ferroviaria", "segmentos": []}
	var pasos_inversos: Array[Dictionary] = []
	var cursor: String = estado_final
	while not cursor.is_empty():
		pasos_inversos.append({"segmento": cursor.get_slice("|", 0), "direccion": cursor.get_slice("|", 1)})
		cursor = str(anterior.get(cursor, ""))
	pasos_inversos.reverse()
	var segmentos: Array[String] = []
	var usados: Dictionary = {}
	for paso: Dictionary in pasos_inversos:
		var sid: String = str(paso.get("segmento", ""))
		if usados.has(sid):
			return {"ok": false, "motivo": "la ruta repite el segmento %s" % sid, "segmentos": [], "pasos": []}
		usados[sid] = true
		segmentos.append(sid)
	var cambios_aguja: int = 0
	for indice: int in maxi(0, pasos_inversos.size() - 1):
		var paso_actual: Dictionary = pasos_inversos[indice]
		var extremo: String = "end" if str(paso_actual.get("direccion", "forward")) == "forward" else "start"
		if es_switch(str(paso_actual.get("segmento", "")), extremo):
			cambios_aguja += 1

	# Recalcular la distancia métrica física real sin penalizaciones heurísticas
	var distancia_real: float = 0.0
	for idx: int in pasos_inversos.size():
		var p_sid: String = str(pasos_inversos[idx].get("segmento", ""))
		var p_path: Path3D = get_segment_path(p_sid)
		if p_path == null or p_path.curve == null:
			continue
		var p_largo: float = p_path.curve.get_baked_length()
		if idx == 0 and idx == pasos_inversos.size() - 1:
			distancia_real += absf(offset_destino - offset_origen)
		elif idx == 0:
			distancia_real += (p_largo - offset_origen) if str(pasos_inversos[idx].get("direccion", "forward")) == "forward" else offset_origen
		elif idx == pasos_inversos.size() - 1:
			distancia_real += offset_destino if str(pasos_inversos[idx].get("direccion", "forward")) == "forward" else (p_largo - offset_destino)
		else:
			distancia_real += p_largo

	return {"ok": true, "segmentos": segmentos, "pasos": pasos_inversos, "distancia_m": distancia_real, "cambios_aguja": cambios_aguja, "forzada": false, "sentido_invertido": sentido_invertido}


## En un desvío sólo se circula entre la vía común y una de sus ramas. Pasar de
## la directa a la desviada (o al revés) es un retroceso físicamente imposible
## (p. ej. llegar por seg_308 y volver por seg_496).
func _es_paso_entre_ramas(nodo_union: int, desde: String, hacia: String) -> bool:
	var ap: BaseTurnout = aparatos_de_via.get(nodo_union) as BaseTurnout
	if ap == null or not is_instance_valid(ap) or ap.has_meta("linea_a_segs"):
		return false
	var ramas: Array[String] = [ap.via_directa_id, ap.via_desviada_id]
	return desde != hacia and desde in ramas and hacia in ramas


## Valida un override como una secuencia física dirigida. Antes se aceptaba la
## lista por nombre y el tren podía llegar a una aguja sin continuidad ni
## distancia métrica; ahora cada tramo debe suceder al anterior en el extremo
## que realmente alcanza la cabecera.
func _planificar_override_dirigido(segmento_origen: String, offset_origen: float, sentido_invertido: bool, segmento_destino: String, offset_destino: float, override_segmentos: Array[String], sentido_ida: Variant = null, permitir_origen_terminal: bool = false) -> Dictionary:
	var forzada: Array[String] = override_segmentos.duplicate()
	if forzada.is_empty():
		return {"ok": false, "motivo": "override vacío", "segmentos": [], "pasos": []}
	if forzada.front() != segmento_origen:
		forzada.push_front(segmento_origen)
	if forzada.back() != segmento_destino:
		forzada.append(segmento_destino)

	var usados: Dictionary = {}
	for sid: String in forzada:
		if not paths.has(sid):
			return {"ok": false, "motivo": "override contiene segmento inexistente: %s" % sid, "segmentos": [], "pasos": []}
		if sentido_ida != null and not (permitir_origen_terminal and sid == segmento_origen) and not segmento_permite_sentido(sid, bool(sentido_ida)):
			return {"ok": false, "motivo": "override contiene segmento no permitido: %s" % sid, "segmentos": [], "pasos": []}
		if usados.has(sid):
			return {"ok": false, "motivo": "override repite el segmento: %s" % sid, "segmentos": [], "pasos": []}
		usados[sid] = true

	var direccion: String = "reversed" if sentido_invertido else "forward"
	var entrada: float = offset_origen
	var distancia: float = 0.0
	var cambios_aguja: int = 0
	var pasos: Array[Dictionary] = [ {"segmento": segmento_origen, "direccion": direccion}]

	for indice: int in range(forzada.size() - 1):
		var actual_id: String = forzada[indice]
		var siguiente_id: String = forzada[indice + 1]
		var actual: Path3D = get_segment_path(actual_id)
		if actual == null or actual.curve == null:
			return {"ok": false, "motivo": "override sin geometría: %s" % actual_id, "segmentos": [], "pasos": []}
		var largo_actual: float = actual.curve.get_baked_length()
		entrada = clampf(entrada, 0.0, largo_actual)
		var extremo: String = "start" if direccion == "reversed" else "end"
		var opcion_valida: Dictionary = {}
		for opcion: Dictionary in get_opciones_siguientes(actual_id, extremo):
			if str(opcion.get("segment_id", "")) == siguiente_id:
				opcion_valida = opcion
				break
		if opcion_valida.is_empty():
			return {"ok": false, "motivo": "override sin continuidad: %s (%s) -> %s" % [actual_id, extremo, siguiente_id], "segmentos": [], "pasos": []}
		distancia += (largo_actual - entrada) if direccion == "forward" else entrada
		if es_switch(actual_id, extremo):
			cambios_aguja += 1
		direccion = str(opcion_valida.get("direccion", "forward"))
		var siguiente: Path3D = get_segment_path(siguiente_id)
		if siguiente == null or siguiente.curve == null:
			return {"ok": false, "motivo": "override sin geometría: %s" % siguiente_id, "segmentos": [], "pasos": []}
		entrada = siguiente.curve.get_baked_length() if direccion == "reversed" else 0.0
		pasos.append({"segmento": siguiente_id, "direccion": direccion})

	var destino: Path3D = get_segment_path(segmento_destino)
	if destino == null or destino.curve == null:
		return {"ok": false, "motivo": "destino sin geometría", "segmentos": [], "pasos": []}
	var largo_destino: float = destino.curve.get_baked_length()
	offset_destino = clampf(offset_destino, 0.0, largo_destino)
	var destino_adelante: bool = offset_destino >= entrada if direccion == "forward" else offset_destino <= entrada
	if not destino_adelante:
		return {"ok": false, "motivo": "el destino queda detrás del sentido del override", "segmentos": [], "pasos": []}
	distancia += absf(offset_destino - entrada)
	return {"ok": true, "segmentos": forzada, "pasos": pasos, "distancia_m": distancia, "cambios_aguja": cambios_aguja, "forzada": true, "sentido_invertido": sentido_invertido}


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
	if not is_inside_tree():
		return
	# Al abrir una escena editada, sus estaciones son la fuente vigente. El
	# journal puede ser anterior a un guardado del editor y no debe pisarlas.
	if Engine.is_editor_hint() and _tiene_vias_en_arbol():
		_sincronizar_estaciones_serializadas_con_journal()
		return
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	if ests.is_empty():
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


## Mantiene el respaldo de estaciones al día con las ediciones del inspector.
func _sincronizar_estaciones_serializadas_con_journal() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	var cambio: bool = false
	for e: Node in get_tree().get_nodes_in_group("estaciones"):
		if not is_instance_valid(e) or not e.has_method("obtener_id_edicion") or not e.has_method("serializar_datos"):
			continue
		var id_est: String = str(e.call("obtener_id_edicion"))
		var datos: Dictionary = e.call("serializar_datos") as Dictionary
		if _huellas_estaciones.get(id_est, {}) == datos:
			continue
		_huellas_estaciones[id_est] = datos.duplicate(true)
		if ests.get(id_est, {}) != datos:
			ests[id_est] = datos
			cambio = true
	if cambio:
		_ediciones_guardadas["_estaciones"] = ests
		_autoguardado_pendiente = true
		_tiempo_autoguardado = 0.0


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

	# Respaldar todas las estaciones, incluidas las editadas sólo en el inspector.
	var ests: Dictionary = _ediciones_guardadas.get("_estaciones", {}) as Dictionary
	if is_inside_tree():
		for e: Node in get_tree().get_nodes_in_group("estaciones"):
			if not is_instance_valid(e):
				continue
			if e.has_method("serializar_datos") and e.has_method("obtener_id_edicion"):
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
	else:
		push_error("TrackNetwork: No se pudieron guardar las ediciones en '%s' (error %d)." % [ruta, FileAccess.get_open_error()])


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
	_on_segmento_datos_modificados(seg_id)
	_segmentos_edicion_pendientes[seg_id] = true
	if _edicion_diferida_programada:
		return
	_edicion_diferida_programada = true
	call_deferred("_procesar_ediciones_pendientes")


func _on_segmento_datos_modificados(seg_id: String) -> void:
	if not Engine.is_editor_hint():
		return
	var via: EditableTrackSegment = paths.get(seg_id) as EditableTrackSegment
	if via == null or not is_instance_valid(via):
		return
	_ediciones_guardadas[seg_id] = via.serializar_datos()
	_autoguardado_pendiente = true
	_tiempo_autoguardado = 0.0


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
	var distancia_final: float = _conectar_lead_a_segmento(sw, lead, p_seg, seg_id, extremo, sw.node_id)
	_registrar_recorte_segmento(seg_id, extremo, distancia_final)


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
