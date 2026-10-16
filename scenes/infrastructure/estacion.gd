@tool
extends Node3D
class_name Estacion
## Estación ferroviaria modular para Train Simulator.
##
## Permite vincularse a un Path3D y ajustarse automáticamente a la curva en
## tiempo real, orientándose tangencialmente a los rieles en el editor.
## Incluye andén de longitud configurable y postes de parada visuales interactivos
## para que el usuario pueda definir en el visor 3D el punto exacto de frenado.
##
## Compatible con Godot 4.x / 4.7.

signal transformada_cambiada(estacion: Estacion)
signal edicion_guardada(estacion: Estacion)
signal reseteada(estacion: Estacion)
signal pasajeros_actualizados(estacion: Estacion)
signal seleccionada(estacion: Estacion)
signal abordaje_cambiado(activo: bool)
signal ingreso_pasajeros_cambiado(habilitado: bool)

enum DestinoAnden { CONSTITUCION, BOSQUES, AMBOS }

const PACK_MODELOS_PASAJEROS: PackedScene = preload("res://assets/models/passengers/free_pack_-_lowpoly_people.glb")
const ESCALA_ELEMENTOS_INFORMACION: float = 5.0
const NOMBRES_VARIANTES_PASAJERO: Array[String] = [
	"SM_People_Lowpoly_01",
	"SM_People_Lowpoly_02",
	"SM_People_Lowpoly_03",
	"SM_People_Lowpoly_04",
	"SM_People_Lowpoly_05",
	"SM_People_Lowpoly_06",
	"SM_People_Lowpoly_07",
	"SM_People_Lowpoly_08",
]
static var _variantes_pasajeros_cargadas: bool = false
static var _cache_mallas_pasajeros: Array[Mesh] = []
static var _cache_transformaciones_mallas_pasajeros: Array[Transform3D] = []
static var _cache_bounds_mallas_pasajeros: Array[AABB] = []

@export_group("Vinculación a la Vía")
## La traza (Path3D) a la que pertenece esta estación.
@export var traza: Path3D:
	set(v):
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.disconnect(_on_curva_cambiada)
		traza = v
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if not traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.connect(_on_curva_cambiada)
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			_aplicar_posicion_en_via()

## Si está activo, la estación se bloquea y orienta sobre la geometría del Path3D según progreso_en_via.
@export var alinear_a_via: bool = true:
	set(v):
		var se_acaba_de_activar: bool = not alinear_a_via and v
		alinear_a_via = v
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			if se_acaba_de_activar:
				_snap_a_posicion_actual()
			else:
				_aplicar_posicion_en_via()

## Distancia en metros a lo largo de la curva donde se ubica el centro de la estación.
@export_range(0.0, 10000.0, 0.5, "or_greater") var progreso_en_via: float = 0.0:
	set(v):
		progreso_en_via = maxf(0.0, v)
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			_aplicar_posicion_en_via()

## Pulsá este botón en el Inspector para forzar el ajuste de la estación al punto más cercano de la vía.
@export var alinear_a_posicion_actual: bool = false:
	set(v):
		if v:
			alinear_a_posicion_actual = false
			if is_inside_tree():
				alinear_a_via = true
				_snap_a_posicion_actual()

## Invierte el sentido longitudinal de la estación (giro 180°).
##
## También se actualiza automáticamente si se gira la estación con el
## manipulador del editor: el eje X local define hacia qué extremo queda la
## Parada Ida. La estación continúa alineada a la vía, por lo que no conserva
## inclinaciones o giros laterales accidentales.
@export var invertir_sentido: bool = false:
	set(v):
		invertir_sentido = v
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			_aplicar_posicion_en_via()

## Ajuste de altura sobre el plano de rodadura del riel (en metros).
@export var desfasaje_vertical: float = 0.0:
	set(v):
		desfasaje_vertical = v
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			_aplicar_posicion_en_via()

## Desplazamiento lateral perpendicular al riel (en metros).
@export var desfasaje_lateral: float = 0.0:
	set(v):
		desfasaje_lateral = v
		if is_inside_tree() and alinear_a_via and not _ajustando_transform:
			_aplicar_posicion_en_via()

@export_group("Dimensiones de Andén")
## Longitud total del andén en metros (200 m para formaciones completas de 7/8 coches).
@export_range(30.0, 500.0, 5.0) var longitud_anden: float = 200.0:
	set(v):
		longitud_anden = maxf(30.0, v)
		if is_inside_tree():
			_actualizar_dimensiones_anden()
			_notificar_trenes()

@export_group("Separación entre Vías")
## Separación transversal, en metros, entre los centros de los dos andenes.
## Afecta la posición de los andenes, marquesinas, columnas y postes de parada.
@export_range(2.0, 30.0, 0.1, "or_greater") var separacion_vias: float = 7.5:
	set(v):
		separacion_vias = maxf(2.0, v)
		if is_inside_tree():
			_actualizar_disposicion_transversal()
			_notificar_trenes()

@export_group("Ajuste fino de andenes")
## Corrección lateral adicional del andén de Ida, sus columnas, marquesina y poste.
## Sirve para adaptar el modelo visual a la distancia real entre vías sin alterar
## el anclaje de la estación (`traza` + `progreso_en_via`).
@export_range(-20.0, 20.0, 0.05, "suffix:m") var ajuste_lateral_anden_ida: float = 0.0:
	set(v):
		ajuste_lateral_anden_ida = v
		if is_inside_tree():
			_actualizar_disposicion_transversal()
			_notificar_trenes()

## Corrección lateral adicional del andén de Vuelta, sus columnas, marquesina y poste.
@export_range(-20.0, 20.0, 0.05, "suffix:m") var ajuste_lateral_anden_vuelta: float = 0.0:
	set(v):
		ajuste_lateral_anden_vuelta = v
		if is_inside_tree():
			_actualizar_disposicion_transversal()
			_notificar_trenes()

@export_group("Andenes centrales")
## Cantidad de andenes isla visuales entre los andenes de Ida y Vuelta.
## Cada uno se genera a partir del mismo modelo y se ajusta con su posición
## lateral; no crea una parada ferroviaria adicional.
@export_range(0, 2, 1) var cantidad_andenes_centrales: int = 0:
	set(v):
		cantidad_andenes_centrales = clampi(v, 0, 2)
		if is_inside_tree():
			_actualizar_disposicion_transversal()

## Posición local lateral del primer andén central. Cero representa el centro
## geométrico de la estación.
@export_range(-50.0, 50.0, 0.05, "suffix:m") var posicion_lateral_anden_central_1: float = 0.0:
	set(v):
		posicion_lateral_anden_central_1 = v
		if is_inside_tree():
			_actualizar_disposicion_transversal()

## Posición local lateral del segundo andén central, disponible al configurar
## `cantidad_andenes_centrales` en 2.
@export_range(-50.0, 50.0, 0.05, "suffix:m") var posicion_lateral_anden_central_2: float = 10.0:
	set(v):
		posicion_lateral_anden_central_2 = v
		if is_inside_tree():
			_actualizar_disposicion_transversal()

@export_group("Cobertura de Vías Paralelas")
## Ancho total del corredor físico de la estación. Todo Path3D paralelo que
## atraviese este rectángulo puede ser usado como vía de parada.
@export_range(5.0, 200.0, 1.0, "or_greater") var ancho_cobertura_vias: float = 35.0:
	set(v):
		ancho_cobertura_vias = maxf(5.0, v)
		if is_inside_tree():
			_notificar_trenes()

## Fija la parada Constitución -> Bosques sobre la traza asignada a la estación.
## Evita perseguir una vía paralela cuyo acceso queda después del andén.
@export var usar_traza_como_via_ida: bool = false:
	set(v):
		usar_traza_como_via_ida = v
		if is_inside_tree():
			_notificar_trenes()

@export_group("Puntos de Parada")
## Distancia métrica respecto al centro del andén para el frenado de ida (hacia adelante).
## Se sincroniza automáticamente al arrastrar el PosteParadaIda en el visor 3D.
@export var desfasaje_parada_ida: float = 75.0:
	set(v):
		desfasaje_parada_ida = v
		if is_inside_tree():
			_actualizar_posicion_postes()
			_notificar_trenes()

## Distancia métrica respecto al centro del andén para el frenado de vuelta (sentido inverso).
## Se sincroniza automáticamente al arrastrar el PosteParadaVuelta en el visor 3D.
@export var desfasaje_parada_vuelta: float = -75.0:
	set(v):
		desfasaje_parada_vuelta = v
		if is_inside_tree():
			_actualizar_posicion_postes()
			_notificar_trenes()

@export_group("Información de Servicio")
@export var nombre_estacion: String = "Estación":
	set(v):
		nombre_estacion = v
		_notificar_trenes()

@export_group("Terminal por Parada")
var _terminal_parada_ida: bool = false
var _terminal_parada_vuelta: bool = false

## Si está activo, el tren que llegue al Poste de Parada Ida invierte su marcha.
@export var terminal_parada_ida: bool = false:
	get:
		return _terminal_parada_ida
	set(v):
		_terminal_parada_ida = v
		_notificar_trenes()

## Si está activo, el tren que llegue al Poste de Parada Vuelta invierte su marcha.
@export var terminal_parada_vuelta: bool = false:
	get:
		return _terminal_parada_vuelta
	set(v):
		_terminal_parada_vuelta = v
		_notificar_trenes()

## Compatibilidad con escenas anteriores: al activarlo, marca ambas paradas como terminales.
@export var es_terminal: bool = false:
	get:
		return _terminal_parada_ida and _terminal_parada_vuelta
	set(v):
		_terminal_parada_ida = v
		_terminal_parada_vuelta = v
		_notificar_trenes()

@export var tiempo_espera: float = 20.0:
	set(v):
		tiempo_espera = maxf(0.0, v)
		_notificar_trenes()

