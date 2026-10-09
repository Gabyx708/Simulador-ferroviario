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

var _ajustando_transform: bool = false
var _transform_reciente: Transform3D = Transform3D.IDENTITY
var _ignorar_transform_reciente: bool = false
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
