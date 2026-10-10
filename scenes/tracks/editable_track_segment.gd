@tool
class_name EditableTrackSegment
extends Path3D
## Tramo de vía procedural editable y persistente para la red ferroviaria (TrackNetwork).
##
## Permite la edición visual interactiva en el viewport 3D de Godot (puntos y manijas de Curve3D)
## y desde el Inspector (offsets de extremos, tangentes y acoples automáticos con switches o vías vecinas).
## Notifica en tiempo real a TrackGeometry para actualizar la infraestructura 3D (rieles, balasto y durmientes)
## y permite guardar o resetear las modificaciones a la forma original base de la red.

signal geometria_modificada(segment_id: String)
signal edicion_guardada(segment_id: String)
signal tramo_reseteado(segment_id: String)

const TIEMPO_DEBOUNCE: float = 0.10
## Intervalo (s) entre sondeos de la curva para detectar ediciones manuales.
const INTERVALO_POLLING_S: float = 0.2

@export_group("Identificación de Red")
## ID único del segmento en la red topológica (ej: "2659599269_0", "r1").
@export var segment_id: String = ""
## Sector geográfico asignado.
@export var sector_nombre: String = ""
## Tramo o estación asignada.
@export var tramo_nombre: String = ""

@export_group("Ajuste Extremo Inicio (Start)")
## Desplazamiento fino (X, Y, Z) aplicado al punto inicial (punto 0) de la curva.
@export var offset_inicio: Vector3 = Vector3.ZERO:
	set(v):
		offset_inicio = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			_aplicar_offsets_extremos()

## Modificación o curvatura tangencial en el extremo de inicio.
@export var tangente_inicio: Vector3 = Vector3.ZERO:
	set(v):
		tangente_inicio = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			_aplicar_offsets_extremos()

## Pulsador: Encaja automáticamente el punto inicial con el aparato de vía o tramo vecino conectado.
@export var boton_encajar_inicio: bool = false:
	set(v):
		if v:
			boton_encajar_inicio = false
			encajar_con_vecino("start")

@export_group("Ajuste Extremo Fin (End)")
## Desplazamiento fino (X, Y, Z) aplicado al punto final (punto N-1) de la curva.
@export var offset_fin: Vector3 = Vector3.ZERO:
	set(v):
		offset_fin = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			_aplicar_offsets_extremos()

## Modificación o curvatura tangencial en el extremo final.
@export var tangente_fin: Vector3 = Vector3.ZERO:
	set(v):
		tangente_fin = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			_aplicar_offsets_extremos()

## Pulsador: Encaja automáticamente el punto final con el aparato de vía o tramo vecino conectado.
@export var boton_encajar_fin: bool = false:
	set(v):
		if v:
			boton_encajar_fin = false
			encajar_con_vecino("end")

@export_group("Control de Recorte")
## Si es verdadero, anula el recorte automático por desvíos y extruye la geometría de vía plena completa.
@export var anular_recorte_switch: bool = false:
	set(v):
		anular_recorte_switch = v
		notificar_geometria_actualizada()

@export_group("Acciones de Vía")
## Guarda las modificaciones geométricas de este tramo en el archivo de ediciones persistente.
@export var boton_guardar: bool = false:
	set(v):
		if v:
			boton_guardar = false
			guardar_edicion()

## Restaura el tramo exactamente a su geometría original del JSON base y descarta las ediciones.
@export var boton_resetear: bool = false:
	set(v):
		if v:
			boton_resetear = false
			resetear_a_original()

## Fuerza la reconstrucción inmediata de la malla 3D de este tramo en TrackGeometry.
@export var boton_reconstruir: bool = false:
	set(v):
		if v:
			boton_reconstruir = false
			notificar_geometria_actualizada()

## Elimina permanentemente este tramo y su malla 3D de la red ferroviaria.
@export var boton_eliminar_tramo: bool = false:
	set(v):
		if v:
			boton_eliminar_tramo = false
			eliminar_este_tramo()

