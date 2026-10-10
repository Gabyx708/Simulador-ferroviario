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

@export_range(0.0, 1000.0, 0.1) var tasa_generacion_pasajeros: float = 1.5
## Limite de figuras visibles por estacion; el contador conserva la cantidad real.
@export_range(0, 150, 1) var maximo_pasajeros_visibles: int = 150
## Segundos que los pasajeros desembarcados permanecen visibles antes de salir.
@export_range(0.0, 60.0, 0.1) var tiempo_salida_pasajeros: float = 3.0

var pasajeros_esperando: int = 0
var pasajeros_saliendo: int = 0
var pasajeros_totales_historicos: int = 0
var pasajeros_subidos_total: int = 0
var pasajeros_bajados_total: int = 0
var _pasajeros_pendientes: float = 0.0
var _reloj_pasajeros: float = 0.0
var _salidas_pasajeros_pendientes: Array[Dictionary] = []
var _mallas_pasajeros: Array[Mesh] = []
var _transformaciones_mallas_pasajeros: Array[Transform3D] = []
var _bounds_mallas_pasajeros: Array[AABB] = []
var _multimeshes_pasajeros: Array[MultiMesh] = []

var _ajustando_transform: bool = false
var _transform_reciente: Transform3D = Transform3D.IDENTITY
var _ignorar_transform_reciente: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0
var _poste_ida: Node3D
var _poste_vuelta: Node3D
var _area_icono_informacion: Area3D
var _cartel_informacion: Label3D
var _fondo_cartel: MeshInstance3D
var _icono_informacion: Label3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		pasajeros_esperando = 0
		pasajeros_saliendo = 0
		pasajeros_totales_historicos = 0
		pasajeros_subidos_total = 0
		pasajeros_bajados_total = 0
		_pasajeros_pendientes = 0.0
		_reloj_pasajeros = 0.0
		_salidas_pasajeros_pendientes.clear()
	_conectar_postes()
	_actualizar_dimensiones_anden()
	_actualizar_posicion_postes()
	_configurar_cartel_informacion()
	if not Engine.is_editor_hint() and maximo_pasajeros_visibles > 0:
		_cargar_variantes_pasajeros()
		_crear_multimeshes_pasajeros()
	_actualizar_cartel_informacion()
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


func _configurar_cartel_informacion() -> void:
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
	_cartel_informacion = get_node_or_null("CartelInformacion") as Label3D
	if _cartel_informacion == null:
		_cartel_informacion = Label3D.new()
		_cartel_informacion.name = "CartelInformacion"
		_fondo_cartel = MeshInstance3D.new()
		_fondo_cartel.name = "FondoCartelInformacion"
		_fondo_cartel.position = Vector3(0.0, 0.0, 0.15)
		var fondo_malla := QuadMesh.new()
		fondo_malla.size = Vector2(90.0, 30.0)
		var fondo_material := StandardMaterial3D.new()
		fondo_material.albedo_color = Color(0.0, 0.0, 0.0, 0.9)
		fondo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fondo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fondo_material.render_priority = -1
		fondo_malla.material = fondo_material
		_fondo_cartel.mesh = fondo_malla
		_cartel_informacion.add_child(_fondo_cartel)
		add_child(_cartel_informacion)
	_cartel_informacion.position = Vector3(0.0, 30.0, 0.0)
	_cartel_informacion.font_size = 320
	_cartel_informacion.modulate = Color(1.0, 0.9, 0.2, 1.0)
	_cartel_informacion.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cartel_informacion.scale = Vector3.ONE
	_cartel_informacion.outline_size = 60
	if _fondo_cartel == null:
		_fondo_cartel = _cartel_informacion.get_node_or_null("FondoCartelInformacion") as MeshInstance3D
	if _fondo_cartel != null:
		var fondo_malla_existente: QuadMesh = _fondo_cartel.mesh as QuadMesh
		if fondo_malla_existente != null:
			fondo_malla_existente.size = Vector2(90.0, 30.0)
	_cartel_informacion.visible = false
	_icono_informacion.visible = true
	_area_icono_informacion.input_ray_pickable = true


func _on_area_input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _cartel_informacion == null:
			_configurar_cartel_informacion()
		var mostrar_cartel: bool = not _cartel_informacion.visible
		_cartel_informacion.visible = mostrar_cartel
		_icono_informacion.visible = not mostrar_cartel
		_area_icono_informacion.input_ray_pickable = not mostrar_cartel
		get_viewport().set_input_as_handled()
		_actualizar_cartel_informacion()


