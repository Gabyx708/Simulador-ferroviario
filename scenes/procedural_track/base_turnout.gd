@tool
class_name BaseTurnout
extends Node3D
## Clase base para todos los aparatos de vía (desvíos/switches).
## Concentra toda la lógica de extrusión de rieles, geometría procedural
## de durmientes, balasto, silletas y marmita, evitando duplicación entre
## ProceduralTurnout (Tipo A), ProceduralSymmetricalTurnout (Tipo B) y
## ProceduralCrossover (Tipo C).

const _FlexibleTrackLeadScript = preload("res://scenes/procedural_track/flexible_track_lead.gd")

@export_group("Materiales")
@export var material_riel: Material = null
@export var material_durmiente: Material = null
@export var material_balasto: Material = null
@export var material_metal: Material = null
@export_group("Topología de Red")
## Identificador numérico del nodo OSM / unión en la red.
@export var node_id: int = 0
## ID del segmento común de entrada (Stem).
@export var via_comun_id: String = ""
## ID del segmento directo (continuación recta principal).
@export var via_directa_id: String = ""
## ID del segmento desviado (rama curva o cambio de vía).
@export var via_desviada_id: String = ""
## Clasificación de aparato asignada por la red (TIPO_A, TIPO_B, TIPO_C, TIPO_D, TIPO_E).
@export var tipo_aparato_override: String = ""
@export_group("Extremos Flexibles")
## Si es verdadero, genera y sincroniza automáticamente los extremos de vía adaptativos en los puertos del switch.
@export var generar_extremos_flexibles: bool = true:
	set(v):
		generar_extremos_flexibles = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			if generar_extremos_flexibles:
				sincronizar_extremos_flexibles()
			else:
				var g: Node = get_node_or_null("ExtremosFlexibles")
				if g != null:
					remove_child(g)
					g.queue_free()

@export_group("Edición Manual")
## Pulsador: elimina permanentemente este aparato de vía de la red y persiste la baja.
## La geometría de vía plena del sector se restaura (el aparato ya no la reemplaza).
@export var boton_eliminar_aparato: bool = false:
	set(v):
		if v:
			boton_eliminar_aparato = false
			eliminar_aparato()
@export_group("Optimización y Culling")
## Distancia máxima en metros a la que se renderizan los rieles y balasto del desvío (0 = sin límite).
@export var distancia_culling_cuerpo: float = 800.0:
	set(v):
		distancia_culling_cuerpo = maxf(0.0, v)
		aplicar_culling()

## Distancia máxima en metros a la que se renderizan piezas menores (marmita, silletas, tirantes, espadines).
@export var distancia_culling_detalles: float = 400.0:
	set(v):
		distancia_culling_detalles = maxf(0.0, v)
		aplicar_culling()

# Materiales de farol (se crean al primer uso)
var _mat_farol_directa: StandardMaterial3D = null
var _mat_farol_desviada: StandardMaterial3D = null

# Nodo marmita e hijos animados (accesibles desde subclases)
var _nodo_marmita: Node3D = null
var _farol_indicador: MeshInstance3D = null
var _disco_indicador: MeshInstance3D = null
var _palanca_contrapeso: Node3D = null

# Tween compartido para animaciones de agujas
var _tween_agujas: Tween = null

## Flag de re-entrada para evitar reconstrucciones recursivas.
## Debe ser leída/escrita exclusivamente desde subclases dentro de construir_geometria().
var _bloqueo_reconstruccion: bool = false:
	set(v): _bloqueo_reconstruccion = v
	get: return _bloqueo_reconstruccion


# ---------------------------------------------------------------------------
# INTERFAZ PÚBLICA (conmutar debe implementarse en subclases)
# ---------------------------------------------------------------------------

## Alterna el estado del desvío.
func conmutar() -> void:
	pass


## Establece el estado o modo de ruta del aparato (0 = directa/vía principal, >0 = desviada/rama secundaria).
func conmutar_a(_modo: int = 0) -> void:
	pass