@export_group("Estado de Edición")
## Indica si este tramo contiene modificaciones respecto a la geometría original base.
@export var esta_modificada: bool = false
## Ficha de estado actual de la vía.
@export var estado_edicion: String = "Original"
## Longitud métrica actual calculada de la curva.
@export var longitud_metros: float = 0.0

## Curva original cargada desde la red base (inmutable, para permitir resetear siempre).
## Es también la curva COMPLETA que el tren recorre y la que el usuario edita: el
## recorte hacia el borne del aparato ya NO se aplica aquí, sino que vive como rango
## útil de malla en TrackNetwork (`obtener_rangos_utiles_tramo`). Antes se reemplazaba
## la curva por una subcurva muestreada, lo que creaba puntos nuevos y pisaba la edición.
var curva_original: Curve3D = null

# Control de debounce y sincronización
var _cache_hash_curva: int = 0
var _curva_sucia: bool = false
var _tiempo_sin_cambios: float = 0.0
var _acum_polling: float = 0.0
var _bloqueo_reconstruccion: bool = false
var _curva_conectada: Curve3D = null


var _red_cache: TrackNetwork = null


func _ready() -> void:
	_red_cache = _obtener_track_network()
	if not curve_changed.is_connected(_on_curve_changed):
		curve_changed.connect(_on_curve_changed)
	_conectar_recurso_curva()

	if curve != null:
		_cache_hash_curva = _obtener_hash_curva()
		longitud_metros = curve.get_baked_length()
		if curva_original == null:
			curva_original = curve.duplicate() as Curve3D


func _exit_tree() -> void:
	if _curva_conectada != null and is_instance_valid(_curva_conectada):
		if _curva_conectada.changed.is_connected(_on_curve_resource_changed):
			_curva_conectada.changed.disconnect(_on_curve_resource_changed)
		_curva_conectada = null

	var red: TrackNetwork = _red_cache if _red_cache != null and is_instance_valid(_red_cache) else _obtener_track_network()
	if red != null and red.get("_limpiando") == true:
		return

	# Al salir del árbol (por eliminación manual del usuario), remover la geometría 3D asociada
	var geo: Node = _obtener_track_geometry()
	if geo != null and geo.has_method("eliminar_geometria_tramo"):
		geo.call("eliminar_geometria_tramo", segment_id)

	# La baja NO se persiste acá: TrackNetwork la confirma en el próximo frame
	# sólo si el nodo desapareció de verdad y la escena sigue viva. Así una
	# recarga/cierre de la escena en el editor no marca toda la red como borrada
	# (era la causa de que se perdiera la edición manual completa al guardar).
	if red != null and red.has_method("solicitar_baja_segmento"):
		red.call("solicitar_baja_segmento", segment_id)


## Elimina este tramo y su infraestructura 3D de la red ferroviaria.
func eliminar_este_tramo() -> void:
	var red: TrackNetwork = _obtener_track_network()
	if red != null and red.has_method("eliminar_segmento"):
		red.call("eliminar_segmento", segment_id)
	else:
		var geo: Node = _obtener_track_geometry()
		if geo != null and geo.has_method("eliminar_geometria_tramo"):
			geo.call("eliminar_geometria_tramo", segment_id)
		queue_free()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	# El sondeo por hash se limita a ~0.2 s: en una red de cientos de tramos, hashear
	# la curva de TODOS cada frame es el mayor costo de CPU en el editor. Los cambios
	# reales igual se detectan por las señales de la curva (con debounce propio).
	_acum_polling += delta
	if _acum_polling >= INTERVALO_POLLING_S:
		_acum_polling = 0.0
		if curve != null:
			var h: int = _obtener_hash_curva()
			if h != _cache_hash_curva:
				_cache_hash_curva = h
				_curva_sucia = true
				_tiempo_sin_cambios = 0.0

	if _curva_sucia:
		_tiempo_sin_cambios += delta
		if _tiempo_sin_cambios >= TIEMPO_DEBOUNCE:
			_curva_sucia = false
			if not _bloqueo_reconstruccion:
				_al_modificar_curva_desde_editor()