@export var activa: bool = true:
	set(v):
		activa = v
		_notificar_trenes()

@export_group("Edición y Persistencia")
## Clave con la que se guarda la edición en el journal de la red. Si está vacía se usa el nombre del nodo.
@export var id_edicion: String = ""
## Pulsador: guarda la posición/estado actual de la estación en el journal de la red.
@export var boton_guardar: bool = false:
	set(v):
		if v:
			boton_guardar = false
			guardar_edicion()

## Pulsador: descarta la edición y restaura la estación a su estado original del JSON/escena.
@export var boton_resetear: bool = false:
	set(v):
		if v:
			boton_resetear = false
			resetear_a_original()

## Pulsador: imanta la estación a la vía más cercana de la red (igual que las vías).
@export var boton_alinear_a_via: bool = false:
	set(v):
		if v:
			boton_alinear_a_via = false
			alinear_a_via = true
			_snap_a_posicion_actual()

## Indica si la estación tiene cambios guardados respecto a su estado original.
@export var esta_editada: bool = false

var _datos_originales: Dictionary = {}

@export_group("Pasajeros")
@export_range(0, 100000, 1) var capacidad_maxima_espera: int = 150:
	set(v):
		capacidad_maxima_espera = maxi(0, v)
		if is_inside_tree():
			_configurar_pasajeros_por_anden()
			pasajeros_actualizados.emit(self)

## Permite excluir AndenB de la generación, el render y el embarque de pasajeros.
@export var incluir_anden_b_pasajeros: bool = true:
	set(v):
		if incluir_anden_b_pasajeros == v:
			return
		incluir_anden_b_pasajeros = v
		if is_inside_tree():
			_actualizar_area_seleccion()
			_configurar_pasajeros_por_anden()
			_reubicar_pasajeros_visuales()
			pasajeros_actualizados.emit(self)

## Ajuste vertical de las figuras del AndenA para integrarlas con plataformas existentes.
@export_range(-5.0, 5.0, 0.01, "suffix:m") var desfasaje_vertical_pasajeros_anden_a: float = 0.0:
	set(v):
		desfasaje_vertical_pasajeros_anden_a = v
		if is_inside_tree():
			_sincronizar_pasajeros_visuales()

## Ajuste lateral de las figuras del AndenA sin desplazar la parada del tren.
@export_range(-30.0, 30.0, 0.1, "suffix:m") var ajuste_lateral_pasajeros_anden_a: float = 0.0:
	set(v):
		ajuste_lateral_pasajeros_anden_a = v
		if is_inside_tree():
			_sincronizar_pasajeros_visuales()

@export_range(0.0, 1000.0, 0.01) var tasa_generacion_pasajeros: float = 0.375
## Limite de figuras visibles por estacion; el contador conserva la cantidad real.
@export_range(0, 150, 1) var maximo_pasajeros_visibles: int = 150
## Segundos que los pasajeros desembarcados permanecen visibles antes de salir.
@export_range(0.0, 60.0, 0.1) var tiempo_salida_pasajeros: float = 3.0

@export_group("Visualización")
## Permite ocultar andenes y postes genéricos sin ocultar el icono ni pasajeros.
@export var mostrar_estructura_andenes: bool = true:
	set(v):
		mostrar_estructura_andenes = v
		if is_inside_tree():
			_actualizar_visibilidad_estructura()

@export_group("Demanda por destino")
@export var demanda_pasajeros: DemandaEstacion:
	set(v):
		demanda_pasajeros = v
		_proximo_sorteo_demanda = 0.0
## El andén A sirve el recorrido actual Constitución -> Bosques.
@export_enum("A Constitución", "A Bosques", "Ambos") var destino_anden_a: int = DestinoAnden.BOSQUES
@export_enum("A Constitución", "A Bosques", "Ambos") var destino_anden_b: int = DestinoAnden.CONSTITUCION
@export_enum("A Constitución", "A Bosques", "Ambos") var destino_anden_central_1: int = DestinoAnden.AMBOS
@export_enum("A Constitución", "A Bosques", "Ambos") var destino_anden_central_2: int = DestinoAnden.AMBOS

var _andenes_pasajeros: Array[MeshInstance3D] = []
var _ids_andenes_pasajeros: Array[String] = []
var _capacidades_por_anden: Array[int] = []
var _esperando_por_anden: Array[int] = []
## X espera a Constitución; Y espera a Bosques. La capacidad es compartida.
var _esperando_por_destino: Array[Vector2i] = []
var _pendientes_por_anden: Array[Vector2] = []
var _demanda_por_ciclo: Vector2i = Vector2i.ZERO
var _proximo_sorteo_demanda: float = 0.0
var _cantidades_visibles_por_anden: Array[int] = []

## Totales para HUD y estadísticas; la población se almacena por andén.
var pasajeros_esperando: int:
	get:
		return _sumar_pasajeros(_esperando_por_anden)
	set(v):
		_repartir_pasajeros_esperando(maxi(0, v))
var ingreso_pasajeros_habilitado: bool = true
var pasajeros_saliendo: int = 0
var pasajeros_totales_historicos: int = 0
var pasajeros_subidos_total: int = 0
var pasajeros_bajados_total: int = 0
var _reloj_pasajeros: float = 0.0
var _reloj_simulacion: RelojSimulacion
var _salidas_pasajeros_pendientes: Array[Dictionary] = []
var _trenes_abordando: Dictionary = {}
var _colas_espera: Dictionary = {}
var _espera_completada_s: float = 0.0
var _pasajeros_espera_completada: int = 0
var _mallas_pasajeros: Array[Mesh] = []
var _transformaciones_mallas_pasajeros: Array[Transform3D] = []
var _bounds_mallas_pasajeros: Array[AABB] = []
var _multimeshes_pasajeros: Array[MultiMesh] = []

var _ajustando_transform: bool = false
var _transform_reciente: Transform3D = Transform3D.IDENTITY
var _ignorar_transform_reciente: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0
var _aviso_trenes_pendiente: bool = false
var _poste_ida: Node3D
var _poste_vuelta: Node3D
var _area_icono_informacion: Area3D
var _icono_informacion: Label3D


func _ready() -> void:
	_reloj_simulacion = get_parent().get_node_or_null("RelojSimulacion") as RelojSimulacion
	if not Engine.is_editor_hint():
		_ids_andenes_pasajeros.clear()
		_esperando_por_anden.clear()
		_esperando_por_destino.clear()
		pasajeros_saliendo = 0
		_pendientes_por_anden.clear()
		pasajeros_totales_historicos = 0
		pasajeros_subidos_total = 0
		pasajeros_bajados_total = 0
		_reloj_pasajeros = 0.0
		_proximo_sorteo_demanda = 0.0
		_salidas_pasajeros_pendientes.clear()
		_trenes_abordando.clear()
		_colas_espera.clear()
		_espera_completada_s = 0.0
		_pasajeros_espera_completada = 0
	_conectar_postes()
	_actualizar_dimensiones_anden()
	_actualizar_visibilidad_estructura()
	_actualizar_posicion_postes()
	_configurar_icono_informacion()
	if not Engine.is_editor_hint() and maximo_pasajeros_visibles > 0:
		_cargar_variantes_pasajeros()
		_crear_multimeshes_pasajeros()
	if Engine.is_editor_hint():
		set_process(true)
		if traza == null:
			_autodetectar_traza()
			if traza == null:
				call_deferred("_autodetectar_y_alinear")
			elif alinear_a_via:
				_aplicar_posicion_en_via()
	if _datos_originales.is_empty():
		_datos_originales = serializar_datos()


## Reintenta detectar una vía de la red y alinear (por si la red cargó después).
func _autodetectar_y_alinear() -> void:
	if traza != null or not is_inside_tree():
		return
	_autodetectar_traza()
	if traza != null and alinear_a_via:
		_aplicar_posicion_en_via()
		_notificar_trenes()


func _configurar_icono_informacion() -> void:
	var area: Area3D = get_node_or_null("AreaSeleccion") as Area3D
	if area != null and not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)
	_area_icono_informacion = get_node_or_null("AreaIconoInformacion") as Area3D
	if _area_icono_informacion == null:
		_area_icono_informacion = Area3D.new()
		_area_icono_informacion.name = "AreaIconoInformacion"
		_area_icono_informacion.collision_layer = 1
		_area_icono_informacion.collision_mask = 0
		_area_icono_informacion.input_ray_pickable = true
		var colision_icono := CollisionShape3D.new()
		colision_icono.name = "CollisionShape3D"
		var forma_icono := SphereShape3D.new()
		forma_icono.radius = 1.5
		colision_icono.shape = forma_icono
		_area_icono_informacion.add_child(colision_icono)
		add_child(_area_icono_informacion)
	if not _area_icono_informacion.input_event.is_connected(_on_area_input_event):
		_area_icono_informacion.input_event.connect(_on_area_input_event)
	if not pasajeros_actualizados.is_connected(_on_pasajeros_actualizados):
		pasajeros_actualizados.connect(_on_pasajeros_actualizados)
	_icono_informacion = get_node_or_null("IconoInformacion") as Label3D
	if _icono_informacion == null:
		_icono_informacion = Label3D.new()
		_icono_informacion.name = "IconoInformacion"
		add_child(_icono_informacion)
	_icono_informacion.text = "ℹ"
	_icono_informacion.position = Vector3(0.0, 30.0, 0.0)
	_icono_informacion.font_size = 192
	_icono_informacion.modulate = Color(0.2, 0.8, 1.0, 1.0)
	_icono_informacion.outline_size = 16
	_icono_informacion.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_area_icono_informacion.position = _icono_informacion.position
	_area_icono_informacion.scale = Vector3.ONE * ESCALA_ELEMENTOS_INFORMACION
	_icono_informacion.scale = Vector3.ONE * ESCALA_ELEMENTOS_INFORMACION
	_icono_informacion.visible = true
	_area_icono_informacion.input_ray_pickable = true


