@tool
class_name ProceduralCrossing
extends BaseTurnout
## Tipo C: Cruce Diamante / Cruce de Vías a Nivel en X (Diamond Crossing).
##
## Modela la infraestructura completa de un cruzamiento en X según estándares UIC / AREA / T:ANE:
## 1. Rieles de rodadura de ambas vías con interrupciones en los 4 corazones (garganta de 45 mm).
## 2. Dos corazones agudos mecanizados en V en los extremos longitudinales con patas de liebre.
## 3. Dos corazones obtusos de codo (knuckle frogs) en los vértices laterales.
## 4. Dos contrarrieles interiores de diamante curvados que rodean el centro (como en el diagrama T:ANE).
## 5. Cuatro contrarrieles exteriores acampanados en las aproximaciones opuestas a los corazones agudos.
## 6. Marcador circular central de intersección de ejes.
## 7. Travesas unificadas continuas de cruce (durmientes extendidos a través del rombo).
## 8. Plataforma de balasto en rombo con taludes perimetrales.
## 9. Mecanismo interactivo de selección de ruta para circulación de trenes (Vía A / Vía B).

signal estado_cambiado(via_b_activa: bool)

@export_group("Curvas de Vía")
## Curva 3D de la Vía A (Directa).
@export var curva_a: Curve3D = null:
	set(v):
		curva_a = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Curva 3D de la Vía B (Cruzada en X).
@export var curva_b: Curve3D = null:
	set(v):
		curva_b = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Centro 3D de intersección de los ejes de ambas vías.
@export var posicion_centro: Vector3 = Vector3.ZERO:
	set(v):
		posicion_centro = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Dimensiones T:ANE")
## Ángulo agudo de cruce en radianes (15° ~ 0.2618 rad).
@export_range(0.08, 1.57, 0.01) var angulo_cruce_rad: float = 0.2618:
	set(v):
		angulo_cruce_rad = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Semitrocha en metros (0.7175m para trocha estándar UIC 1.435m).
@export var trocha_media: float = ProceduralTrackProfile.TROCHA_MEDIA_DEFECTO:
	set(v):
		trocha_media = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Longitud total protegida del cruce a lo largo de cada vía.
@export_range(8.0, 35.0, 1.0) var largo_zona_cruce: float = 22.0:
	set(v):
		largo_zona_cruce = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Luz de pestaña reglamentaria (45 mm).
@export var luz_pestana: float = ProceduralTrackProfile.LUZ_PESTANA
## Paso entre durmientes de cruce (60 cm).
@export var paso_durmientes: float = ProceduralTrackProfile.PASO_DURMIENTES

@export_group("Equipamiento")
## Si es verdadero, se construye un farol/marmita indicador al costado del cruce.
@export var mostrar_marmita: bool = true:
	set(v):
		mostrar_marmita = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Estado de Ruta")
## false = Vía A activa (Directa), true = Vía B activa (Cruzada en X)
@export var via_b_activa: bool = false:
	set(v):
		var cambio: bool = (via_b_activa != v)
		via_b_activa = v
		if cambio:
			_actualizar_indicador_ruta()
			estado_cambiado.emit(via_b_activa)

# Nodos visuales generados
var _nodo_balasto: MeshInstance3D = null
var _nodo_durmientes: MeshInstance3D = null
var _nodo_rieles: MeshInstance3D = null
var _nodo_corazones: MeshInstance3D = null
var _nodo_contrarrieles: MeshInstance3D = null
var _nodo_marcador_centro: MeshInstance3D = null

# Geometría calculada
var _dir_bisectriz: Vector3 = Vector3.FORWARD
var _dir_transversal: Vector3 = Vector3.RIGHT
var _semi_ang: float = 0.1309
var _z_agudo: float = 5.50
var _x_obtuso: float = 0.73
var _s_agudo: float = 5.45
var _s_obtuso: float = 0.095


func _ready() -> void:
	_asegurar_materiales()
	if _nodo_rieles == null:
		construir_geometria()