## Devuelve si el desvío está en posición desviada o ruta secundaria activa.
func is_desviado() -> bool:
	return false


## Construye la geometría completa del aparato en el espacio 3D.
func construir_geometria() -> void:
	pass


## Devuelve la curva (Curve3D) actualmente activa según la posición de las agujas.
func obtener_curva_activa(_via_origen: int = 1) -> Curve3D:
	return null


## Devuelve la curva continua completa (extremo de entrada + núcleo del switch + extremo de salida)
## en coordenadas locales del aparato. Subclases deben sobreescribirla según su topología.
func obtener_trayectoria_completa(_via_origen: int = 1) -> Curve3D:
	return obtener_curva_activa(_via_origen)


## Devuelve la curva continua completa en coordenadas globales del mundo 3D.
func obtener_trayectoria_completa_global(via_origen: int = 1) -> Curve3D:
	var c_loc: Curve3D = obtener_trayectoria_completa(via_origen)
	if c_loc == null or c_loc.point_count < 2:
		return null
	var c_glob: Curve3D = Curve3D.new()
	var xform: Transform3D = global_transform
	for i in range(c_loc.point_count):
		var p: Vector3 = xform * c_loc.get_point_position(i)
		var in_h: Vector3 = xform.basis * c_loc.get_point_in(i)
		var out_h: Vector3 = xform.basis * c_loc.get_point_out(i)
		c_glob.add_point(p, in_h, out_h)
	return c_glob


## Función auxiliar para muestrear puntos de una curva y agregarlos secuencialmente a otra.
func _muestrear_y_anexar_curva(c_dest: Curve3D, c_fuente: Curve3D, invertida: bool, n_pasos: int = 24) -> void:
	if c_fuente == null or c_fuente.point_count < 2:
		return
	var len_c: float = c_fuente.get_baked_length()
	if len_c < 0.05:
		return
	var step: float = len_c / float(n_pasos)
	for i in range(n_pasos + 1):
		var d: float = (len_c - float(i) * step) if invertida else (float(i) * step)
		var pt: Vector3 = c_fuente.sample_baked(d)
		if c_dest.point_count > 0:
			var ult: Vector3 = c_dest.get_point_position(c_dest.point_count - 1)
			if ult.distance_squared_to(pt) < 1e-4:
				continue
		c_dest.add_point(pt)



## Devuelve el identificador del tipo de aparato (TIPO_A, TIPO_B, TIPO_C, TIPO_D, TIPO_E).
func get_tipo_aparato() -> String:
	if not tipo_aparato_override.is_empty():
		return tipo_aparato_override
	return "BASE"


## Devuelve una descripción legible del estado actual del aparato.
func get_estado_descripcion() -> String:
	return ""


## Devuelve el ID del segmento actualmente conectado según la posición de las agujas.
func get_segmento_activo() -> String:
	return via_desviada_id if is_desviado() else via_directa_id


## Devuelve la longitud longitudinal de ocupación del aparato en metros (para recortar vía plena sin solapes).
func get_largo_aparato() -> float:
	return 20.0


## Devuelve la lista de puertos de conexión en los extremos físicos del aparato.
## Cada elemento es un Dictionary con:
## - "id": String
## - "nombre": String
## - "posicion": Vector3 (local)
## - "direccion": Vector3 (vector unitario saliente hacia afuera del aparato)
func obtener_puertos_conexion() -> Array[Dictionary]:
	return []


## Los nodos de geometría procedural (balasto, durmientes, rieles, marmita)
## NO deben tener scene owner asignado para evitar que Godot los serialice como
## arreglos binarios gigantescos en el archivo .tscn (ver sección 4 del README).
func obtener_scene_owner() -> Node:
	return null