func _conectar_recurso_curva() -> void:
	if _curva_conectada != null and is_instance_valid(_curva_conectada):
		if _curva_conectada != curve:
			if _curva_conectada.changed.is_connected(_on_curve_resource_changed):
				_curva_conectada.changed.disconnect(_on_curve_resource_changed)
			_curva_conectada = null

	if curve != null and _curva_conectada == null:
		if not curve.changed.is_connected(_on_curve_resource_changed):
			curve.changed.connect(_on_curve_resource_changed)
		_curva_conectada = curve


func _on_curve_changed() -> void:
	_conectar_recurso_curva()
	if not _bloqueo_reconstruccion:
		_curva_sucia = true
		_tiempo_sin_cambios = 0.0


func _on_curve_resource_changed() -> void:
	if not _bloqueo_reconstruccion:
		_curva_sucia = true
		_tiempo_sin_cambios = 0.0


func _al_modificar_curva_desde_editor() -> void:
	esta_modificada = true
	estado_edicion = "Modificado"
	# La curva editada pasa a ser la curva de referencia (la que recorre el tren y
	# la que se serializa). No se toca punto alguno: se respeta exactamente lo que
	# el usuario movió. Antes se resampleaba y desplazaba, creando puntos nuevos.
	curva_original = curve.duplicate() as Curve3D
	# La edición con el gizmo redefine la forma completa: los ajustes finos de
	# extremos quedan obsoletos y se anulan para que no se re-apliquen encima.
	_bloqueo_reconstruccion = true
	offset_inicio = Vector3.ZERO
	offset_fin = Vector3.ZERO
	tangente_inicio = Vector3.ZERO
	tangente_fin = Vector3.ZERO
	_bloqueo_reconstruccion = false
	if curve != null:
		longitud_metros = curve.get_baked_length()

	notificar_geometria_actualizada()
	geometria_modificada.emit(segment_id)


func _aplicar_offsets_extremos() -> void:
	if curva_original == null or curve == null or curve.point_count < 2 or curva_original.point_count < 2:
		return

	_bloqueo_reconstruccion = true

	# Extremo inicio
	var p0_orig: Vector3 = curva_original.get_point_position(0)
	var t0_out_orig: Vector3 = curva_original.get_point_out(0)
	curve.set_point_position(0, p0_orig + offset_inicio)
	if tangente_inicio != Vector3.ZERO:
		curve.set_point_out(0, t0_out_orig + tangente_inicio)

	# Extremo fin
	var last_idx: int = curve.point_count - 1
	var last_orig: int = curva_original.point_count - 1
	var pn_orig: Vector3 = curva_original.get_point_position(last_orig)
	var tn_in_orig: Vector3 = curva_original.get_point_in(last_orig)
	curve.set_point_position(last_idx, pn_orig + offset_fin)
	if tangente_fin != Vector3.ZERO:
		curve.set_point_in(last_idx, tn_in_orig + tangente_fin)

	_bloqueo_reconstruccion = false
	_cache_hash_curva = _obtener_hash_curva()
	longitud_metros = curve.get_baked_length()
	esta_modificada = true
	estado_edicion = "Modificado"

	notificar_geometria_actualizada()
	geometria_modificada.emit(segment_id)


## Notifica a TrackGeometry para que re-extruya inmediatamente la infraestructura 3D de este tramo.
func notificar_geometria_actualizada() -> void:
	var geo: Node = _obtener_track_geometry()
	if geo != null and geo.has_method("actualizar_geometria_tramo"):
		geo.call("actualizar_geometria_tramo", segment_id)