func _actualizar_visibilidad_estructura() -> void:
	for hijo: Node in get_children():
		if hijo is MeshInstance3D:
			(hijo as MeshInstance3D).visible = mostrar_estructura_andenes
		elif hijo is Node3D and (hijo.name == "AndenesCentrales" or String(hijo.name).begins_with("PosteParada")):
			(hijo as Node3D).visible = mostrar_estructura_andenes


func _on_area_input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		seleccionada.emit(self)


func _on_pasajeros_actualizados(_estacion: Estacion) -> void:
	_sincronizar_pasajeros_visuales()


func _cargar_variantes_pasajeros() -> void:
	if _variantes_pasajeros_cargadas:
		_mallas_pasajeros = _cache_mallas_pasajeros
		_transformaciones_mallas_pasajeros = _cache_transformaciones_mallas_pasajeros
		_bounds_mallas_pasajeros = _cache_bounds_mallas_pasajeros
		return

	var pack: Node3D = PACK_MODELOS_PASAJEROS.instantiate() as Node3D
	if pack == null:
		push_warning("No se pudo instanciar el pack de modelos de pasajeros.")
		_variantes_pasajeros_cargadas = true
		return
	pack.visible = false

	var grupo: Node = pack.find_child("SM_People_Lowpoly", true, false)
	if grupo == null:
		push_warning("No se encontro el grupo de modelos SM_People_Lowpoly en el GLB.")
		pack.free()
		_variantes_pasajeros_cargadas = true
		return

	for nombre_variante: String in NOMBRES_VARIANTES_PASAJERO:
		var variante: Node = grupo.get_node_or_null(nombre_variante)
		if variante == null:
			continue
		var nodos_malla: Array[Node] = variante.find_children("*", "MeshInstance3D", true, false)
		if nodos_malla.is_empty():
			continue
		var instancia_malla: MeshInstance3D = nodos_malla[0] as MeshInstance3D
		if instancia_malla == null or instancia_malla.mesh == null:
			continue

		var transformacion: Transform3D = Transform3D.IDENTITY
		var nodo_transformacion: Node = instancia_malla
		while nodo_transformacion != null and nodo_transformacion != pack:
			if nodo_transformacion is Node3D:
				transformacion = (nodo_transformacion as Node3D).transform * transformacion
			nodo_transformacion = nodo_transformacion.get_parent()
		var bounds: AABB = transformacion * instancia_malla.get_aabb()
		if bounds.size.y <= 0.0:
			continue
		_mallas_pasajeros.append(instancia_malla.mesh)
		_transformaciones_mallas_pasajeros.append(transformacion)
		_bounds_mallas_pasajeros.append(bounds)

	pack.free()
	_cache_mallas_pasajeros = _mallas_pasajeros
	_cache_transformaciones_mallas_pasajeros = _transformaciones_mallas_pasajeros
	_cache_bounds_mallas_pasajeros = _bounds_mallas_pasajeros
	_variantes_pasajeros_cargadas = true


func _crear_multimeshes_pasajeros() -> void:
	if _mallas_pasajeros.is_empty() or maximo_pasajeros_visibles <= 0:
		return

	for indice_variante: int in range(_mallas_pasajeros.size()):
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mallas_pasajeros[indice_variante]

		var nodo_multimesh: MultiMeshInstance3D = MultiMeshInstance3D.new()
		nodo_multimesh.name = "PasajerosMultimesh%02d" % indice_variante
		nodo_multimesh.multimesh = multimesh
		nodo_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(nodo_multimesh)
		_multimeshes_pasajeros.append(multimesh)
	_reubicar_pasajeros_visuales()


func _sincronizar_pasajeros_visuales() -> void:
	if _multimeshes_pasajeros.is_empty():
		return

	# Distribuir las figuras según el tamaño real de cada fila para que el límite
	# visual no haga parecer iguales andenes con cantidades distintas.
	var cantidades: Array[int] = []
	var disponibles: Array[int] = []
	var pesos: Array[int] = []
	var posiciones_por_anden: int = _posiciones_pasajeros_por_anden()
	var cantidad_andenes: int = maxi(1, _andenes_pasajeros.size())
	var total_disponible: int = 0
	for indice: int in range(_andenes_pasajeros.size()):
		cantidades.append(0)
		# La bajada es un contador general; solo la fila de espera pertenece al andén.
		var saliendo: int = int(pasajeros_saliendo / cantidad_andenes) + (1 if indice < pasajeros_saliendo % cantidad_andenes else 0)
		var poblacion: int = _esperando_por_anden[indice] + saliendo
		pesos.append(poblacion)
		var lugares_visibles: int = mini(poblacion, posiciones_por_anden)
		disponibles.append(lugares_visibles)
		total_disponible += lugares_visibles
	var restantes: int = mini(_limite_pasajeros_visibles(), total_disponible)
	while restantes > 0:
		var elegido: int = -1
		var mayor_prioridad: float = -1.0
		for indice: int in range(cantidades.size()):
			if cantidades[indice] >= disponibles[indice] or pesos[indice] <= 0:
				continue
			var prioridad: float = float(pesos[indice]) / float(cantidades[indice] + 1)
			if prioridad > mayor_prioridad:
				mayor_prioridad = prioridad
				elegido = indice
		if elegido < 0:
			break
		cantidades[elegido] += 1
		restantes -= 1
	if cantidades == _cantidades_visibles_por_anden:
		return
	_cantidades_visibles_por_anden = cantidades.duplicate()

	var cantidad_por_variante: Array[int] = []
	var bounds_por_variante: Array[AABB] = []
	for multimesh: MultiMesh in _multimeshes_pasajeros:
		cantidad_por_variante.append(0)
		bounds_por_variante.append(AABB())

	var indice_visual: int = 0
	for indice_anden: int in range(_andenes_pasajeros.size()):
		for puesto: int in range(cantidades[indice_anden]):
			var variante: int = indice_visual % _multimeshes_pasajeros.size()
			var multimesh: MultiMesh = _multimeshes_pasajeros[variante]
			var instancia: int = cantidad_por_variante[variante]
			var transformacion: Transform3D = _transformacion_pasajero_visual(
				_andenes_pasajeros[indice_anden], puesto, cantidades[indice_anden], variante
			)
			multimesh.set_instance_transform(instancia, transformacion)
			var bounds: AABB = transformacion * multimesh.mesh.get_aabb()
			bounds_por_variante[variante] = bounds if instancia == 0 else bounds_por_variante[variante].merge(bounds)
			cantidad_por_variante[variante] += 1
			indice_visual += 1

	for indice_variante: int in range(_multimeshes_pasajeros.size()):
		_multimeshes_pasajeros[indice_variante].custom_aabb = bounds_por_variante[indice_variante]
		_multimeshes_pasajeros[indice_variante].visible_instance_count = cantidad_por_variante[indice_variante]


func _obtener_andenes_pasajeros() -> Array[MeshInstance3D]:
	var andenes: Array[MeshInstance3D] = []
	var nombres: Array[String] = ["AndenA"]
	if incluir_anden_b_pasajeros:
		nombres.append("AndenB")
	for nombre: String in nombres:
		var anden: MeshInstance3D = get_node_or_null(nombre) as MeshInstance3D
		if anden != null and anden.mesh != null and not anden.is_queued_for_deletion():
			andenes.append(anden)
	for indice: int in range(cantidad_andenes_centrales):
		var ruta: String = "AndenesCentrales/Central%d/Anden" % (indice + 1)
		var anden: MeshInstance3D = get_node_or_null(ruta) as MeshInstance3D
		if anden != null and anden.mesh != null and not anden.is_queued_for_deletion():
			andenes.append(anden)
	return andenes


func _configurar_pasajeros_por_anden() -> void:
	var andenes: Array[MeshInstance3D] = _obtener_andenes_pasajeros()
	var ids: Array[String] = []
	var capacidades: Array[int] = []
	var esperando: Array[int] = []
	var por_destino: Array[Vector2i] = []
	var pendientes: Array[Vector2] = []
	var cantidad: int = andenes.size()
	for indice: int in range(cantidad):
		var id: String = str(get_path_to(andenes[indice]))
		var capacidad: int = int(capacidad_maxima_espera / cantidad)
		if indice < capacidad_maxima_espera % cantidad:
			capacidad += 1
		var anterior: int = _ids_andenes_pasajeros.find(id)
		ids.append(id)
		capacidades.append(capacidad)
		var fila: Vector2i = _esperando_por_destino[anterior] if anterior >= 0 else Vector2i.ZERO
		var total: int = fila.x + fila.y
		if total > capacidad:
			var a_constitucion: int = roundi(float(capacidad) * float(fila.x) / float(total))
			fila = Vector2i(a_constitucion, capacidad - a_constitucion)
		esperando.append(fila.x + fila.y)
		por_destino.append(fila)
		pendientes.append(_pendientes_por_anden[anterior] if anterior >= 0 else Vector2.ZERO)
	_andenes_pasajeros = andenes
	_ids_andenes_pasajeros = ids
	_capacidades_por_anden = capacidades
	_esperando_por_anden = esperando
	_esperando_por_destino = por_destino
	_pendientes_por_anden = pendientes
	_sincronizar_colas_espera()


func _sincronizar_colas_espera() -> void:
	for id: String in _colas_espera.keys():
		if id not in _ids_andenes_pasajeros:
			_colas_espera.erase(id)
	for indice: int in _ids_andenes_pasajeros.size():
		var id: String = _ids_andenes_pasajeros[indice]
		if not _colas_espera.has(id):
			_colas_espera[id] = [ColaEsperaPasajeros.new(), ColaEsperaPasajeros.new()]
		var colas: Array = _colas_espera[id]
		(colas[0] as ColaEsperaPasajeros).ajustar_cantidad(_esperando_por_destino[indice].x, _reloj_pasajeros)
		(colas[1] as ColaEsperaPasajeros).ajustar_cantidad(_esperando_por_destino[indice].y, _reloj_pasajeros)