## Devuelve la red ferroviaria a la que pertenece este aparato (si existe).
func obtener_track_network() -> Node:
	var candidato: Node = get_parent()
	while candidato != null:
		if candidato is TrackNetwork:
			return candidato
		candidato = candidato.get_parent()
	if is_inside_tree():
		return get_tree().get_first_node_in_group("track_network")
	return null


## Elimina este aparato de la red de forma persistente (baja registrada en el journal).
func eliminar_aparato() -> void:
	var red: Node = obtener_track_network()
	if red != null and red.has_method("eliminar_switch"):
		red.call("eliminar_switch", node_id)
		return
	push_warning("BaseTurnout: No se encontró TrackNetwork; se elimina sólo el nodo de escena.")
	var padre: Node = get_parent()
	if padre != null:
		padre.remove_child(self)
	queue_free()


## Obtiene o crea un contenedor organizado de nodos (GeometriaFija, MecanismoAgujas, ExtremosFlexibles)
## registrando adecuadamente el owner para que sea visible en el panel Escena.
func asegurar_nodo_grupo(nombre_grupo: String) -> Node3D:
	var nodo: Node3D = get_node_or_null(nombre_grupo) as Node3D
	if nodo == null:
		nodo = Node3D.new()
		nodo.name = nombre_grupo
		add_child(nodo)
		var ow: Node = obtener_scene_owner()
		if ow != null:
			nodo.owner = ow
	return nodo


func agregar_a_geometria_fija(nodo: Node) -> void:
	if nodo == null:
		return
	var g_geo: Node3D = asegurar_nodo_grupo("GeometriaFija")
	g_geo.add_child(nodo)
	var ow: Node = obtener_scene_owner()
	if ow != null:
		nodo.owner = ow


func agregar_a_mecanismo(nodo: Node) -> void:
	if nodo == null:
		return
	var g_mec: Node3D = asegurar_nodo_grupo("MecanismoAgujas")
	g_mec.add_child(nodo)
	var ow: Node = obtener_scene_owner()
	if ow != null:
		nodo.owner = ow


## Genera o sincroniza los tramos de transición adaptativos en los puertos de conexión del switch.
func sincronizar_extremos_flexibles(longitud_defecto: float = 20.0) -> Node3D:
	var grupo: Node3D = asegurar_nodo_grupo("ExtremosFlexibles")
	var puertos: Array[Dictionary] = obtener_puertos_conexion()
	var ow: Node = obtener_scene_owner()

	for p: Dictionary in puertos:
		var p_id: String = str(p.get("id", ""))
		var nombre_nodo: String = "Extremo_" + p_id.capitalize().replace(" ", "_")
		var lead: Node3D = grupo.get_node_or_null(nombre_nodo)
		if lead == null:
			lead = _FlexibleTrackLeadScript.new()
			lead.name = nombre_nodo
			lead.material_riel = material_riel
			lead.material_balasto = material_balasto
			lead.material_durmiente = material_durmiente
			lead.longitud_extension = longitud_defecto
			grupo.add_child(lead)
			if ow != null:
				lead.owner = ow
		else:
			lead.material_riel = material_riel
			lead.material_balasto = material_balasto
			lead.material_durmiente = material_durmiente

		var pos_b: Vector3 = p.get("posicion", Vector3.ZERO) as Vector3
		var dir_b: Vector3 = p.get("direccion", Vector3.FORWARD) as Vector3
		lead.conectar_a_borne(pos_b, dir_b)

	return grupo


func _limpiar_hijos_de(nodo: Node) -> void:
	if nodo == null:
		return
	var hijos: Array[Node] = nodo.get_children()
	for c: Node in hijos:
		nodo.remove_child(c)
		c.queue_free()