func conmutar() -> void:
	via_b_activa = not via_b_activa


func limpiar() -> void:
	super.limpiar()
	_nodo_balasto = null
	_nodo_durmientes = null
	_nodo_rieles = null
	_nodo_corazones = null
	_nodo_contrarrieles = null
	_nodo_marcador_centro = null


## Devuelve la lista de puertos de conexión en los 4 extremos físicos del diamante.
func obtener_puertos_conexion() -> Array[Dictionary]:
	var fwd_a: Vector3 = _obtener_fwd_a()
	var fwd_b: Vector3 = _obtener_fwd_b()
	if fwd_a.dot(fwd_b) < 0.0:
		fwd_b = -fwd_b
	var semi_largo: float = largo_zona_cruce * 0.5
	return [
		{
			"id": "via_a_entrada",
			"nombre": "Vía A (Entrada)",
			"posicion": posicion_centro - fwd_a * semi_largo,
			"direccion": -fwd_a
		},
		{
			"id": "via_a_salida",
			"nombre": "Vía A (Salida)",
			"posicion": posicion_centro + fwd_a * semi_largo,
			"direccion": fwd_a
		},
		{
			"id": "via_b_entrada",
			"nombre": "Vía B (Entrada)",
			"posicion": posicion_centro - fwd_b * semi_largo,
			"direccion": -fwd_b
		},
		{
			"id": "via_b_salida",
			"nombre": "Vía B (Salida)",
			"posicion": posicion_centro + fwd_b * semi_largo,
			"direccion": fwd_b
		}
	]


# ===========================================================================
# CONSTRUCCIÓN DE GEOMETRÍA
# ===========================================================================

func construir_geometria() -> void:
	if _bloqueo_reconstruccion:
		return
	_bloqueo_reconstruccion = true

	limpiar()
	_asegurar_materiales()

	var fwd_a: Vector3 = _obtener_fwd_a()
	var fwd_b: Vector3 = _obtener_fwd_b()

	if fwd_a.dot(fwd_b) < 0.0:
		fwd_b = -fwd_b

	var cos_val: float = clampf(fwd_a.dot(fwd_b), -0.9999, 0.9999)
	var ang_calc: float = clampf(acos(cos_val), deg_to_rad(4.0), deg_to_rad(85.0))
	_semi_ang = clampf(ang_calc * 0.5, deg_to_rad(2.5), deg_to_rad(42.5))

	# Ejes del diamante
	_dir_bisectriz = (fwd_a + fwd_b).normalized()
	if _dir_bisectriz.length_squared() < 0.01:
		_dir_bisectriz = fwd_a
	_dir_transversal = Vector3.UP.cross(_dir_bisectriz).normalized()

	# Distancias de los 4 corazones desde el centro
	_z_agudo = trocha_media / sin(_semi_ang)
	_x_obtuso = trocha_media / cos(_semi_ang)

	# Distancias paramétricas exactas a lo largo de cada vía
	_s_agudo = trocha_media / tan(_semi_ang)
	_s_obtuso = trocha_media * tan(_semi_ang)

	var largo_minimo: float = (_z_agudo + 1.2) * 2.0
	largo_zona_cruce = clampf(maxf(largo_zona_cruce, largo_minimo), 10.0, 60.0)
	var semi_largo: float = largo_zona_cruce * 0.5
	_z_agudo = minf(_z_agudo, semi_largo - 0.8)
	_s_agudo = minf(_s_agudo, semi_largo - 0.8)

	var side_a: Vector3 = Vector3.UP.cross(fwd_a).normalized()
	var side_b: Vector3 = Vector3.UP.cross(fwd_b).normalized()

	# Puntos 3D de los 4 corazones
	var p_a1: Vector3 = posicion_centro - _dir_bisectriz * _z_agudo  # Agudo anterior
	var p_a2: Vector3 = posicion_centro + _dir_bisectriz * _z_agudo  # Agudo posterior
	var p_o1: Vector3 = posicion_centro - _dir_transversal * _x_obtuso # Obtuso izquierdo
	var p_o2: Vector3 = posicion_centro + _dir_transversal * _x_obtuso # Obtuso derecho

	# 1. Balasto en rombo
	_construir_balasto(semi_largo)

	# 2. Travesas unificadas ortogonales a la bisectriz
	_construir_durmientes(semi_largo)

	# 3. Rieles de rodadura con interrupciones de 90 mm en los corazones
	_construir_rieles_cruce(fwd_a, fwd_b, side_a, side_b, semi_largo)

	# 4. Bloques mecanizados de corazones (2 agudos con patas de liebre y 2 obtusos)
	_construir_corazones(p_a1, p_a2, p_o1, p_o2, fwd_a, fwd_b)

	# 5. Contrarrieles (2 centrales curvados de diamante + 4 exteriores acampanados)
	_construir_contrarrieles(p_a1, p_a2, p_o1, p_o2, fwd_a, fwd_b, side_a, side_b)

	# 6. Marcador circular central del cruce
	_construir_marcador_central()

	# 7. Indicador visual interactivo de ruta
	if mostrar_marmita:
		_construir_indicador_ruta(fwd_a)
		_actualizar_indicador_ruta()

	aplicar_culling()
	if self.generar_extremos_flexibles:
		sincronizar_extremos_flexibles()

	_bloqueo_reconstruccion = false