func _obtener_track_network() -> TrackNetwork:
	var candidato: Node = get_parent()
	while candidato != null:
		if candidato is TrackNetwork:
			return candidato as TrackNetwork
		candidato = candidato.get_parent()
	if is_inside_tree():
		return get_tree().get_first_node_in_group("track_network") as TrackNetwork
	return null


func _obtener_track_geometry() -> Node:
	var red: TrackNetwork = _obtener_track_network()
	if red != null:
		var g: Node = red.get_node_or_null("GeometriaVias")
		if g != null:
			return g
	if is_inside_tree():
		var lista: Array[Node] = get_tree().get_nodes_in_group("track_geometry")
		if not lista.is_empty():
			return lista[0]
	return null


## Encaja automáticamente este extremo de vía con el aparato de vía o tramo conectado.
func encajar_con_vecino(extremo: String) -> void:
	var red: TrackNetwork = _obtener_track_network()
	if red == null:
		push_warning("EditableTrackSegment: No se encontró TrackNetwork para encajar tramo %s." % segment_id)
		return
	if red.has_method("encajar_segmento_con_vecino"):
		red.call("encajar_segmento_con_vecino", segment_id, extremo)


## Guarda las modificaciones geométricas de este tramo en el archivo persistente de la red.
func guardar_edicion() -> void:
	var red: TrackNetwork = _obtener_track_network()
	if red != null and red.has_method("guardar_edicion_segmento"):
		red.call("guardar_edicion_segmento", segment_id)
		estado_edicion = "Modificado (Guardado)"
		edicion_guardada.emit(segment_id)
		print("EditableTrackSegment: Edición guardada para tramo '%s'." % segment_id)
	else:
		push_warning("EditableTrackSegment: No se pudo guardar. TrackNetwork no disponible.")


## Restaura el tramo a su geometría original base y descarta cualquier edición.
func resetear_a_original() -> void:
	_bloqueo_reconstruccion = true
	if curva_original != null:
		curve = curva_original.duplicate() as Curve3D
	offset_inicio = Vector3.ZERO
	tangente_inicio = Vector3.ZERO
	offset_fin = Vector3.ZERO
	tangente_fin = Vector3.ZERO
	anular_recorte_switch = false
	esta_modificada = false
	estado_edicion = "Original"

	if curve != null:
		longitud_metros = curve.get_baked_length()
	_cache_hash_curva = _obtener_hash_curva()
	_bloqueo_reconstruccion = false

	var red: TrackNetwork = _obtener_track_network()
	if red != null and red.has_method("descartar_edicion_segmento"):
		red.call("descartar_edicion_segmento", segment_id)

	notificar_geometria_actualizada()
	tramo_reseteado.emit(segment_id)
	print("EditableTrackSegment: Tramo '%s' reseteado a su forma original." % segment_id)


func _obtener_hash_curva() -> int:
	if curve == null:
		return 0
	var h: int = curve.point_count
	for i in curve.point_count:
		var p: Vector3 = curve.get_point_position(i)
		var pi: Vector3 = curve.get_point_in(i)
		var po: Vector3 = curve.get_point_out(i)
		var t: float = curve.get_point_tilt(i)
		h = hash(h ^ hash(p) ^ hash(pi) ^ hash(po) ^ hash(t))
	return h


## Serializa la curva actual a un diccionario reproducible en formato JSON.
func serializar_datos() -> Dictionary:
	return {
		"modificado": esta_modificada,
		"anular_recorte_switch": anular_recorte_switch,
		"offset_inicio": [offset_inicio.x, offset_inicio.y, offset_inicio.z],
		"tangente_inicio": [tangente_inicio.x, tangente_inicio.y, tangente_inicio.z],
		"offset_fin": [offset_fin.x, offset_fin.y, offset_fin.z],
		"tangente_fin": [tangente_fin.x, tangente_fin.y, tangente_fin.z],
		# Se guarda la curva COMPLETA editada (el recorte de malla se recalcula solo).
		"curva": curva_a_dict(curva_original) if curva_original != null else (curva_a_dict(curve) if curve != null else {})
	}