func obtener_metricas_espera() -> Dictionary:
	var espera_actual: float = 0.0
	for colas: Array in _colas_espera.values():
		for cola: ColaEsperaPasajeros in colas:
			espera_actual += cola.espera_acumulada_actual(_reloj_pasajeros)
	return {
		"espera_total_completada_s": _espera_completada_s,
		"pasajeros_con_espera": _pasajeros_espera_completada,
		"espera_promedio_s": _espera_completada_s / _pasajeros_espera_completada if _pasajeros_espera_completada > 0 else 0.0,
		"espera_actual_total_s": espera_actual,
		"espera_promedio_actual_s": espera_actual / pasajeros_esperando if pasajeros_esperando > 0 else 0.0,
	}


## Reinicia el contador actual de la estación al producirse un embarque real.
## Conserva las esperas históricas de quienes ya subieron.
func reiniciar_contador_espera_actual() -> void:
	for colas: Array in _colas_espera.values():
		for cola: ColaEsperaPasajeros in colas:
			cola.reiniciar_espera_actual(_reloj_pasajeros)
	pasajeros_actualizados.emit(self)


func _sumar_pasajeros(cantidades: Array[int]) -> int:
	var total: int = 0
	for cantidad: int in cantidades:
		total += cantidad
	return total


## Conserva la asignación del total usada por herramientas y reparte la demanda.
func _repartir_pasajeros_esperando(cantidad: int) -> void:
	var andenes: int = _esperando_por_anden.size()
	if andenes == 0:
		return
	var total: int = mini(cantidad, _sumar_pasajeros(_capacidades_por_anden))
	for indice: int in range(andenes):
		_esperando_por_anden[indice] = int(total / andenes) + (1 if indice < total % andenes else 0)
		_esperando_por_destino[indice] = _repartir_por_destino(_esperando_por_anden[indice], _ids_andenes_pasajeros[indice])
	_sincronizar_colas_espera()
	if is_inside_tree():
		pasajeros_actualizados.emit(self)


func obtener_pasajeros_por_anden() -> Array[int]:
	var resultado: Array[int] = []
	for pasajeros: int in _esperando_por_anden:
		resultado.append(pasajeros)
	return resultado


## Límites globales de los andenes que muestran pasajeros, incluidos los
## ajustes visuales de las terminales, para encuadrar la estación desde el HUD.
func obtener_limites_andenes_pasajeros() -> AABB:
	var limites: AABB = AABB(global_position, Vector3.ZERO)
	var primero: bool = true
	var anden_a: MeshInstance3D = get_node_or_null("AndenA") as MeshInstance3D
	for anden: MeshInstance3D in _obtener_andenes_pasajeros():
		var transformacion: Transform3D = anden.global_transform
		if anden == anden_a:
			transformacion.origin += transformacion.basis * Vector3(
				0.0, desfasaje_vertical_pasajeros_anden_a, ajuste_lateral_pasajeros_anden_a
			)
		var bounds: AABB = transformacion * anden.mesh.get_aabb()
		limites = bounds if primero else limites.merge(bounds)
		primero = false
	return limites


func registrar_abordaje_tren(id_tren: int, activo: bool) -> void:
	var habia_abordaje: bool = not _trenes_abordando.is_empty()
	if activo:
		_trenes_abordando[id_tren] = true
	else:
		_trenes_abordando.erase(id_tren)
	var hay_abordaje: bool = not _trenes_abordando.is_empty()
	if habia_abordaje != hay_abordaje:
		abordaje_cambiado.emit(hay_abordaje)


func hay_tren_abordando() -> bool:
	return not _trenes_abordando.is_empty()


func _destino_del_anden(id_anden: String) -> int:
	match id_anden:
		"AndenA":
			return destino_anden_a
		"AndenB":
			return destino_anden_b
		"AndenesCentrales/Central1/Anden":
			return destino_anden_central_1
		"AndenesCentrales/Central2/Anden":
			return destino_anden_central_2
	return DestinoAnden.AMBOS


func _repartir_por_destino(cantidad: int, id_anden: String) -> Vector2i:
	var destino: int = _destino_del_anden(id_anden)
	if destino == DestinoAnden.CONSTITUCION:
		return Vector2i(cantidad, 0)
	if destino == DestinoAnden.BOSQUES:
		return Vector2i(0, cantidad)
	var proporcion: float = 0.5
	if demanda_pasajeros != null:
		var total: int = demanda_pasajeros.suben_a_constitucion + demanda_pasajeros.suben_a_bosques
		if total > 0:
			proporcion = float(demanda_pasajeros.suben_a_constitucion) / float(total)
	var a_constitucion: int = roundi(float(cantidad) * proporcion)
	return Vector2i(a_constitucion, cantidad - a_constitucion)


func calcular_bajada_pasajeros(hacia_constitucion: bool) -> int:
	return demanda_pasajeros.sortear_bajada(hacia_constitucion, _hora_simulada_actual()) if demanda_pasajeros != null else -1


func _hora_simulada_actual() -> int:
	return int(_reloj_simulacion.fecha_hora_simulada().get("hora", 12)) if is_instance_valid(_reloj_simulacion) else 12


## Selecciona la superficie junto a la vía; el sentido desempata entre laterales.
func resolver_anden_pasajeros(punto_via: Vector3, sentido_ida: bool = true) -> String:
	var elegido: int = -1
	var mejor_distancia: float = INF
	var preferido: String = "AndenA" if sentido_ida else "AndenB"
	for indice: int in range(_andenes_pasajeros.size()):
		var anden: MeshInstance3D = _andenes_pasajeros[indice]
		var bounds: AABB = anden.mesh.get_aabb()
		var punto: Vector3 = anden.to_local(punto_via)
		var cercano: Vector3 = Vector3(
			clampf(punto.x, bounds.position.x, bounds.end.x),
			punto.y,
			clampf(punto.z, bounds.position.z, bounds.end.z)
		)
		var distancia: float = anden.to_global(cercano).distance_squared_to(punto_via)
		if distancia < mejor_distancia - 0.001 or (absf(distancia - mejor_distancia) <= 0.001 and _ids_andenes_pasajeros[indice] == preferido):
			mejor_distancia = distancia
			elegido = indice
	return _ids_andenes_pasajeros[elegido] if elegido >= 0 else ""


func _posiciones_pasajeros_por_anden() -> int:
	var largo_util: float = maxf(0.0, longitud_anden * 0.9)
	return maxi(1, int(floor(largo_util / 1.2)) + 1)


func _limite_pasajeros_visibles() -> int:
	return mini(maxi(0, maximo_pasajeros_visibles), _posiciones_pasajeros_por_anden() * _andenes_pasajeros.size())


func _transformacion_pasajero_visual(anden: MeshInstance3D, puesto: int, cantidad_por_anden: int, indice_variante: int) -> Transform3D:
	# Los andenes centrales están anidados: incluir la transformada de sus padres.
	var transformacion_anden: Transform3D = anden.transform
	var ancestro: Node = anden.get_parent()
	while ancestro != null and ancestro != self:
		if ancestro is Node3D:
			transformacion_anden = (ancestro as Node3D).transform * transformacion_anden
		ancestro = ancestro.get_parent()
	var bounds_anden: AABB = anden.mesh.get_aabb()
	var margen: float = minf(5.0, bounds_anden.size.x * 0.05)
	var largo_util: float = maxf(0.0, bounds_anden.size.x - margen * 2.0)
	var separacion: float = 8.0
	if cantidad_por_anden > 1:
		separacion = clampf(largo_util / float(cantidad_por_anden - 1), 1.2, 8.0)
	var anillo: int = int(ceil(float(puesto) / 2.0))
	var direccion: float = -1.0 if puesto % 2 == 1 else 1.0
	var x: float = clampf(float(anillo) * separacion * direccion, -largo_util * 0.5, largo_util * 0.5)
	# El andén ya incorpora la separación y los ajustes laterales del Inspector.
	var centro_anden: Vector3 = bounds_anden.get_center()
	var ajuste_vertical: float = desfasaje_vertical_pasajeros_anden_a if anden == get_node_or_null("AndenA") else 0.0
	var ajuste_lateral: float = ajuste_lateral_pasajeros_anden_a if anden == get_node_or_null("AndenA") else 0.0
	var posicion_local: Vector3 = Vector3(centro_anden.x + x, bounds_anden.end.y + 0.02 + ajuste_vertical, centro_anden.z + ajuste_lateral)
	var posicion: Vector3 = transformacion_anden * posicion_local

	var bounds: AABB = _bounds_mallas_pasajeros[indice_variante]
	var transformacion_modelo: Transform3D = _transformaciones_mallas_pasajeros[indice_variante]
	var centro: Vector3 = bounds.get_center()
	transformacion_modelo.origin -= Vector3(centro.x, bounds.position.y, centro.z)
	var escala: float = 1.65 / bounds.size.y
	var transformacion_raiz: Transform3D = Transform3D(transformacion_anden.basis.orthonormalized().scaled(Vector3.ONE * escala), posicion)
	return transformacion_raiz * transformacion_modelo


func _reubicar_pasajeros_visuales() -> void:
	if _multimeshes_pasajeros.is_empty():
		return

	var capacidad_visual: int = _limite_pasajeros_visibles()
	var instancias_por_variante: int = int(ceil(float(capacidad_visual) / float(_multimeshes_pasajeros.size())))
	for multimesh: MultiMesh in _multimeshes_pasajeros:
		multimesh.instance_count = instancias_por_variante
		multimesh.visible_instance_count = 0
		multimesh.custom_aabb = AABB()
	_cantidades_visibles_por_anden.clear()
	_sincronizar_pasajeros_visuales()