func _obtener_fwd_a() -> Vector3:
	if curva_a != null and curva_a.point_count >= 2:
		var d: float = curva_a.get_closest_offset(posicion_centro)
		var d0: float = maxf(0.0, d - 0.5)
		var d1: float = minf(curva_a.get_baked_length(), d + 0.5)
		var v: Vector3 = curva_a.sample_baked(d1) - curva_a.sample_baked(d0)
		if v.length_squared() > 0.001:
			return v.normalized()
	return Vector3.FORWARD


func _obtener_fwd_b() -> Vector3:
	if curva_b != null and curva_b.point_count >= 2:
		var d: float = curva_b.get_closest_offset(posicion_centro)
		var d0: float = maxf(0.0, d - 0.5)
		var d1: float = minf(curva_b.get_baked_length(), d + 0.5)
		var v: Vector3 = curva_b.sample_baked(d1) - curva_b.sample_baked(d0)
		if v.length_squared() > 0.001:
			return v.normalized()
	return Vector3(sin(angulo_cruce_rad), 0.0, cos(angulo_cruce_rad)).normalized()


# ===========================================================================
# BLOQUES DE CONSTRUCCIÓN
# ===========================================================================

func _construir_balasto(semi_largo: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pasos: int = maxi(6, int(ceil(largo_zona_cruce / 1.5)))
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var z_rel: float = -semi_largo + float(p) * largo_zona_cruce / float(pasos)
		var c_pt: Vector3 = posicion_centro + _dir_bisectriz * z_rel

		var dist_abs: float = absf(z_rel)
		var x_outer: float = dist_abs * tan(_semi_ang) + _x_obtuso
		var largo_t: float = maxf(2.0 * (x_outer + 0.55), 2.0 * _x_obtuso + 2.00)
		var semi_ancho: float = maxf((largo_t * 0.5) + 0.45, x_outer + 1.25)

		var pt_izq: Vector3 = c_pt - _dir_transversal * semi_ancho
		var pt_der: Vector3 = c_pt + _dir_transversal * semi_ancho

		var y_top: float = -0.28
		var y_bot: float = -0.65
		var ancho_talud: float = 0.85

		var v0: Vector3 = pt_izq - _dir_transversal * ancho_talud + Vector3(0.0, y_bot, 0.0)
		var v1: Vector3 = pt_der + _dir_transversal * ancho_talud + Vector3(0.0, y_bot, 0.0)
		var v2: Vector3 = pt_der + Vector3(0.0, y_top, 0.0)
		var v3: Vector3 = pt_izq + Vector3(0.0, y_top, 0.0)
		anillos.append(PackedVector3Array([v0, v1, v2, v3]))

	for p: int in pasos:
		for i: int in 4:
			var j: int = (i + 1) % 4
			var a: Vector3 = anillos[p][i]
			var b: Vector3 = anillos[p][j]
			var c: Vector3 = anillos[p + 1][j]
			var e: Vector3 = anillos[p + 1][i]
			var norm: Vector3 = (b - a).cross(c - a).normalized()
			st.set_normal(norm)
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(e)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_balasto = MeshInstance3D.new()
		_nodo_balasto.name = "BalastoRombo"
		_nodo_balasto.mesh = m
		_nodo_balasto.material_override = material_balasto
		add_child(_nodo_balasto)


func _construir_durmientes(semi_largo: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cantidad: int = maxi(2, int(round(largo_zona_cruce / paso_durmientes)))
	var paso_real: float = largo_zona_cruce / float(cantidad)
	var alto_d: float = 0.20
	var ancho_d: float = 0.26

	for i: int in cantidad:
		var z_rel: float = -semi_largo + (float(i) + 0.5) * paso_real
		var centro_d: Vector3 = posicion_centro + _dir_bisectriz * z_rel + Vector3(0.0, -0.28, 0.0)

		var dist_abs: float = absf(z_rel)
		var x_outer: float = dist_abs * tan(_semi_ang) + _x_obtuso
		var largo_t: float = maxf(2.0 * (x_outer + 0.55), 2.0 * _x_obtuso + 2.00)

		_agregar_box_orientado(st, centro_d, largo_t, alto_d, ancho_d, _dir_transversal, _dir_bisectriz)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_durmientes = MeshInstance3D.new()
		_nodo_durmientes.name = "DurmientesCruce"
		_nodo_durmientes.mesh = m
		_nodo_durmientes.material_override = material_durmiente
		add_child(_nodo_durmientes)


func _construir_rieles_cruce(
	fwd_a: Vector3, fwd_b: Vector3,
	side_a: Vector3, side_b: Vector3,
	semi_largo: float
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var g: float = luz_pestana # 45 mm semibrecha de garganta

	# --- VÍA A ---
	# 1. Riel Izquierdo (offset -trocha_media):
	# Cruces en -s_agudo y +s_obtuso
	_extruir_segmento(st,
		posicion_centro - fwd_a * semi_largo - side_a * trocha_media,
		posicion_centro - fwd_a * (_s_agudo + g) - side_a * trocha_media, side_a)
	_extruir_segmento(st,
		posicion_centro - fwd_a * (_s_agudo - g) - side_a * trocha_media,
		posicion_centro + fwd_a * (_s_obtuso - g) - side_a * trocha_media, side_a)
	_extruir_segmento(st,
		posicion_centro + fwd_a * (_s_obtuso + g) - side_a * trocha_media,
		posicion_centro + fwd_a * semi_largo - side_a * trocha_media, side_a)

	# 2. Riel Derecho (offset +trocha_media):
	# Cruces en -s_obtuso y +s_agudo
	_extruir_segmento(st,
		posicion_centro - fwd_a * semi_largo + side_a * trocha_media,
		posicion_centro - fwd_a * (_s_obtuso + g) + side_a * trocha_media, side_a)
	_extruir_segmento(st,
		posicion_centro - fwd_a * (_s_obtuso - g) + side_a * trocha_media,
		posicion_centro + fwd_a * (_s_agudo - g) + side_a * trocha_media, side_a)
	_extruir_segmento(st,
		posicion_centro + fwd_a * (_s_agudo + g) + side_a * trocha_media,
		posicion_centro + fwd_a * semi_largo + side_a * trocha_media, side_a)

	# --- VÍA B ---
	# 1. Riel Izquierdo (offset -trocha_media):
	# Cruces en -s_obtuso y +s_agudo
	_extruir_segmento(st,
		posicion_centro - fwd_b * semi_largo - side_b * trocha_media,
		posicion_centro - fwd_b * (_s_obtuso + g) - side_b * trocha_media, side_b)
	_extruir_segmento(st,
		posicion_centro - fwd_b * (_s_obtuso - g) - side_b * trocha_media,
		posicion_centro + fwd_b * (_s_agudo - g) - side_b * trocha_media, side_b)
	_extruir_segmento(st,
		posicion_centro + fwd_b * (_s_agudo + g) - side_b * trocha_media,
		posicion_centro + fwd_b * semi_largo - side_b * trocha_media, side_b)

	# 2. Riel Derecho (offset +trocha_media):
	# Cruces en -s_agudo y +s_obtuso
	_extruir_segmento(st,
		posicion_centro - fwd_b * semi_largo + side_b * trocha_media,
		posicion_centro - fwd_b * (_s_agudo + g) + side_b * trocha_media, side_b)
	_extruir_segmento(st,
		posicion_centro - fwd_b * (_s_agudo - g) + side_b * trocha_media,
		posicion_centro + fwd_b * (_s_obtuso - g) + side_b * trocha_media, side_b)
	_extruir_segmento(st,
		posicion_centro + fwd_b * (_s_obtuso + g) + side_b * trocha_media,
		posicion_centro + fwd_b * semi_largo + side_b * trocha_media, side_b)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_rieles = MeshInstance3D.new()
		_nodo_rieles.name = "RielesCruce"
		_nodo_rieles.mesh = m
		_nodo_rieles.material_override = material_riel
		add_child(_nodo_rieles)


func _construir_corazones(
	p_a1: Vector3, p_a2: Vector3,
	p_o1: Vector3, p_o2: Vector3,
	_fwd_a: Vector3, _fwd_b: Vector3
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Puntas en V de los Corazones Agudos en los extremos (forjadas afiladas)
	# Agudo anterior (p_a1, apunta hacia +bisectriz)
	_agregar_punta_corazon_v(st, p_a1, _dir_bisectriz, _dir_transversal)
	# Agudo posterior (p_a2, apunta hacia -bisectriz)
	_agregar_punta_corazon_v(st, p_a2, -_dir_bisectriz, _dir_transversal)

	# 2. Corazones Obtusos (Knuckle Frogs con codo mecanizado a 180° - ángulo)
	_agregar_bloque_obtuso(st, p_o1, -_dir_transversal, _dir_bisectriz)
	_agregar_bloque_obtuso(st, p_o2, _dir_transversal, _dir_bisectriz)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_corazones = MeshInstance3D.new()
		_nodo_corazones.name = "CorazonesMecanizados"
		_nodo_corazones.mesh = m
		_nodo_corazones.material_override = material_riel
		add_child(_nodo_corazones)


func _agregar_punta_corazon_v(st: SurfaceTool, pos_vertice: Vector3, dir_apunta: Vector3, dir_trans: Vector3) -> void:
	# Bloque triangular afilado que materializa la punta del corazón agudo
	var l_punta: float = 1.15
	var w_base: float = 0.13
	var h: float = 0.150

	var p_tip: Vector3 = pos_vertice
	var p_base_izq: Vector3 = pos_vertice + dir_apunta * l_punta - dir_trans * (w_base * 0.5)
	var p_base_der: Vector3 = pos_vertice + dir_apunta * l_punta + dir_trans * (w_base * 0.5)

	# Cara superior
	st.set_normal(Vector3.UP)
	st.add_vertex(p_tip)
	st.add_vertex(p_base_der)
	st.add_vertex(p_base_izq)

	# Caras laterales
	var p_tip_bot: Vector3 = p_tip + Vector3(0.0, -h, 0.0)
	var p_base_izq_bot: Vector3 = p_base_izq + Vector3(0.0, -h, 0.0)
	var p_base_der_bot: Vector3 = p_base_der + Vector3(0.0, -h, 0.0)

	var norm_der: Vector3 = (p_base_der - p_tip).cross(Vector3.UP).normalized()
	st.set_normal(norm_der)
	st.add_vertex(p_tip); st.add_vertex(p_tip_bot); st.add_vertex(p_base_der_bot)
	st.add_vertex(p_tip); st.add_vertex(p_base_der_bot); st.add_vertex(p_base_der)

	var norm_izq: Vector3 = Vector3.UP.cross(p_base_izq - p_tip).normalized()
	st.set_normal(norm_izq)
	st.add_vertex(p_tip); st.add_vertex(p_base_izq); st.add_vertex(p_base_izq_bot)
	st.add_vertex(p_tip); st.add_vertex(p_base_izq_bot); st.add_vertex(p_tip_bot)


func _agregar_bloque_obtuso(st: SurfaceTool, pos_codo: Vector3, dir_hacia_afuera: Vector3, dir_long: Vector3) -> void:
	# Codo protector mecanizado en el vértice obtuso
	var l_obt: float = 0.70
	_agregar_box_orientado(st, pos_codo + dir_hacia_afuera * 0.02, 0.09, 0.15, l_obt, dir_hacia_afuera, dir_long)


func _construir_contrarrieles(
	_p_a1: Vector3, _p_a2: Vector3,
	p_o1: Vector3, p_o2: Vector3,
	fwd_a: Vector3, fwd_b: Vector3,
	side_a: Vector3, side_b: Vector3
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# -------------------------------------------------------------------------
	# 1. DOS CONTRARRIELES CENTRALES CURVADOS DE DIAMANTE (COMO EN EL DIAGRAMA)
	# -------------------------------------------------------------------------
	# Situados en el interior del rombo frente a los dos corazones obtusos,
	# curvándose hacia el centro circular en ambos extremos.
	var g: float = luz_pestana
	var r_inward: float = 0.07 # Arqueo hacia el centro circular

	# Contrarriel central izquierdo (frente a p_o1)
	var pos_ci_mid: Vector3 = p_o1 + _dir_transversal * (g + 0.025) + Vector3(0.0, 0.025, 0.0)
	_agregar_contrarriel_curvado(st, pos_ci_mid, _dir_bisectriz, _dir_transversal, r_inward)

	# Contrarriel central derecho (frente a p_o2)
	var pos_cd_mid: Vector3 = p_o2 - _dir_transversal * (g + 0.025) + Vector3(0.0, 0.025, 0.0)
	_agregar_contrarriel_curvado(st, pos_cd_mid, _dir_bisectriz, -_dir_transversal, r_inward)

	# -------------------------------------------------------------------------
	# 2. CUATRO CONTRARRIELES EXTERIORES ACAMPANADOS EN LAS APROXIMACIONES
	# -------------------------------------------------------------------------
	var l_cr: float = 2.40
	# Vía A (opuestos a los corazones agudos)
	var ca_pos: Vector3 = posicion_centro + fwd_a * _s_agudo - side_a * (trocha_media - g - 0.02) + Vector3(0.0, 0.025, 0.0)
	var ca_neg: Vector3 = posicion_centro - fwd_a * _s_agudo + side_a * (trocha_media - g - 0.02) + Vector3(0.0, 0.025, 0.0)
	_agregar_contrarriel_acampanado_recto(st, ca_pos, l_cr, side_a, fwd_a)
	_agregar_contrarriel_acampanado_recto(st, ca_neg, l_cr, side_a, fwd_a)

	# Vía B
	var cb_pos: Vector3 = posicion_centro + fwd_b * _s_agudo - side_b * (trocha_media - g - 0.02) + Vector3(0.0, 0.025, 0.0)
	var cb_neg: Vector3 = posicion_centro - fwd_b * _s_agudo + side_b * (trocha_media - g - 0.02) + Vector3(0.0, 0.025, 0.0)
	_agregar_contrarriel_acampanado_recto(st, cb_pos, l_cr, side_b, fwd_b)
	_agregar_contrarriel_acampanado_recto(st, cb_neg, l_cr, side_b, fwd_b)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_contrarrieles = MeshInstance3D.new()
		_nodo_contrarrieles.name = "ContrarrielesProtectores"
		_nodo_contrarrieles.mesh = m
		_nodo_contrarrieles.material_override = material_riel
		add_child(_nodo_contrarrieles)


func _agregar_contrarriel_curvado(
	st: SurfaceTool,
	pos_centro: Vector3,
	dir_long: Vector3,
	dir_inward: Vector3,
	bow_amount: float
) -> void:
	# Genera el contrarriel interior arqueado con sección de caja de 40x150 mm
	var pasos: int = 10
	var l_total: float = 2.60
	var w: float = 0.035
	var h: float = 0.160
	var up: Vector3 = Vector3.UP

	var anillos: Array[PackedVector3Array] = []
	for p: int in pasos + 1:
		var u: float = float(p) / float(pasos) # 0 a 1
		var z_local: float = lerpf(-l_total * 0.5, l_total * 0.5, u)

		# Arqueamiento parabólico hacia el centro del diamante en los extremos
		var frac_end: float = absf(z_local) / (l_total * 0.5)
		var curve_offset: float = bow_amount * (frac_end * frac_end)

		var c_pt: Vector3 = pos_centro + dir_long * z_local + dir_inward * curve_offset
		anillos.append(PackedVector3Array([
			c_pt - dir_inward * (w * 0.5),
			c_pt + dir_inward * (w * 0.5),
			c_pt + dir_inward * (w * 0.5) - up * h,
			c_pt - dir_inward * (w * 0.5) - up * h
		]))

	_teselar_anillos(st, anillos, 4)


func _agregar_contrarriel_acampanado_recto(
	st: SurfaceTool,
	centro: Vector3,
	largo: float,
	dir_lateral: Vector3,
	dir_fwd: Vector3
) -> void:
	# Tramo central recto (70% del largo)
	var l_mid: float = largo * 0.70
	_agregar_box_orientado(st, centro, 0.035, 0.160, l_mid, dir_lateral, dir_fwd)

	# Extremos acampanados hacia adentro (flare de 25 mm)
	var l_flare: float = largo * 0.15
	var z_f1: float = (l_mid + l_flare) * 0.5
	var c_f1: Vector3 = centro + dir_fwd * z_f1 - dir_lateral * 0.018
	var c_f2: Vector3 = centro - dir_fwd * z_f1 - dir_lateral * 0.018
	_agregar_box_orientado(st, c_f1, 0.035, 0.160, l_flare, dir_lateral, dir_fwd)
	_agregar_box_orientado(st, c_f2, 0.035, 0.160, l_flare, dir_lateral, dir_fwd)


func _construir_marcador_central() -> void:
	# Círculo representativo en el centro geométrico del cruce (como en el diagrama C: Diamond Crossing)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radio: float = 0.18
	var altura: float = 0.035
	var segmentos: int = 16
	var c_top: Vector3 = posicion_centro + Vector3(0.0, -0.155, 0.0)

	st.set_normal(Vector3.UP)
	for i: int in segmentos:
		var a1: float = float(i) * TAU / float(segmentos)
		var a2: float = float(i + 1) * TAU / float(segmentos)
		var p1: Vector3 = c_top + Vector3(cos(a1) * radio, 0.0, sin(a1) * radio)
		var p2: Vector3 = c_top + Vector3(cos(a2) * radio, 0.0, sin(a2) * radio)
		st.add_vertex(c_top)
		st.add_vertex(p1)
		st.add_vertex(p2)

		# Lateral del cilindro
		var p1_b: Vector3 = p1 + Vector3(0.0, -altura, 0.0)
		var p2_b: Vector3 = p2 + Vector3(0.0, -altura, 0.0)
		var n: Vector3 = (p1 + p2 - c_top * 2.0).normalized()
		st.set_normal(n)
		st.add_vertex(p1); st.add_vertex(p1_b); st.add_vertex(p2_b)
		st.add_vertex(p1); st.add_vertex(p2_b); st.add_vertex(p2)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_marcador_centro = MeshInstance3D.new()
		_nodo_marcador_centro.name = "MarcadorCentroInterseccion"
		_nodo_marcador_centro.mesh = m
		_nodo_marcador_centro.material_override = material_metal
		add_child(_nodo_marcador_centro)


func _construir_indicador_ruta(fwd: Vector3) -> void:
	# Indicador de enclavamiento / farol de cruce a un costado
	var pos_m: Vector3 = posicion_centro - _dir_transversal * (_x_obtuso + 1.65)
	_construir_marmita_en(pos_m, fwd)


func _actualizar_indicador_ruta() -> void:
	if not mostrar_marmita or _nodo_marmita == null:
		return
	var rot_farol: float = deg_to_rad(90.0) if via_b_activa else 0.0
	var rot_pesa: float = deg_to_rad(-45.0) if via_b_activa else deg_to_rad(45.0)
	_aplicar_estado_marmita(via_b_activa, true, rot_farol, rot_pesa)


func _extruir_segmento(st: SurfaceTool, p0: Vector3, p1: Vector3, side: Vector3) -> void:
	var vec: Vector3 = p1 - p0
	var l: float = vec.length()
	if l < 0.08:
		return
	var dir: Vector3 = vec.normalized()
	var pasos: int = maxi(2, int(ceil(l / 0.85)))
	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_RIEL
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var pt_centro: Vector3 = p0 + dir * (float(p) * l / float(pasos))
		var t: Transform3D = Transform3D(Basis(side, Vector3.UP, dir), pt_centro)
		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(t * Vector3(pt.x, pt.y, 0.0))
		anillos.append(anillo)

	_teselar_anillos(st, anillos, perfil.size())


# ---------------------------------------------------------------------------
# INTERFAZ POLIMÓRFICA
# ---------------------------------------------------------------------------

func set_via_b(v: bool) -> void:
	via_b_activa = v


func obtener_curva_activa(_via_origen: int = 1) -> Curve3D:
	return curva_b if via_b_activa else curva_a


func obtener_trayectoria_completa(_via_origen: int = 1) -> Curve3D:
	var c_res: Curve3D = Curve3D.new()
	var g_ext: Node = get_node_or_null("ExtremosFlexibles")
	var usa_b: bool = via_b_activa
	var id_in: String = "Extremo_Via_B_Entrada" if usa_b else "Extremo_Via_A_Entrada"
	var id_out: String = "Extremo_Via_B_Salida" if usa_b else "Extremo_Via_A_Salida"
	var lead_in: Node = g_ext.get_node_or_null(id_in) if g_ext != null else null
	var lead_out: Node = g_ext.get_node_or_null(id_out) if g_ext != null else null
	var c_core: Curve3D = curva_b if usa_b else curva_a

	if lead_in != null:
		var c_in: Curve3D = lead_in.get("curve") as Curve3D
		if c_in != null:
			_muestrear_y_anexar_curva(c_res, c_in, true)
	if c_core != null:
		_muestrear_y_anexar_curva(c_res, c_core, false)
	if lead_out != null:
		var c_out: Curve3D = lead_out.get("curve") as Curve3D
		if c_out != null:
			_muestrear_y_anexar_curva(c_res, c_out, false)
	return c_res



func get_tipo_aparato() -> String:
	if not tipo_aparato_override.is_empty():
		return tipo_aparato_override
	return "TIPO_C"


func get_estado_descripcion() -> String:
	return "VIA_B" if via_b_activa else "VIA_A"


func is_desviado() -> bool:
	return via_b_activa


func conmutar_a(modo: int = 0) -> void:
	set_via_b(modo != 0)


func get_largo_aparato() -> float:
	return largo_zona_cruce