## Elimina todos los hijos generados y resetea referencias.
func limpiar() -> void:
	if _tween_agujas != null and _tween_agujas.is_valid():
		_tween_agujas.kill()
	_tween_agujas = null

	var g_geo: Node = get_node_or_null("GeometriaFija")
	if g_geo != null:
		_limpiar_hijos_de(g_geo)

	var g_mec: Node = get_node_or_null("MecanismoAgujas")
	if g_mec != null:
		_limpiar_hijos_de(g_mec)

	var a_eliminar: Array[Node] = []
	for c: Node in get_children():
		if c.name != "ExtremosFlexibles" and c.name != "GeometriaFija" and c.name != "MecanismoAgujas":
			a_eliminar.append(c)
	for c: Node in a_eliminar:
		remove_child(c)
		c.queue_free()

	_nodo_marmita = null
	_farol_indicador = null
	_disco_indicador = null
	_palanca_contrapeso = null
	_mat_farol_directa = null
	_mat_farol_desviada = null


## Aplica rangos de visibilidad (GPU distance culling) a toda la geometría del aparato.
func aplicar_culling() -> void:
	_aplicar_culling_recursivo(self)


func _aplicar_culling_recursivo(nodo: Node) -> void:
	if nodo == null:
		return
	if nodo is MeshInstance3D:
		var mi: MeshInstance3D = nodo as MeshInstance3D
		var es_detalle: bool = mi.name.begins_with("Silletas") or \
							   mi.name.begins_with("Espadin") or \
							   mi.name.begins_with("Tirante") or \
							   mi.name == "Disco" or \
							   mi.name == "Farol" or \
							   (nodo.get_parent() != null and nodo.get_parent().name.begins_with("Marmita")) or \
							   (nodo.get_parent() != null and nodo.get_parent().name.begins_with("Palanca"))
		var dist: float = distancia_culling_detalles if es_detalle else distancia_culling_cuerpo
		if dist > 0.0:
			mi.visibility_range_end = dist
			mi.visibility_range_end_margin = 25.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			mi.visibility_range_end = 0.0
	for c: Node in nodo.get_children():
		_aplicar_culling_recursivo(c)


# ---------------------------------------------------------------------------
# MATERIALES
# ---------------------------------------------------------------------------

func _asegurar_materiales() -> void:
	if material_riel == null:
		material_riel = ProceduralTrackProfile.obtener_material_defecto("riel")
	if material_balasto == null:
		material_balasto = ProceduralTrackProfile.obtener_material_defecto("balasto")
	if material_durmiente == null:
		material_durmiente = ProceduralTrackProfile.obtener_material_defecto("durmiente")
	if material_metal == null:
		material_metal = ProceduralTrackProfile.obtener_material_defecto("metal_oscuro")
	_asegurar_materiales_farol()


func _asegurar_materiales_farol() -> void:
	if _mat_farol_directa == null:
		_mat_farol_directa = StandardMaterial3D.new()
		_mat_farol_directa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_farol_directa.albedo_color = Color(0.10, 0.90, 0.20)
		_mat_farol_directa.emission_enabled = true
		_mat_farol_directa.emission = Color(0.10, 0.90, 0.20)
		_mat_farol_directa.emission_energy_multiplier = 0.7
	if _mat_farol_desviada == null:
		_mat_farol_desviada = StandardMaterial3D.new()
		_mat_farol_desviada.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_farol_desviada.albedo_color = Color(0.96, 0.52, 0.04)
		_mat_farol_desviada.emission_enabled = true
		_mat_farol_desviada.emission = Color(0.96, 0.52, 0.04)
		_mat_farol_desviada.emission_energy_multiplier = 0.7


func _mat_farol_para_estado(desviada: bool) -> Material:
	_asegurar_materiales_farol()
	return _mat_farol_desviada if desviada else _mat_farol_directa


# ---------------------------------------------------------------------------
# EXTRUSIÓN DE RIELES
# ---------------------------------------------------------------------------