func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_reloj_pasajeros += _delta
		_actualizar_pasajeros_saliendo()
		_generar_pasajeros(_delta)
		return
	if not alinear_a_via or not _pendiente_snap:
		return

	var clic_izq: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var tiempo_pasado: int = Time.get_ticks_msec() - _tiempo_ultimo_movimiento

	# Cuando el usuario suelta el mouse tras arrastrar, o tras detener el movimiento
	if not clic_izq and tiempo_pasado > 60:
		_pendiente_snap = false
		_snap_a_posicion_actual()


func _generar_pasajeros(delta: float) -> void:
	if not ingreso_pasajeros_habilitado or not activa or _andenes_pasajeros.is_empty():
		return
	if demanda_pasajeros == null and tasa_generacion_pasajeros <= 0.0:
		return

	var tasas: Vector2 = Vector2.ZERO
	var andenes_constitucion: int = 0
	var andenes_bosques: int = 0
	for id_anden: String in _ids_andenes_pasajeros:
		var destino: int = _destino_del_anden(id_anden)
		if destino != DestinoAnden.BOSQUES:
			andenes_constitucion += 1
		if destino != DestinoAnden.CONSTITUCION:
			andenes_bosques += 1
	if demanda_pasajeros != null:
		var intervalo: float = maxf(0.1, demanda_pasajeros.intervalo_formaciones)
		if _reloj_pasajeros >= _proximo_sorteo_demanda:
			var hora: int = _hora_simulada_actual()
			_demanda_por_ciclo = Vector2i(demanda_pasajeros.sortear_generacion(true, hora), demanda_pasajeros.sortear_generacion(false, hora))
			_proximo_sorteo_demanda = _reloj_pasajeros + minf(intervalo, 60.0)
		tasas = Vector2(_demanda_por_ciclo) / intervalo
		tasas.x /= float(maxi(1, andenes_constitucion))
		tasas.y /= float(maxi(1, andenes_bosques))
	var tasa_por_anden: float = tasa_generacion_pasajeros / float(_andenes_pasajeros.size())
	var generados: int = 0
	for indice: int in range(_andenes_pasajeros.size()):
		var lugar: int = maxi(0, _capacidades_por_anden[indice] - _esperando_por_anden[indice])
		if lugar <= 0:
			_pendientes_por_anden[indice] = Vector2.ZERO
			continue
		var destino: int = _destino_del_anden(_ids_andenes_pasajeros[indice])
		var tasa: Vector2 = tasas
		if demanda_pasajeros == null:
			tasa = Vector2.ONE * tasa_por_anden * 0.5 if destino == DestinoAnden.AMBOS else Vector2.ONE * tasa_por_anden
		if destino == DestinoAnden.CONSTITUCION:
			tasa.y = 0.0
		elif destino == DestinoAnden.BOSQUES:
			tasa.x = 0.0
		var pendientes: Vector2 = _pendientes_por_anden[indice] + tasa * delta
		var posibles: Vector2i = Vector2i(floori(pendientes.x), floori(pendientes.y))
		var total: int = posibles.x + posibles.y
		if total <= 0:
			_pendientes_por_anden[indice] = pendientes
			continue
		var nuevos: int = mini(total, lugar)
		var a_constitucion: int = clampi(roundi(float(nuevos) * float(posibles.x) / float(total)), maxi(0, nuevos - posibles.y), mini(nuevos, posibles.x))
		var reparto: Vector2i = Vector2i(a_constitucion, nuevos - a_constitucion)
		_esperando_por_destino[indice] += reparto
		_esperando_por_anden[indice] += nuevos
		var colas: Array = _colas_espera[_ids_andenes_pasajeros[indice]]
		(colas[0] as ColaEsperaPasajeros).agregar(reparto.x, _reloj_pasajeros)
		(colas[1] as ColaEsperaPasajeros).agregar(reparto.y, _reloj_pasajeros)
		_pendientes_por_anden[indice] = Vector2.ZERO if nuevos == lugar else pendientes - Vector2(reparto)
		generados += nuevos
	if generados > 0:
		pasajeros_totales_historicos += generados
		pasajeros_actualizados.emit(self)


## Cierra o habilita el ingreso de pasajeros a la estación.
func establecer_ingreso_pasajeros_habilitado(habilitado: bool) -> void:
	if ingreso_pasajeros_habilitado == habilitado:
		return
	ingreso_pasajeros_habilitado = habilitado
	if not habilitado:
		_pendientes_por_anden.fill(Vector2.ZERO)
	ingreso_pasajeros_cambiado.emit(habilitado)


## Registra pasajeros que bajan. Se muestran temporalmente en la estación,
## pero no pasan a la fila de quienes esperan para subir.
func desembarcar_pasajeros(cantidad: int) -> int:
	var pasajeros: int = maxi(0, cantidad)
	if pasajeros <= 0:
		return 0
	if tiempo_salida_pasajeros > 0.0:
		pasajeros_saliendo += pasajeros
		_salidas_pasajeros_pendientes.append({
			"vence_en": _reloj_pasajeros + tiempo_salida_pasajeros,
			"cantidad": pasajeros,
		})
	pasajeros_bajados_total += pasajeros
	pasajeros_actualizados.emit(self)
	return pasajeros


func _actualizar_pasajeros_saliendo() -> void:
	var desaparecieron: int = 0
	while not _salidas_pasajeros_pendientes.is_empty():
		var salida: Dictionary = _salidas_pasajeros_pendientes[0]
		if float(salida["vence_en"]) > _reloj_pasajeros:
			break
		desaparecieron += int(salida["cantidad"])
		_salidas_pasajeros_pendientes.pop_front()

	if desaparecieron <= 0:
		return
	pasajeros_saliendo = maxi(0, pasajeros_saliendo - desaparecieron)
	pasajeros_actualizados.emit(self)


## Embarca pasajeros inmediatamente. Puede llamarse con cantidad=1 desde un escalonador.
func embarcar_pasajeros(cantidad: int, id_anden: String = "", hacia_constitucion: bool = false) -> int:
	var indice: int = _ids_andenes_pasajeros.find(id_anden) if not id_anden.is_empty() else 0
	if indice < 0 or indice >= _esperando_por_anden.size():
		return 0
	var fila: Vector2i = _esperando_por_destino[indice]
	var disponibles: int = fila.x if hacia_constitucion else fila.y
	var pasajeros: int = mini(maxi(0, cantidad), disponibles)
	if pasajeros <= 0:
		return 0
	_esperando_por_anden[indice] -= pasajeros
	var colas: Array = _colas_espera[_ids_andenes_pasajeros[indice]]
	var cola: ColaEsperaPasajeros = colas[0 if hacia_constitucion else 1] as ColaEsperaPasajeros
	_espera_completada_s += cola.retirar(pasajeros, _reloj_pasajeros)
	_pasajeros_espera_completada += pasajeros
	if hacia_constitucion:
		fila.x -= pasajeros
	else:
		fila.y -= pasajeros
	_esperando_por_destino[indice] = fila
	pasajeros_subidos_total += pasajeros
	pasajeros_actualizados.emit(self)
	return pasajeros


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_POST_ENTER_TREE:
			add_to_group("estaciones")
			set_notify_transform(true)
			_conectar_postes()
			_actualizar_dimensiones_anden()
			_actualizar_posicion_postes()
			if traza == null:
				_autodetectar_traza()
			if traza != null and is_instance_valid(traza) and traza.curve != null:
				if not traza.curve.changed.is_connected(_on_curva_cambiada):
					traza.curve.changed.connect(_on_curva_cambiada)
			if alinear_a_via and traza != null:
				_aplicar_posicion_en_via()
			_notificar_trenes()

		NOTIFICATION_TRANSFORM_CHANGED:
			if _ajustando_transform:
				return
			# Ignorar la notificación generada por nuestro propio ajuste (es diferida).
			if _ignorar_transform_reciente:
				_ignorar_transform_reciente = false
				if global_transform.is_equal_approx(_transform_reciente):
					return
			transformada_cambiada.emit(self)
			if Engine.is_editor_hint():
				esta_editada = true
			if alinear_a_via and traza != null and is_instance_valid(traza) and traza.curve != null and Engine.is_editor_hint():
				_pendiente_snap = true
				_tiempo_ultimo_movimiento = Time.get_ticks_msec()
			else:
				_notificar_trenes()

		NOTIFICATION_EXIT_TREE:
			if is_in_group("estaciones"):
				remove_from_group("estaciones")
			if traza != null and is_instance_valid(traza) and traza.curve != null:
				if traza.curve.changed.is_connected(_on_curva_cambiada):
					traza.curve.changed.disconnect(_on_curva_cambiada)
			_notificar_trenes()


func _conectar_postes() -> void:
	_poste_ida = get_node_or_null("PosteParadaIda") as Node3D
	_poste_vuelta = get_node_or_null("PosteParadaVuelta") as Node3D

	if _poste_ida != null:
		if _poste_ida.has_signal("posicion_cambiada") and not _poste_ida.posicion_cambiada.is_connected(_on_poste_posicion_cambiada):
			_poste_ida.posicion_cambiada.connect(_on_poste_posicion_cambiada)
	if _poste_vuelta != null:
		if _poste_vuelta.has_signal("posicion_cambiada") and not _poste_vuelta.posicion_cambiada.is_connected(_on_poste_posicion_cambiada):
			_poste_vuelta.posicion_cambiada.connect(_on_poste_posicion_cambiada)