func _actualizar_cartel_informacion() -> void:
	if _cartel_informacion == null:
		return
	var presentes: int = pasajeros_esperando + pasajeros_saliendo
	_cartel_informacion.text = "%s\nEn estación: %d / %d\nHistórico: %d\nSubieron: %d  Bajaron: %d" % [nombre_estacion, presentes, capacidad_maxima_espera, pasajeros_totales_historicos, pasajeros_subidos_total, pasajeros_bajados_total]


func _on_pasajeros_actualizados(_estacion: Estacion) -> void:
	_actualizar_cartel_informacion()
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
		multimesh.custom_aabb = _aabb_multimesh_pasajeros()

		var nodo_multimesh: MultiMeshInstance3D = MultiMeshInstance3D.new()
		nodo_multimesh.name = "PasajerosMultimesh%02d" % indice_variante
		nodo_multimesh.multimesh = multimesh
		nodo_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(nodo_multimesh)
		_multimeshes_pasajeros.append(multimesh)
	_reubicar_pasajeros_visuales()


func _aabb_multimesh_pasajeros() -> AABB:
	return AABB(
		Vector3(-longitud_anden * 0.5 - 2.0, 0.0, -6.0),
		Vector3(longitud_anden + 4.0, 3.0, 12.0)
	)


func _sincronizar_pasajeros_visuales() -> void:
	if _multimeshes_pasajeros.is_empty():
		return

	var presentes: int = pasajeros_esperando + pasajeros_saliendo
	var cantidad_objetivo: int = mini(maxi(0, presentes), _limite_pasajeros_visibles())
	var cantidad_por_variante: Array[int] = []
	for multimesh: MultiMesh in _multimeshes_pasajeros:
		cantidad_por_variante.append(0)

	for indice: int in range(cantidad_objetivo):
		cantidad_por_variante[indice % _multimeshes_pasajeros.size()] += 1

	for indice_variante: int in range(_multimeshes_pasajeros.size()):
		_multimeshes_pasajeros[indice_variante].visible_instance_count = cantidad_por_variante[indice_variante]


func _limite_pasajeros_visibles() -> int:
	var largo_util: float = maxf(0.0, longitud_anden * 0.9)
	var posiciones_por_anden: int = maxi(1, int(floor(largo_util / 1.2)) + 1)
	return mini(maxi(0, maximo_pasajeros_visibles), posiciones_por_anden * 2)


func _transformacion_pasajero_visual(indice: int, cantidad_total: int) -> Transform3D:
	var cantidad_por_anden: int = maxi(1, int(ceil(float(cantidad_total) / 2.0)))
	var puesto: int = int(indice / 2)
	var margen: float = minf(5.0, longitud_anden * 0.05)
	var largo_util: float = maxf(0.0, longitud_anden - margen * 2.0)
	var separacion: float = 8.0
	if cantidad_por_anden > 1:
		separacion = clampf(largo_util / float(cantidad_por_anden - 1), 1.2, 8.0)
	var anillo: int = int(ceil(float(puesto) / 2.0))
	var direccion: float = -1.0 if puesto % 2 == 1 else 1.0
	var x: float = float(anillo) * separacion * direccion
	var z: float = -3.75 if indice % 2 == 0 else 3.75
	var posicion: Vector3 = Vector3(x, 0.52, z)

	var indice_variante: int = indice % _mallas_pasajeros.size()
	var bounds: AABB = _bounds_mallas_pasajeros[indice_variante]
	var transformacion_modelo: Transform3D = _transformaciones_mallas_pasajeros[indice_variante]
	var centro: Vector3 = bounds.get_center()
	transformacion_modelo.origin -= Vector3(centro.x, bounds.position.y, centro.z)
	var escala: float = 1.65 / bounds.size.y
	var transformacion_raiz: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * escala), posicion)
	return transformacion_raiz * transformacion_modelo


