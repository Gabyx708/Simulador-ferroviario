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
signal pasajeros_actualizados(estacion: Estacion)

const PACK_MODELOS_PASAJEROS: PackedScene = preload("res://assets/models/passengers/free_pack_-_lowpoly_people.glb")
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
		if is_inside_tree() and alinear_a_via:
			_aplicar_posicion_en_via()

## Si está activo, la estación se bloquea y orienta sobre la geometría del Path3D según progreso_en_via.
@export var alinear_a_via: bool = true:
	set(v):
		var se_acaba_de_activar: bool = not alinear_a_via and v
		alinear_a_via = v
		if is_inside_tree() and alinear_a_via:
			if se_acaba_de_activar:
				_snap_a_posicion_actual()
			else:
				_aplicar_posicion_en_via()

## Distancia en metros a lo largo de la curva donde se ubica el centro de la estación.
@export_range(0.0, 10000.0, 0.5, "or_greater") var progreso_en_via: float = 0.0:
	set(v):
		progreso_en_via = maxf(0.0, v)
		if is_inside_tree() and alinear_a_via:
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
		if is_inside_tree() and alinear_a_via:
			_aplicar_posicion_en_via()

## Ajuste de altura sobre el plano de rodadura del riel (en metros).
@export var desfasaje_vertical: float = 0.0:
	set(v):
		desfasaje_vertical = v
		if is_inside_tree() and alinear_a_via:
			_aplicar_posicion_en_via()

## Desplazamiento lateral perpendicular al riel (en metros).
@export var desfasaje_lateral: float = 0.0:
	set(v):
		desfasaje_lateral = v
		if is_inside_tree() and alinear_a_via:
			_aplicar_posicion_en_via()

@export_group("Dimensiones de Andén")
## Longitud total del andén en metros (200 m para formaciones completas de 7/8 coches).
@export_range(30.0, 500.0, 5.0) var longitud_anden: float = 200.0:
	set(v):
		longitud_anden = maxf(30.0, v)
		if is_inside_tree():
			_actualizar_dimensiones_anden()
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

## Si está activo, indica que esta estación es cabecera / parada final de recorrido.
## El tren que arribe aquí invertirá automáticamente su sentido de marcha para el viaje de regreso.
@export var es_terminal: bool = false:
	set(v):
		es_terminal = v
		_notificar_trenes()

@export var tiempo_espera: float = 20.0:
	set(v):
		tiempo_espera = maxf(0.0, v)
		_notificar_trenes()

@export var activa: bool = true:
	set(v):
		activa = v
		_notificar_trenes()

@export_group("Pasajeros")
@export_range(0, 100000, 1) var capacidad_maxima_espera: int = 150:
	set(v):
		capacidad_maxima_espera = maxi(0, v)

@export_range(0.0, 1000.0, 0.1) var tasa_generacion_pasajeros: float = 1.5
## Limite de figuras visibles por estacion; el contador conserva la cantidad real.
@export_range(0, 150, 1) var maximo_pasajeros_visibles: int = 150

var pasajeros_esperando: int = 0
var pasajeros_totales_historicos: int = 0
var pasajeros_subidos_total: int = 0
var pasajeros_bajados_total: int = 0
var _pasajeros_pendientes: float = 0.0
var _mallas_pasajeros: Array[Mesh] = []
var _transformaciones_mallas_pasajeros: Array[Transform3D] = []
var _bounds_mallas_pasajeros: Array[AABB] = []
var _multimeshes_pasajeros: Array[MultiMesh] = []

var _ajustando_transform: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0
var _poste_ida: Node3D
var _poste_vuelta: Node3D
var _cartel_informacion: Label3D
var _fondo_cartel: MeshInstance3D
var _icono_informacion: Label3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		pasajeros_esperando = 0
		pasajeros_totales_historicos = 0
		pasajeros_subidos_total = 0
		pasajeros_bajados_total = 0
		_pasajeros_pendientes = 0.0
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