func _on_poste_posicion_cambiada(poste: Node3D) -> void:
	if poste == _poste_ida:
		desfasaje_parada_ida = snappedf(poste.position.x, 0.1)
	elif poste == _poste_vuelta:
		desfasaje_parada_vuelta = snappedf(poste.position.x, 0.1)
	_notificar_trenes()


func _actualizar_posicion_postes() -> void:
	if _poste_ida == null or _poste_vuelta == null:
		_conectar_postes()
	if _poste_ida != null and is_instance_valid(_poste_ida):
		if _poste_ida.has_method("fijar_posicion_x"):
			_poste_ida.fijar_posicion_x(desfasaje_parada_ida)
		else:
			_poste_ida.position.x = desfasaje_parada_ida
	if _poste_vuelta != null and is_instance_valid(_poste_vuelta):
		if _poste_vuelta.has_method("fijar_posicion_x"):
			_poste_vuelta.fijar_posicion_x(desfasaje_parada_vuelta)
		else:
			_poste_vuelta.position.x = desfasaje_parada_vuelta


func _actualizar_dimensiones_anden() -> void:
	for anden_nombre: String in ["AndenA", "AndenB"]:
		var anden: MeshInstance3D = get_node_or_null(anden_nombre) as MeshInstance3D
		if anden != null and anden.mesh is BoxMesh:
			var bm: BoxMesh = anden.mesh.duplicate() as BoxMesh
			bm.size = Vector3(longitud_anden, bm.size.y, bm.size.z)
			anden.mesh = bm

	for marq_nombre: String in ["MarquesinaA", "MarquesinaB"]:
		var marq: MeshInstance3D = get_node_or_null(marq_nombre) as MeshInstance3D
		if marq != null and marq.mesh is BoxMesh:
			var bm: BoxMesh = marq.mesh.duplicate() as BoxMesh
			bm.size = Vector3(longitud_anden, bm.size.y, bm.size.z)
			marq.mesh = bm

	for prefijo: String in ["ColumnaA", "ColumnaB"]:
		var c0: Node3D = get_node_or_null(prefijo + "0") as Node3D
		var c1: Node3D = get_node_or_null(prefijo + "1") as Node3D
		var c2: Node3D = get_node_or_null(prefijo + "2") as Node3D
		var c3: Node3D = get_node_or_null(prefijo + "3") as Node3D
		var c4: Node3D = get_node_or_null(prefijo + "4") as Node3D
		if c0: c0.position.x = -longitud_anden * 0.4
		if c1: c1.position.x = -longitud_anden * 0.2
		if c2: c2.position.x = 0.0
		if c3: c3.position.x = longitud_anden * 0.2
		if c4: c4.position.x = longitud_anden * 0.4

	_actualizar_disposicion_transversal()


func _actualizar_disposicion_transversal() -> void:
	var mitad_separacion: float = separacion_vias * 0.5
	for sufijo: String in ["A", "B"]:
		var lado: float = -1.0 if sufijo == "A" else 1.0
		var ajuste_lateral: float = ajuste_lateral_anden_ida if sufijo == "A" else ajuste_lateral_anden_vuelta
		var z_anden: float = lado * mitad_separacion + ajuste_lateral
		for prefijo: String in ["Anden", "Marquesina"]:
			var pieza: Node3D = get_node_or_null(prefijo + sufijo) as Node3D
			if pieza != null:
				pieza.position.z = z_anden
		for i: int in range(5):
			var columna: Node3D = get_node_or_null("Columna" + sufijo + str(i)) as Node3D
			if columna != null:
				columna.position.z = z_anden

	# Los postes quedan a la misma distancia del borde interior que en el diseño original.
	if _poste_ida != null:
		_poste_ida.position.z = -mitad_separacion + 1.75 + ajuste_lateral_anden_ida
	if _poste_vuelta != null:
		_poste_vuelta.position.z = mitad_separacion - 1.75 + ajuste_lateral_anden_vuelta
	_sincronizar_andenes_centrales()
	_actualizar_area_seleccion()
	_configurar_pasajeros_por_anden()
	_reubicar_pasajeros_visuales()


## Construye hasta dos andenes isla visuales. Son nodos generados por la
## configuración, por lo que no se guardan como hijos permanentes de la escena:
## al abrirla se reconstruyen desde las propiedades exportadas del Inspector.
func _sincronizar_andenes_centrales() -> void:
	var contenedor: Node3D = get_node_or_null("AndenesCentrales") as Node3D
	if cantidad_andenes_centrales <= 0:
		if contenedor != null:
			contenedor.queue_free()
		return

	if contenedor == null:
		contenedor = Node3D.new()
		contenedor.name = "AndenesCentrales"
		add_child(contenedor)

	for indice: int in range(cantidad_andenes_centrales):
		var nombre_central: String = "Central%d" % (indice + 1)
		var central: Node3D = contenedor.get_node_or_null(nombre_central) as Node3D
		if central == null:
			central = Node3D.new()
			central.name = nombre_central
			contenedor.add_child(central)
			_crear_modelo_anden_central(central)
		central.position.z = _posicion_lateral_anden_central(indice)
		_actualizar_dimensiones_anden_central(central)

	for hijo: Node in contenedor.get_children():
		var nombre_hijo: String = String(hijo.name)
		if hijo is Node3D and nombre_hijo.begins_with("Central"):
			var indice_texto: String = nombre_hijo.trim_prefix("Central")
			if indice_texto.is_valid_int() and indice_texto.to_int() > cantidad_andenes_centrales:
				hijo.queue_free()


func _posicion_lateral_anden_central(indice: int) -> float:
	return posicion_lateral_anden_central_1 if indice == 0 else posicion_lateral_anden_central_2


func _crear_modelo_anden_central(central: Node3D) -> void:
	var fuentes: Array[String] = ["AndenA", "MarquesinaA", "ColumnaA0", "ColumnaA1", "ColumnaA2", "ColumnaA3", "ColumnaA4"]
	var destinos: Array[String] = ["Anden", "Marquesina", "Columna0", "Columna1", "Columna2", "Columna3", "Columna4"]
	for indice: int in range(fuentes.size()):
		var fuente: Node3D = get_node_or_null(fuentes[indice]) as Node3D
		if fuente == null:
			continue
		var copia: Node3D = fuente.duplicate() as Node3D
		if copia == null:
			continue
		copia.name = destinos[indice]
		copia.position.z = 0.0
		central.add_child(copia)


func _actualizar_dimensiones_anden_central(central: Node3D) -> void:
	for nombre_malla: String in ["Anden", "Marquesina"]:
		var pieza: MeshInstance3D = central.get_node_or_null(nombre_malla) as MeshInstance3D
		if pieza != null and pieza.mesh is BoxMesh:
			var caja: BoxMesh = pieza.mesh.duplicate() as BoxMesh
			caja.size = Vector3(longitud_anden, caja.size.y, caja.size.z)
			pieza.mesh = caja
	for indice: int in range(5):
		var columna: Node3D = central.get_node_or_null("Columna%d" % indice) as Node3D
		if columna != null:
			columna.position.x = longitud_anden * (float(indice) - 2.0) * 0.2


## Amplía el volumen de clic según los andenes laterales y centrales visibles.
## De esta forma una estación sigue siendo seleccionable aunque sus modelos se
## alejen del ancho inicial de la escena.
func _actualizar_area_seleccion() -> void:
	var colision: CollisionShape3D = get_node_or_null("AreaSeleccion/CollisionShape3D") as CollisionShape3D
	if colision == null:
		return
	var caja: BoxShape3D = colision.shape as BoxShape3D
	if caja == null:
		return
	var mitad: float = separacion_vias * 0.5
	var posiciones: Array[float] = [-mitad + ajuste_lateral_anden_ida]
	if incluir_anden_b_pasajeros:
		posiciones.append(mitad + ajuste_lateral_anden_vuelta)
	if cantidad_andenes_centrales >= 1:
		posiciones.append(posicion_lateral_anden_central_1)
	if cantidad_andenes_centrales >= 2:
		posiciones.append(posicion_lateral_anden_central_2)
	var minimo: float = posiciones[0]
	var maximo: float = posiciones[0]
	for posicion: float in posiciones:
		minimo = minf(minimo, posicion)
		maximo = maxf(maximo, posicion)
	var margen_lateral: float = 2.75
	var caja_local: BoxShape3D = caja.duplicate() as BoxShape3D
	caja_local.size = Vector3(maxf(longitud_anden, 1.0), 8.0, maxf(5.0, maximo - minimo + margen_lateral * 2.0))
	colision.shape = caja_local
	colision.position.z = (minimo + maximo) * 0.5


## Calcula y devuelve el offset exacto a lo largo de la curva de la vía donde debe detenerse
## la cabina del tren, proyectando la posición 3D real del poste correspondiente.
func obtener_offset_parada(sentido_ida: bool) -> float:
	var usar_ida: bool = sentido_ida or not incluir_anden_b_pasajeros
	var poste: Node3D = _poste_ida if usar_ida else _poste_vuelta
	if poste == null:
		_conectar_postes()
		poste = _poste_ida if usar_ida else _poste_vuelta

	if poste != null and is_instance_valid(poste) and traza != null and is_instance_valid(traza) and traza.curve != null:
		var pos_local: Vector3 = traza.to_local(poste.global_position)
		return snappedf(traza.curve.get_closest_offset(pos_local), 0.01)

	# Fallback si no está el nodo del poste
	var desfasaje: float = desfasaje_parada_ida if usar_ida else desfasaje_parada_vuelta
	if invertir_sentido:
		desfasaje = -desfasaje
	return snappedf(progreso_en_via + desfasaje, 0.01)