## Extruye un riel a lo largo de una curva entre d0 y d1 con offset lateral.
func _extruir_riel(st: SurfaceTool, curva: Curve3D, d0: float, d1: float, offset_lat: float) -> void:
	var largo: float = d1 - d0
	if largo < 0.10:
		return
	var pasos: int = maxi(2, int(ceil(largo / 0.8)))
	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_RIEL
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var d: float = d0 + float(p) * largo / float(pasos)
		var t: Transform3D = _frame_offset(curva, d, offset_lat)
		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(t * Vector3(pt.x, pt.y, 0.0))
		anillos.append(anillo)

	_teselar_anillos(st, anillos, perfil.size())


## Extruye una pata de liebre (wing rail) con acampanado cuadrático.
func _extruir_wing_rail(st: SurfaceTool, curva: Curve3D, d0: float, d1: float, offset_lat: float, flare_total: float) -> void:
	var largo: float = d1 - d0
	if largo < 0.10:
		return
	var pasos: int = 8
	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_RIEL
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var frac: float = float(p) / float(pasos)
		var d: float = d0 + frac * largo
		var flare: float = flare_total * (frac * frac)
		var t: Transform3D = _frame_offset(curva, d, offset_lat + flare)
		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(t * Vector3(pt.x, pt.y, 0.0))
		anillos.append(anillo)

	_teselar_anillos(st, anillos, perfil.size())


## Extruye un contrarriel con acampanado en los extremos.
func _extruir_contrarriel_acampanado(st: SurfaceTool, curva: Curve3D, d0: float, d1: float, offset_stock: float, offset_cr: float) -> void:
	var largo: float = d1 - d0
	if largo < 0.2:
		return
	var pasos: int = 14
	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_CONTRARRIEL
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var frac: float = float(p) / float(pasos)
		var d: float = d0 + frac * largo
		var extra_flare: float = 0.0
		if frac < 0.22:
			extra_flare = offset_cr * 0.85 * (1.0 - frac / 0.22)
		elif frac > 0.78:
			extra_flare = offset_cr * 0.85 * ((frac - 0.78) / 0.22)
		var t: Transform3D = _frame_offset(curva, d, offset_stock + offset_cr + extra_flare)
		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(t * Vector3(pt.x, pt.y, 0.0))
		anillos.append(anillo)

	_teselar_anillos(st, anillos, perfil.size())


# ---------------------------------------------------------------------------
# ESPADINES DE AGUJA MECANIZADOS (PUNTA REAL DE CAMBIO DE VÍA)
# ---------------------------------------------------------------------------

## Genera el perfil transversal de 10 vértices de un espadín mecanizado (UIC/T:ANE).
## u: 0.0 (punta afilada de aguja) a 1.0 (talón pleno de riel Vignole).
## lado_contraaguja: +1.0 si la contraaguja está a la derecha del espadín (+side), -1.0 si está a la izquierda (-side).
static func _obtener_perfil_espadin_mecanizado(u: float, lado_contraaguja: float) -> Array[Vector2]:
	var h_total: float = lerpf(0.142, 0.150, u)
	var y_top: float = lerpf(-0.008, 0.000, u)

	var w_hongo: float = lerpf(0.012, 0.070, u)
	var w_alma: float = lerpf(0.016, 0.024, u)
	var w_patin_int: float = lerpf(0.040, 0.060, u)
	var w_patin_ext: float = lerpf(0.004, 0.060, u)

	var s_in: float = -lado_contraaguja
	var s_ext: float = lado_contraaguja

	var pts: Array[Vector2] = [
		Vector2(0.0, y_top),
		Vector2(w_hongo * s_in, y_top),
		Vector2(w_hongo * s_in, y_top - 0.035),
		Vector2(w_alma * s_in, y_top - 0.050),
		Vector2(w_alma * s_in, -0.125),
		Vector2(w_patin_int * s_in, -0.145),
		Vector2(w_patin_int * s_in, -h_total),
		Vector2(w_patin_ext * s_ext, -h_total),
		Vector2(w_patin_ext * s_ext, -0.145),
		Vector2(w_alma * 0.5 * s_ext, y_top - 0.040)
	]
	return pts