func _reubicar_pasajeros_visuales() -> void:
	if _multimeshes_pasajeros.is_empty():
		return

	var capacidad_visual: int = _limite_pasajeros_visibles()
	var instancias_por_variante: int = int(ceil(float(capacidad_visual) / float(_multimeshes_pasajeros.size())))
	var cantidad_por_variante: Array[int] = []
	for multimesh: MultiMesh in _multimeshes_pasajeros:
		multimesh.instance_count = instancias_por_variante
		multimesh.visible_instance_count = 0
		multimesh.custom_aabb = _aabb_multimesh_pasajeros()
		cantidad_por_variante.append(0)

	for indice: int in range(capacidad_visual):
		var indice_variante: int = indice % _multimeshes_pasajeros.size()
		var indice_instancia: int = cantidad_por_variante[indice_variante]
		_multimeshes_pasajeros[indice_variante].set_instance_transform(
			indice_instancia,
			_transformacion_pasajero_visual(indice, capacidad_visual)
		)
		cantidad_por_variante[indice_variante] += 1

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
	if not activa or pasajeros_esperando >= capacidad_maxima_espera or tasa_generacion_pasajeros <= 0.0:
		return

	_pasajeros_pendientes += tasa_generacion_pasajeros * delta
	var nuevos: int = mini(int(floor(_pasajeros_pendientes)), capacidad_maxima_espera - pasajeros_esperando)
	if nuevos <= 0:
		return

	_pasajeros_pendientes -= nuevos
	pasajeros_esperando += nuevos
	pasajeros_totales_historicos += nuevos
	pasajeros_actualizados.emit(self)


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
func embarcar_pasajeros(cantidad: int) -> int:
	var pasajeros: int = mini(maxi(0, cantidad), pasajeros_esperando)
	if pasajeros <= 0:
		return 0
	pasajeros_esperando -= pasajeros
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
		var z_anden: float = lado * mitad_separacion
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
		_poste_ida.position.z = -mitad_separacion + 1.75
	if _poste_vuelta != null:
		_poste_vuelta.position.z = mitad_separacion - 1.75
	for multimesh: MultiMesh in _multimeshes_pasajeros:
		multimesh.custom_aabb = _aabb_multimesh_pasajeros()
	_reubicar_pasajeros_visuales()


## Calcula y devuelve el offset exacto a lo largo de la curva de la vía donde debe detenerse
## la cabina del tren, proyectando la posición 3D real del poste correspondiente.
func obtener_offset_parada(sentido_ida: bool) -> float:
	var poste: Node3D = _poste_ida if sentido_ida else _poste_vuelta
	if poste == null:
		_conectar_postes()
		poste = _poste_ida if sentido_ida else _poste_vuelta

	if poste != null and is_instance_valid(poste) and traza != null and is_instance_valid(traza) and traza.curve != null:
		var pos_local: Vector3 = traza.to_local(poste.global_position)
		return snappedf(traza.curve.get_closest_offset(pos_local), 0.01)

	# Fallback si no está el nodo del poste
	var desfasaje: float = desfasaje_parada_ida if sentido_ida else desfasaje_parada_vuelta
	if invertir_sentido:
		desfasaje = -desfasaje
	return snappedf(progreso_en_via + desfasaje, 0.01)


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

	# Asignar con bloqueo para que los setters no reposicionen a mitad de camino.
	_ajustando_transform = true
	traza = vía_destino
	progreso_en_via = nuevo_progreso
	_ajustando_transform = false
	_aplicar_posicion_en_via()


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
	if not is_inside_tree():
		return
	var trenes: Array[Node] = get_tree().get_nodes_in_group("trenes")
	for t: Node in trenes:
		if is_instance_valid(t) and t.has_method("_recalcular_paradas_dinamicas"):
			t.call_deferred("_recalcular_paradas_dinamicas")


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
		"progreso_en_via": progreso_en_via,
		"invertir_sentido": invertir_sentido,
		"desfasaje_vertical": desfasaje_vertical,
		"desfasaje_lateral": desfasaje_lateral,
		"longitud_anden": longitud_anden,
		"separacion_vias": separacion_vias,
		"desfasaje_parada_ida": desfasaje_parada_ida,
		"desfasaje_parada_vuelta": desfasaje_parada_vuelta,
		"nombre_estacion": nombre_estacion,
		"es_terminal": es_terminal,
		"terminal_parada_ida": terminal_parada_ida,
		"terminal_parada_vuelta": terminal_parada_vuelta,
		"tiempo_espera": tiempo_espera,
		"activa": activa,
		"transform": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]
	}


## Aplica datos guardados a la estación (posición en la red y ajustes).
func deserializar_datos(data: Dictionary) -> void:
	_ajustando_transform = true
	_autodetectar_traza_segun_datos(str(data.get("segment_id", "")))
	progreso_en_via = float(data.get("progreso_en_via", progreso_en_via))
	invertir_sentido = bool(data.get("invertir_sentido", invertir_sentido))
	desfasaje_vertical = float(data.get("desfasaje_vertical", desfasaje_vertical))
	desfasaje_lateral = float(data.get("desfasaje_lateral", desfasaje_lateral))
	longitud_anden = maxf(30.0, float(data.get("longitud_anden", longitud_anden)))
	separacion_vias = maxf(2.0, float(data.get("separacion_vias", separacion_vias)))
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