## Devuelve las vías paralelas que cruzan el área física de la estación y el
## punto de frenado obtenido al proyectar el poste correspondiente sobre cada
## una. La traza de referencia sólo ubica el andén; no limita el servicio.
func obtener_puntos_parada_multivia(red: Node, sentido_ida: bool) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	if red == null or not ("paths" in red):
		return resultado
	_conectar_postes()
	var poste: Node3D = _poste_ida if sentido_ida or not incluir_anden_b_pasajeros else _poste_vuelta
	if poste == null or not is_instance_valid(poste):
		return resultado
	var paths_var: Variant = red.get("paths")
	if not (paths_var is Dictionary):
		return resultado
	var paths: Dictionary = paths_var as Dictionary
	if sentido_ida and usar_traza_como_via_ida:
		if traza == null or traza.curve == null or traza.curve.point_count < 2 or not paths.values().has(traza):
			return resultado
		var offset_asignado: float = snappedf(traza.curve.get_closest_offset(traza.to_local(poste.global_position)), 0.01)
		resultado.append({
			"segmento": String(traza.name),
			"traza": traza,
			"offset": offset_asignado,
			"offset_ida": offset_asignado,
			"offset_vuelta": offset_asignado,
			"punto_global": traza.to_global(traza.curve.sample_baked(offset_asignado, true)),
		})
		return resultado
	var eje_estacion: Vector3 = global_transform.basis.x.normalized()
	var mitad_largo: float = longitud_anden * 0.5 + 3.0
	var mitad_ancho: float = ancho_cobertura_vias * 0.5

	for segmento: String in paths.keys():
		var via: Path3D = paths[segmento] as Path3D
		if via == null or via.curve == null or via.curve.point_count < 2:
			continue
		var offset: float = via.curve.get_closest_offset(via.to_local(poste.global_position))
		var punto_global: Vector3 = via.to_global(via.curve.sample_baked(offset, true))
		var punto_estacion: Vector3 = to_local(punto_global)
		if absf(punto_estacion.x) > mitad_largo or absf(punto_estacion.z) > mitad_ancho:
			continue
		if punto_global.distance_to(poste.global_position) > mitad_ancho + 3.0:
			continue
		var muestra: Transform3D = via.curve.sample_baked_with_rotation(offset, true, true)
		var eje_via: Vector3 = (via.global_transform.basis * -muestra.basis.z).normalized()
		if absf(eje_via.dot(eje_estacion)) < 0.7:
			continue
		resultado.append({
			"segmento": segmento,
			"traza": via,
			"offset": snappedf(offset, 0.01),
			"offset_ida": snappedf(offset, 0.01),
			"offset_vuelta": snappedf(offset, 0.01),
			"punto_global": punto_global,
		})
	return resultado


## Indica si el poste correspondiente al sentido de marcha actúa como cabecera.
func es_terminal_en_sentido(sentido_ida: bool) -> bool:
	return terminal_parada_ida if sentido_ida else terminal_parada_vuelta


func _on_curva_cambiada() -> void:
	if is_inside_tree() and alinear_a_via:
		_aplicar_posicion_en_via()


func _autodetectar_traza() -> void:
	if get_parent() is Path3D:
		traza = get_parent()
		return

	var p: Node = get_parent()
	if p != null:
		var encontrada: Path3D = p.find_child("Traza", true, false) as Path3D
		if encontrada != null:
			traza = encontrada
			return
		if p.get_parent() != null:
			encontrada = p.get_parent().find_child("Traza", true, false) as Path3D
			if encontrada != null:
				traza = encontrada
				return

	# Red topológica (TrackNetwork): tomar un tramo troncal como vía inicial.
	traza = _segmento_inicial_de_red()


## Red ferroviaria (TrackNetwork) que contiene la traza, si existe.
func _obtener_red() -> Node:
	if traza != null and is_instance_valid(traza):
		var c: Node = traza.get_parent()
		while c != null:
			if c.has_method("get_closest_segment"):
				return c
			c = c.get_parent()
	if is_inside_tree():
		return get_tree().get_first_node_in_group("track_network")
	return null


## Primer segmento disponible de la red topológica (prefiere un troncal conocido).
func _segmento_inicial_de_red() -> Path3D:
	if not is_inside_tree():
		return null
	var red: Node = get_tree().get_first_node_in_group("track_network")
	if red == null:
		var raiz: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if raiz != null:
			red = raiz.find_child("TrackNetwork", true, false)
	if red == null or not ("paths" in red):
		return null
	var paths_v: Variant = red.get("paths")
	if not (paths_v is Dictionary):
		return null
	var dicc: Dictionary = paths_v as Dictionary
	for id_cand: String in ["seg_470", "seg_471", "seg_1", "seg_179"]:
		if dicc.has(id_cand) and dicc[id_cand] is Path3D:
			return dicc[id_cand] as Path3D
	for v: Variant in dicc.values():
		if v is Path3D and (v as Path3D).curve != null and (v as Path3D).curve.point_count >= 2:
			return v as Path3D
	return null


## Proyecta la posición 3D actual de la estación sobre la vía y la imanta a ella.
## Si pertenece a una red, busca la vía MÁS CERCANA de toda la red y se cambia a ella.
##
## Clave: el progreso se calcula desde la posición SOLTADA por el usuario sobre la vía
## destino ANTES de cambiar `traza` (si se cambiaba primero, el setter reposicionaba la
## estación y el cálculo se hacía sobre esa posición ya movida -> lugar incorrecto).
func _snap_a_posicion_actual() -> void:
	if traza == null:
		_autodetectar_traza()

	# Posición global donde el usuario soltó la estación.
	var objetivo_global: Vector3 = global_position

	var vía_destino: Path3D = traza
	var red: Node = _obtener_red()
	if red != null and red.has_method("get_closest_segment") and red.has_method("get_segment_path"):
		var seg_id: String = str(red.call("get_closest_segment", objetivo_global))
		if not seg_id.is_empty():
			var p: Path3D = red.call("get_segment_path", seg_id) as Path3D
			if p != null and p.curve != null and p.curve.point_count >= 2:
				vía_destino = p

	if vía_destino == null or not is_instance_valid(vía_destino) or vía_destino.curve == null or vía_destino.curve.point_count < 2:
		return

	# Calcular el progreso en la vía destino a partir de la posición soltada.
	var pos_local: Vector3 = vía_destino.to_local(objetivo_global)
	var nuevo_progreso: float = snappedf(vía_destino.curve.get_closest_offset(pos_local), 0.1)

	# La estación siempre termina tangente a la vía, pero el giro manual de
	# 180° sí tiene significado operativo: define qué extremo visual es Ida.
	# Leerlo antes de reemplazar el transform evita que el autoalineado lo
	# descarte al soltar el manipulador.
	# Asignar con bloqueo para que los setters no reposicionen a mitad de camino.
	_ajustando_transform = true
	_actualizar_sentido_desde_orientacion(vía_destino, nuevo_progreso)
	traza = vía_destino
	progreso_en_via = nuevo_progreso
	_ajustando_transform = false
	_aplicar_posicion_en_via()


## Interpreta el eje longitudinal que dejó el usuario en el editor. Sólo se
## conserva la elección de sentido (normal o invertido); la orientación final
## vuelve a calcularse desde la curva para que andén, cobertura y postes sigan
## correctamente anclados a la vía.
func _actualizar_sentido_desde_orientacion(vía: Path3D, offset: float) -> void:
	if not Engine.is_editor_hint() or vía == null or vía.curve == null:
		return

	var muestra: Transform3D = vía.curve.sample_baked_with_rotation(offset, true, true)
	var tangente_local: Vector3 = -muestra.basis.z.normalized()
	var tangente_global: Vector3 = (vía.global_transform.basis * tangente_local).normalized()
	var eje_longitudinal: Vector3 = global_transform.basis.x.normalized()
	if tangente_global.length_squared() <= 0.0001 or eje_longitudinal.length_squared() <= 0.0001:
		return

	# Con un giro de 180° el producto escalar pasa a ser negativo. Para giros
	# intermedios se conserva el último sentido, evitando que una edición leve
	# cerca de 90° altere de manera inesperada el poste operativo.
	var alineacion: float = eje_longitudinal.dot(tangente_global)
	if absf(alineacion) >= 0.5:
		invertir_sentido = alineacion < 0.0


## Posiciona y orienta tangencialmente la estación según el progreso_en_via en la traza.
func _aplicar_posicion_en_via() -> void:
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	_ajustando_transform = true

	var largo: float = traza.curve.get_baked_length()
	var d: float = clampf(progreso_en_via, 0.0, largo)

	# sample_baked_with_rotation devuelve una Transform3D donde -Z es la tangente y +Y es el vector UP
	var t: Transform3D = traza.curve.sample_baked_with_rotation(d, true, true)
	var tangent: Vector3 = -t.basis.z.normalized()
	if invertir_sentido:
		tangent = -tangent

	var up: Vector3 = t.basis.y.normalized()
	var lateral: Vector3 = tangent.cross(up).normalized()

	# Los andenes de la estación se extienden a lo largo del eje X local
	var nueva_basis: Basis = Basis(tangent, up, lateral).orthonormalized()
	var nuevo_origen: Vector3 = t.origin + up * desfasaje_vertical + lateral * desfasaje_lateral

	global_transform = traza.global_transform * Transform3D(nueva_basis, nuevo_origen)

	# La notificación de transform llega diferida: registrar el transform propio para
	# ignorarla y no re-disparar el snap (provocaba que la estación se moviera sola).
	_transform_reciente = global_transform
	_ignorar_transform_reciente = true
	_ajustando_transform = false
	_notificar_trenes()


func _notificar_trenes() -> void:
	# Editar una estación no debe ejecutar búsquedas topológicas para cada tren.
	# El editor sólo modifica la escena; las rutas se resolverán al iniciar el juego.
	if Engine.is_editor_hint() or not is_inside_tree() or _aviso_trenes_pendiente:
		return
	_aviso_trenes_pendiente = true
	call_deferred("_notificar_trenes_diferido")