## Genera una malla de espadín mecanizado de alta definición a lo largo de una curva dada,
## transformando cada vértice a coordenadas locales relativas al talón (pivot_pos y pivot_basis).
func _generar_malla_espadin_mecanizado(
	curva: Curve3D,
	d_toe: float,
	d_heel: float,
	offset_lat: float,
	lado_contraaguja: float,
	pivot_pos: Vector3,
	pivot_basis: Basis,
	pasos: int = 16
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inv: Basis = pivot_basis.inverse()
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var u: float = float(p) / float(pasos) # 0 = punta, 1 = talón
		var d: float = lerpf(d_toe, d_heel, u)

		var pos_track: Vector3 = curva.sample_baked(d)
		var fwd: Vector3 = _tangente(curva, d)
		var side: Vector3 = Vector3.UP.cross(fwd).normalized()
		var p_centro: Vector3 = pos_track + side * offset_lat

		var perfil: Array[Vector2] = _obtener_perfil_espadin_mecanizado(u, lado_contraaguja)
		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			var p_vert_world: Vector3 = p_centro + side * pt.x + Vector3(0.0, pt.y, 0.0)
			anillo.append(inv * (p_vert_world - pivot_pos))
		anillos.append(anillo)

	_teselar_anillos(st, anillos, 10)
	return st.commit()


## Tesela un array de anillos generando la malla del tubo.
func _teselar_anillos(st: SurfaceTool, anillos: Array[PackedVector3Array], n_pts: int) -> void:
	for p: int in anillos.size() - 1:
		for i: int in n_pts:
			var j: int = (i + 1) % n_pts
			var a: Vector3 = anillos[p][i]
			var b: Vector3 = anillos[p][j]
			var c: Vector3 = anillos[p + 1][j]
			var e: Vector3 = anillos[p + 1][i]
			var norm: Vector3 = (b - a).cross(c - a).normalized()
			st.set_normal(norm)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(e)


# ---------------------------------------------------------------------------
# GEOMETRÍA DE CAJAS
# ---------------------------------------------------------------------------

## Agrega un box orientado arbitrariamente al SurfaceTool.
func _agregar_box_orientado(st: SurfaceTool, centro: Vector3, largo: float, alto: float, ancho: float, dir_largo: Vector3, dir_fwd: Vector3) -> void:
	var h_l: float = largo * 0.5
	var h_h: float = alto * 0.5
	var h_w: float = ancho * 0.5
	var up: Vector3 = Vector3.UP

	var v000: Vector3 = centro - dir_largo * h_l - up * h_h - dir_fwd * h_w
	var v001: Vector3 = centro - dir_largo * h_l - up * h_h + dir_fwd * h_w
	var v010: Vector3 = centro - dir_largo * h_l + up * h_h - dir_fwd * h_w
	var v011: Vector3 = centro - dir_largo * h_l + up * h_h + dir_fwd * h_w
	var v100: Vector3 = centro + dir_largo * h_l - up * h_h - dir_fwd * h_w
	var v101: Vector3 = centro + dir_largo * h_l - up * h_h + dir_fwd * h_w
	var v110: Vector3 = centro + dir_largo * h_l + up * h_h - dir_fwd * h_w
	var v111: Vector3 = centro + dir_largo * h_l + up * h_h + dir_fwd * h_w

	st.set_normal(up)
	st.add_vertex(v010); st.add_vertex(v110); st.add_vertex(v111)
	st.add_vertex(v010); st.add_vertex(v111); st.add_vertex(v011)

	st.set_normal(-up)
	st.add_vertex(v000); st.add_vertex(v101); st.add_vertex(v100)
	st.add_vertex(v000); st.add_vertex(v001); st.add_vertex(v101)

	st.set_normal(dir_fwd)
	st.add_vertex(v001); st.add_vertex(v101); st.add_vertex(v111)
	st.add_vertex(v001); st.add_vertex(v111); st.add_vertex(v011)

	st.set_normal(-dir_fwd)
	st.add_vertex(v000); st.add_vertex(v110); st.add_vertex(v100)
	st.add_vertex(v000); st.add_vertex(v010); st.add_vertex(v110)

	st.set_normal(dir_largo)
	st.add_vertex(v100); st.add_vertex(v110); st.add_vertex(v111)
	st.add_vertex(v100); st.add_vertex(v111); st.add_vertex(v101)

	st.set_normal(-dir_largo)
	st.add_vertex(v000); st.add_vertex(v011); st.add_vertex(v010)
	st.add_vertex(v000); st.add_vertex(v001); st.add_vertex(v011)


# ---------------------------------------------------------------------------
# MARMITA INTERACTIVA (construida por subclases con posición / orientación propias)
# ---------------------------------------------------------------------------

## Construye la marmita completa y la agrega como hijo del nodo indicado.
## pos_world: posición en espacio local de this  |  basis: orientación local
func _construir_marmita_en(pos_world: Vector3, fwd: Vector3) -> Node3D:
	_asegurar_materiales()
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()

	var nodo: Node3D = Node3D.new()
	nodo.name = "Marmita"
	nodo.transform = Transform3D(Basis(side, Vector3.UP, fwd), pos_world)
	agregar_a_mecanismo(nodo)

	var ow: Node = obtener_scene_owner()

	# Base de fundición
	var mi_base: MeshInstance3D = MeshInstance3D.new()
	mi_base.name = "BaseFundicion"
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.50, 0.22, 0.50)
	mi_base.mesh = bm
	mi_base.position = Vector3(0.0, 0.11, 0.0)
	mi_base.material_override = material_metal
	nodo.add_child(mi_base)
	if ow != null: mi_base.owner = ow

	# Mástil vertical
	var mi_mastil: MeshInstance3D = MeshInstance3D.new()
	mi_mastil.name = "Mastil"
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 1.15
	mi_mastil.mesh = cm
	mi_mastil.position = Vector3(0.0, 0.78, 0.0)
	mi_mastil.material_override = material_metal
	nodo.add_child(mi_mastil)
	if ow != null: mi_mastil.owner = ow

	# Farol giratorio
	_farol_indicador = MeshInstance3D.new()
	_farol_indicador.name = "FarolIndicador"
	var cm_f: CylinderMesh = CylinderMesh.new()
	cm_f.top_radius = 0.14
	cm_f.bottom_radius = 0.15
	cm_f.height = 0.30
	_farol_indicador.mesh = cm_f
	_farol_indicador.position = Vector3(0.0, 1.35, 0.0)
	nodo.add_child(_farol_indicador)
	if ow != null: _farol_indicador.owner = ow

	# Disco indicador
	_disco_indicador = MeshInstance3D.new()
	_disco_indicador.name = "Disco"
	var cm_d: CylinderMesh = CylinderMesh.new()
	cm_d.top_radius = 0.22
	cm_d.bottom_radius = 0.22
	cm_d.height = 0.03
	_disco_indicador.mesh = cm_d
	_disco_indicador.rotation.x = deg_to_rad(90.0)
	_farol_indicador.add_child(_disco_indicador)
	if ow != null: _disco_indicador.owner = ow

	# Palanca de contrapeso
	_palanca_contrapeso = Node3D.new()
	_palanca_contrapeso.name = "PalancaContrapeso"
	_palanca_contrapeso.position = Vector3(0.0, 0.35, 0.0)
	nodo.add_child(_palanca_contrapeso)
	if ow != null: _palanca_contrapeso.owner = ow

	var mi_brazo: MeshInstance3D = MeshInstance3D.new()
	var cm_b: CylinderMesh = CylinderMesh.new()
	cm_b.top_radius = 0.020
	cm_b.bottom_radius = 0.025
	cm_b.height = 0.65
	mi_brazo.mesh = cm_b
	mi_brazo.position = Vector3(0.0, 0.25, 0.0)
	mi_brazo.material_override = material_metal
	_palanca_contrapeso.add_child(mi_brazo)
	if ow != null: mi_brazo.owner = ow

	var mi_pesa: MeshInstance3D = MeshInstance3D.new()
	var sm_p: SphereMesh = SphereMesh.new()
	sm_p.radius = 0.09
	sm_p.height = 0.18
	mi_pesa.mesh = sm_p
	mi_pesa.position = Vector3(0.0, 0.55, 0.0)
	mi_pesa.material_override = material_metal
	_palanca_contrapeso.add_child(mi_pesa)
	if ow != null: mi_pesa.owner = ow

	# Área de clic
	var area: Area3D = Area3D.new()
	area.name = "AreaClicMarmita"
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = 0.70
	shape.height = 1.75
	col.shape = shape
	col.position = Vector3(0.0, 0.85, 0.0)
	area.add_child(col)
	area.input_ray_pickable = true
	area.input_event.connect(_on_area_marmita_input_event)
	nodo.add_child(area)
	if ow != null:
		area.owner = ow
		col.owner = ow

	_nodo_marmita = nodo
	return nodo