func _configurar_cartel_informacion() -> void:
	var area: Area3D = get_node_or_null("AreaSeleccion") as Area3D
	if area != null and not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)
	if not pasajeros_actualizados.is_connected(_on_pasajeros_actualizados):
		pasajeros_actualizados.connect(_on_pasajeros_actualizados)
	_icono_informacion = get_node_or_null("IconoInformacion") as Label3D
	if _icono_informacion == null:
		_icono_informacion = Label3D.new()
		_icono_informacion.name = "IconoInformacion"
		_icono_informacion.text = "i"
		_icono_informacion.position = Vector3(0.0, 11.0, 0.0)
		_icono_informacion.font_size = 48
		_icono_informacion.modulate = Color(0.2, 0.8, 1.0, 1.0)
		_icono_informacion.outline_size = 8
		_icono_informacion.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_icono_informacion)
	_cartel_informacion = get_node_or_null("CartelInformacion") as Label3D
	if _cartel_informacion == null:
		_cartel_informacion = Label3D.new()
		_cartel_informacion.name = "CartelInformacion"
		_cartel_informacion.position = Vector3(0.0, 8.0, 0.0)
		_cartel_informacion.font_size = 32
		_cartel_informacion.modulate = Color(1.0, 0.9, 0.2, 1.0)
		_cartel_informacion.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_cartel_informacion.outline_size = 8
		_fondo_cartel = MeshInstance3D.new()
		_fondo_cartel.name = "FondoCartelInformacion"
		_fondo_cartel.position = Vector3(0.0, 0.0, 0.15)
		var fondo_malla := QuadMesh.new()
		fondo_malla.size = Vector2(9.0, 3.2)
		var fondo_material := StandardMaterial3D.new()
		fondo_material.albedo_color = Color(0.0, 0.0, 0.0, 0.9)
		fondo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fondo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fondo_material.render_priority = -1
		fondo_malla.material = fondo_material
		_fondo_cartel.mesh = fondo_malla
		_cartel_informacion.add_child(_fondo_cartel)
		add_child(_cartel_informacion)
	_cartel_informacion.visible = false


func _on_area_input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _cartel_informacion == null:
			_configurar_cartel_informacion()
		_cartel_informacion.visible = not _cartel_informacion.visible
		_actualizar_cartel_informacion()


func _actualizar_cartel_informacion() -> void:
	if _cartel_informacion == null:
		return
	_cartel_informacion.text = "%s\nEsperando: %d / %d\nHistórico: %d\nSubieron: %d  Bajaron: %d" % [nombre_estacion, pasajeros_esperando, capacidad_maxima_espera, pasajeros_totales_historicos, pasajeros_subidos_total, pasajeros_bajados_total]


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

	var cantidad_objetivo: int = mini(maxi(0, pasajeros_esperando), _limite_pasajeros_visibles())
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


## Desembarca pasajeros inmediatamente. Puede llamarse con cantidad=1 desde un escalonador.
func desembarcar_pasajeros(cantidad: int) -> int:
	var espacio_disponible: int = maxi(0, capacidad_maxima_espera - pasajeros_esperando)
	var pasajeros: int = mini(maxi(0, cantidad), espacio_disponible)
	if pasajeros <= 0:
		return 0
	pasajeros_esperando += pasajeros
	pasajeros_bajados_total += pasajeros
	pasajeros_actualizados.emit(self)
	return pasajeros


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
			transformada_cambiada.emit(self)
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


## Proyecta la posición 3D actual de la estación sobre la curva de la vía y la imanta a ella.
func _snap_a_posicion_actual() -> void:
	if traza == null:
		_autodetectar_traza()
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	var pos_local: Vector3 = traza.to_local(global_position)
	progreso_en_via = snappedf(traza.curve.get_closest_offset(pos_local), 0.1)
	_aplicar_posicion_en_via()


## Posiciona y orienta tangencialmente la estación según el progreso_en_via en la traza.
func _aplicar_posicion_en_via() -> void:
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	_ajustando_transform = true

	# sample_baked_with_rotation devuelve una Transform3D donde -Z es la tangente y +Y es el vector UP
	var t: Transform3D = traza.curve.sample_baked_with_rotation(progreso_en_via, true, true)
	var tangent: Vector3 = -t.basis.z.normalized()
	if invertir_sentido:
		tangent = -tangent

	var up: Vector3 = t.basis.y.normalized()
	var lateral: Vector3 = tangent.cross(up).normalized()

	# Los andenes de la estación se extienden a lo largo del eje X local
	var nueva_basis: Basis = Basis(tangent, up, lateral).orthonormalized()
	var nuevo_origen: Vector3 = t.origin + up * desfasaje_vertical + lateral * desfasaje_lateral

	global_transform = traza.global_transform * Transform3D(nueva_basis, nuevo_origen)

	_ajustando_transform = false
	_notificar_trenes()


func _notificar_trenes() -> void:
	if not is_inside_tree():
		return
	var trenes: Array[Node] = get_tree().get_nodes_in_group("trenes")
	for t: Node in trenes:
		if is_instance_valid(t) and t.has_method("_recalcular_paradas_dinamicas"):
			t.call_deferred("_recalcular_paradas_dinamicas")
