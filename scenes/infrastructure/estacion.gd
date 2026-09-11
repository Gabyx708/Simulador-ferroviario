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

var _ajustando_transform: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0
var _poste_ida: Node3D
var _poste_vuelta: Node3D


func _ready() -> void:
	_conectar_postes()
	_actualizar_dimensiones_anden()
	_actualizar_posicion_postes()
	if Engine.is_editor_hint():
		set_process(true)



func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not alinear_a_via or not _pendiente_snap:
		return

	var clic_izq: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var tiempo_pasado: int = Time.get_ticks_msec() - _tiempo_ultimo_movimiento

	# Cuando el usuario suelta el mouse tras arrastrar, o tras detener el movimiento
	if not clic_izq and tiempo_pasado > 60:
		_pendiente_snap = false
		_snap_a_posicion_actual()


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