func _on_area_marmita_input_event(_cam: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			conmutar()


## Aplica el estado visual del farol/disco de la marmita.
func _aplicar_estado_marmita(desviada: bool, animado: bool, rot_farol_obj: float, rot_pesa_obj: float) -> void:
	_asegurar_materiales_farol()
	var mat_f: Material = _mat_farol_para_estado(desviada)
	if _farol_indicador != null:
		_farol_indicador.material_override = mat_f
	if _disco_indicador != null:
		_disco_indicador.material_override = mat_f

	if not animado or not is_inside_tree():
		if _farol_indicador != null:
			_farol_indicador.rotation.y = rot_farol_obj
		if _palanca_contrapeso != null:
			_palanca_contrapeso.rotation.z = rot_pesa_obj
	else:
		# Tween dedicado para la marmita (independiente del tween de agujas)
		var tween_m: Tween = create_tween().set_parallel(true)
		if _farol_indicador != null:
			tween_m.tween_property(_farol_indicador, "rotation:y", rot_farol_obj, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _palanca_contrapeso != null:
			tween_m.tween_property(_palanca_contrapeso, "rotation:z", rot_pesa_obj, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# HELPERS DE CURVA
# ---------------------------------------------------------------------------

## Punto en el riel (sobre la curva, desplazado lateralmente).
func _punto_riel(curva: Curve3D, d: float, offset_lat: float) -> Vector3:
	var p: Vector3 = curva.sample_baked(d)
	var fwd: Vector3 = _tangente(curva, d)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	return p + side * offset_lat


## Tangente robusta (derivada analítica en extremos o diferencias finitas).
func _tangente(curva: Curve3D, d: float) -> Vector3:
	if curva == null or curva.point_count < 2:
		return Vector3.FORWARD
	var len_c: float = curva.get_baked_length()
	if d <= 0.05 and curva.point_count >= 2:
		var o: Vector3 = curva.get_point_out(0)
		if o.length_squared() > 1e-4:
			return o.normalized()
	elif d >= len_c - 0.05 and curva.point_count >= 2:
		var last_idx: int = curva.point_count - 1
		var in_h: Vector3 = curva.get_point_in(last_idx)
		if in_h.length_squared() > 1e-4:
			return (-in_h).normalized()
	var d0: float = maxf(0.0, d - 0.10)
	var d1: float = minf(len_c, d + 0.10)
	var v: Vector3 = curva.sample_baked(d1) - curva.sample_baked(d0)
	return v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD


## Transform3D (frame Frenet) en la curva con offset lateral.
func _frame_offset(curva: Curve3D, d: float, offset_lat: float) -> Transform3D:
	var p: Vector3 = curva.sample_baked(d)
	var fwd: Vector3 = _tangente(curva, d)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	return Transform3D(Basis(side, Vector3.UP, fwd), p + side * offset_lat)