## Agrupa cambios consecutivos de una estación en una única actualización de
## itinerario por tren. Por ejemplo, modificar separación y ambos ajustes en el
## Inspector no genera tres recálculos de ruta en el mismo frame.
func _notificar_trenes_diferido() -> void:
	_aviso_trenes_pendiente = false
	if not is_inside_tree():
		return
	var trenes: Array[Node] = get_tree().get_nodes_in_group("trenes")
	for t: Node in trenes:
		if is_instance_valid(t) and t.has_method("_recalcular_paradas_dinamicas"):
			t.call("_recalcular_paradas_dinamicas")


# ==============================================================================
# PERSISTENCIA Y EDICIÓN (misma mecánica que EditableTrackSegment)
# ==============================================================================

## Clave única de esta estación en el journal de la red.
func obtener_id_edicion() -> String:
	return id_edicion if not id_edicion.is_empty() else String(name)


## Serializa la posición/ajustes de la estación a un diccionario persistible.
func serializar_datos() -> Dictionary:
	var b: Basis = global_transform.basis
	var o: Vector3 = global_transform.origin
	return {
		"segment_id": traza.name if (traza != null and is_instance_valid(traza)) else "",
		"alinear_a_via": alinear_a_via,
		"progreso_en_via": progreso_en_via,
		"invertir_sentido": invertir_sentido,
		"desfasaje_vertical": desfasaje_vertical,
		"desfasaje_lateral": desfasaje_lateral,
		"longitud_anden": longitud_anden,
		"separacion_vias": separacion_vias,
		"ajuste_lateral_anden_ida": ajuste_lateral_anden_ida,
		"ajuste_lateral_anden_vuelta": ajuste_lateral_anden_vuelta,
		"cantidad_andenes_centrales": cantidad_andenes_centrales,
		"posicion_lateral_anden_central_1": posicion_lateral_anden_central_1,
		"posicion_lateral_anden_central_2": posicion_lateral_anden_central_2,
		"ancho_cobertura_vias": ancho_cobertura_vias,
		"usar_traza_como_via_ida": usar_traza_como_via_ida,
		"desfasaje_parada_ida": desfasaje_parada_ida,
		"desfasaje_parada_vuelta": desfasaje_parada_vuelta,
		"nombre_estacion": nombre_estacion,
		"es_terminal": es_terminal,
		"terminal_parada_ida": terminal_parada_ida,
		"terminal_parada_vuelta": terminal_parada_vuelta,
		"tiempo_espera": tiempo_espera,
		"activa": activa,
		"capacidad_maxima_espera": capacidad_maxima_espera,
		"incluir_anden_b_pasajeros": incluir_anden_b_pasajeros,
		"desfasaje_vertical_pasajeros_anden_a": desfasaje_vertical_pasajeros_anden_a,
		"ajuste_lateral_pasajeros_anden_a": ajuste_lateral_pasajeros_anden_a,
		"tasa_generacion_pasajeros": tasa_generacion_pasajeros,
		"maximo_pasajeros_visibles": maximo_pasajeros_visibles,
		"tiempo_salida_pasajeros": tiempo_salida_pasajeros,
		"mostrar_estructura_andenes": mostrar_estructura_andenes,
		"demanda_pasajeros": demanda_pasajeros.resource_path if demanda_pasajeros != null else "",
		"destino_anden_a": destino_anden_a,
		"destino_anden_b": destino_anden_b,
		"destino_anden_central_1": destino_anden_central_1,
		"destino_anden_central_2": destino_anden_central_2,
		"transform": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]
	}


## Aplica datos guardados a la estación (posición en la red y ajustes).
func deserializar_datos(data: Dictionary) -> void:
	_ajustando_transform = true
	_autodetectar_traza_segun_datos(str(data.get("segment_id", "")))
	alinear_a_via = bool(data.get("alinear_a_via", alinear_a_via))
	progreso_en_via = float(data.get("progreso_en_via", progreso_en_via))
	invertir_sentido = bool(data.get("invertir_sentido", invertir_sentido))
	desfasaje_vertical = float(data.get("desfasaje_vertical", desfasaje_vertical))
	desfasaje_lateral = float(data.get("desfasaje_lateral", desfasaje_lateral))
	longitud_anden = maxf(30.0, float(data.get("longitud_anden", longitud_anden)))
	separacion_vias = maxf(2.0, float(data.get("separacion_vias", separacion_vias)))
	ajuste_lateral_anden_ida = float(data.get("ajuste_lateral_anden_ida", ajuste_lateral_anden_ida))
	ajuste_lateral_anden_vuelta = float(data.get("ajuste_lateral_anden_vuelta", ajuste_lateral_anden_vuelta))
	cantidad_andenes_centrales = int(data.get("cantidad_andenes_centrales", cantidad_andenes_centrales))
	posicion_lateral_anden_central_1 = float(data.get("posicion_lateral_anden_central_1", posicion_lateral_anden_central_1))
	posicion_lateral_anden_central_2 = float(data.get("posicion_lateral_anden_central_2", posicion_lateral_anden_central_2))
	ancho_cobertura_vias = maxf(5.0, float(data.get("ancho_cobertura_vias", ancho_cobertura_vias)))
	usar_traza_como_via_ida = bool(data.get("usar_traza_como_via_ida", usar_traza_como_via_ida))
	desfasaje_parada_ida = float(data.get("desfasaje_parada_ida", desfasaje_parada_ida))
	desfasaje_parada_vuelta = float(data.get("desfasaje_parada_vuelta", desfasaje_parada_vuelta))
	nombre_estacion = str(data.get("nombre_estacion", nombre_estacion))
	if data.has("terminal_parada_ida") or data.has("terminal_parada_vuelta"):
		terminal_parada_ida = bool(data.get("terminal_parada_ida", false))
		terminal_parada_vuelta = bool(data.get("terminal_parada_vuelta", false))
	else:
		es_terminal = bool(data.get("es_terminal", es_terminal))
	tiempo_espera = maxf(0.0, float(data.get("tiempo_espera", tiempo_espera)))
	activa = bool(data.get("activa", activa))
	capacidad_maxima_espera = int(data.get("capacidad_maxima_espera", capacidad_maxima_espera))
	incluir_anden_b_pasajeros = bool(data.get("incluir_anden_b_pasajeros", incluir_anden_b_pasajeros))
	desfasaje_vertical_pasajeros_anden_a = float(data.get("desfasaje_vertical_pasajeros_anden_a", desfasaje_vertical_pasajeros_anden_a))
	ajuste_lateral_pasajeros_anden_a = float(data.get("ajuste_lateral_pasajeros_anden_a", ajuste_lateral_pasajeros_anden_a))
	tasa_generacion_pasajeros = float(data.get("tasa_generacion_pasajeros", tasa_generacion_pasajeros))
	maximo_pasajeros_visibles = int(data.get("maximo_pasajeros_visibles", maximo_pasajeros_visibles))
	tiempo_salida_pasajeros = float(data.get("tiempo_salida_pasajeros", tiempo_salida_pasajeros))
	mostrar_estructura_andenes = bool(data.get("mostrar_estructura_andenes", mostrar_estructura_andenes))
	var ruta_demanda: String = str(data.get("demanda_pasajeros", ""))
	if not ruta_demanda.is_empty() and ResourceLoader.exists(ruta_demanda):
		demanda_pasajeros = load(ruta_demanda) as DemandaEstacion
	destino_anden_a = int(data.get("destino_anden_a", destino_anden_a))
	destino_anden_b = int(data.get("destino_anden_b", destino_anden_b))
	destino_anden_central_1 = int(data.get("destino_anden_central_1", destino_anden_central_1))
	destino_anden_central_2 = int(data.get("destino_anden_central_2", destino_anden_central_2))
	var valores_transform: Array = data.get("transform", []) as Array
	if valores_transform.size() == 12:
		global_transform = Transform3D(
			Basis(
				Vector3(float(valores_transform[0]), float(valores_transform[1]), float(valores_transform[2])),
				Vector3(float(valores_transform[3]), float(valores_transform[4]), float(valores_transform[5])),
				Vector3(float(valores_transform[6]), float(valores_transform[7]), float(valores_transform[8]))
			),
			Vector3(float(valores_transform[9]), float(valores_transform[10]), float(valores_transform[11]))
		)
	_ajustando_transform = false
	_actualizar_dimensiones_anden()
	_actualizar_posicion_postes()
	_actualizar_disposicion_transversal()
	if traza != null and alinear_a_via:
		_aplicar_posicion_en_via()
	esta_editada = true
	_notificar_trenes()


func _autodetectar_traza_segun_datos(segment_id: String) -> void:
	if segment_id.is_empty():
		return
	var red: Node = _obtener_red()
	if red != null and red.has_method("get_segment_path"):
		var p: Path3D = red.call("get_segment_path", segment_id) as Path3D
		if p != null and p.curve != null:
			traza = p


## Guarda la edición de esta estación en el journal de la red.
func guardar_edicion() -> void:
	esta_editada = true
	var red: Node = _obtener_red()
	if red != null and red.has_method("guardar_edicion_estacion"):
		red.call("guardar_edicion_estacion", self)
		edicion_guardada.emit(self)
		print("Estacion: edición guardada para '%s'." % obtener_id_edicion())
	else:
		push_warning("Estacion: no se encontró TrackNetwork para persistir la edición.")


## Restaura la estación a su estado original (el capturado al cargar la escena).
func resetear_a_original() -> void:
	if not _datos_originales.is_empty():
		deserializar_datos(_datos_originales)
	esta_editada = false
	var red: Node = _obtener_red()
	if red != null and red.has_method("descartar_edicion_estacion"):
		red.call("descartar_edicion_estacion", obtener_id_edicion())
	reseteada.emit(self)
	print("Estacion: '%s' restaurada a su estado original." % obtener_id_edicion())