## Deserializa y aplica datos guardados en este tramo.
func deserializar_datos(data: Dictionary) -> void:
	_bloqueo_reconstruccion = true
	anular_recorte_switch = bool(data.get("anular_recorte_switch", false))

	var o_ini: Array = data.get("offset_inicio", [0.0, 0.0, 0.0]) as Array
	if o_ini.size() >= 3:
		offset_inicio = Vector3(float(o_ini[0]), float(o_ini[1]), float(o_ini[2]))

	var t_ini: Array = data.get("tangente_inicio", [0.0, 0.0, 0.0]) as Array
	if t_ini.size() >= 3:
		tangente_inicio = Vector3(float(t_ini[0]), float(t_ini[1]), float(t_ini[2]))

	var o_fin: Array = data.get("offset_fin", [0.0, 0.0, 0.0]) as Array
	if o_fin.size() >= 3:
		offset_fin = Vector3(float(o_fin[0]), float(o_fin[1]), float(o_fin[2]))

	var t_fin: Array = data.get("tangente_fin", [0.0, 0.0, 0.0]) as Array
	if t_fin.size() >= 3:
		tangente_fin = Vector3(float(t_fin[0]), float(t_fin[1]), float(t_fin[2]))

	if data.has("curva") and data["curva"] is Dictionary:
		var completa: Curve3D = dict_a_curva(data["curva"] as Dictionary)
		if completa.point_count >= 2:
			curva_original = completa
			curve = completa.duplicate() as Curve3D

	esta_modificada = true
	estado_edicion = "Modificado (Guardado)"
	if curve != null:
		longitud_metros = curve.get_baked_length()
	_cache_hash_curva = _obtener_hash_curva()
	_bloqueo_reconstruccion = false


## Convierte un recurso Curve3D en diccionario compatible con JSON.
static func curva_a_dict(c: Curve3D) -> Dictionary:
	if c == null:
		return {}
	var puntos: Array[Dictionary] = []
	for i in c.point_count:
		var p: Vector3 = c.get_point_position(i)
		var pi: Vector3 = c.get_point_in(i)
		var po: Vector3 = c.get_point_out(i)
		var t: float = c.get_point_tilt(i)
		puntos.append({
			"pos": [p.x, p.y, p.z],
			"in": [pi.x, pi.y, pi.z],
			"out": [po.x, po.y, po.z],
			"tilt": t
		})
	return {
		"bake_interval": c.bake_interval,
		"points": puntos
	}


## Reconstruye un Curve3D a partir de un diccionario JSON.
static func dict_a_curva(d: Dictionary) -> Curve3D:
	var c: Curve3D = Curve3D.new()
	c.bake_interval = float(d.get("bake_interval", 2.0))
	var puntos: Array = d.get("points", []) as Array
	for pt_raw in puntos:
		if not (pt_raw is Dictionary):
			continue
		var pt: Dictionary = pt_raw as Dictionary
		var p_arr: Array = pt.get("pos", [0.0, 0.0, 0.0]) as Array
		var in_arr: Array = pt.get("in", [0.0, 0.0, 0.0]) as Array
		var out_arr: Array = pt.get("out", [0.0, 0.0, 0.0]) as Array
		var tilt: float = float(pt.get("tilt", 0.0))

		var pos: Vector3 = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2])) if p_arr.size() >= 3 else Vector3.ZERO
		var p_in: Vector3 = Vector3(float(in_arr[0]), float(in_arr[1]), float(in_arr[2])) if in_arr.size() >= 3 else Vector3.ZERO
		var p_out: Vector3 = Vector3(float(out_arr[0]), float(out_arr[1]), float(out_arr[2])) if out_arr.size() >= 3 else Vector3.ZERO

		c.add_point(pos, p_in, p_out)
		c.set_point_tilt(c.point_count - 1, tilt)
	return c
