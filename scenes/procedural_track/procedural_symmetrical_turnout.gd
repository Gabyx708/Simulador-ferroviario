@tool
class_name ProceduralSymmetricalTurnout
extends BaseTurnout
## Tipo B: Desvío Simétrico / Bifurcación en Y (Symmetrical Turnout) según norma T:ANE.
##
## Ambas vías abren simétricamente con igual radio y deflexión (+/- theta/2).
## Características:
##   • Dos contraagujas curvas continuas simétricas (stock rails).
##   • Dos espadines cónicos móviles centrados (switch blades).
##   • Barra de tracción transversal (stretcher bar).
##   • Rieles de cierre + patas de liebre + corazón en V central.
##   • Dos contrarrieles protectores simétricos.
##   • Marmita interactiva 3D con farol giratorio.
##
## Cinemática:
##   IZQUIERDA (ruta_derecha=false): Espadín derecho CERRADO, izquierdo ABIERTO.
##   DERECHA   (ruta_derecha=true):  Espadín izquierdo CERRADO, derecho ABIERTO.

signal estado_cambiado(es_derecha: bool)

@export_group("Geometría de Trazado")
@export var curva_izquierda: Curve3D = null:
	set(v):
		curva_izquierda = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export var curva_derecha: Curve3D = null:
	set(v):
		curva_derecha = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_range(14.0, 30.0, 0.5) var largo_turnout: float = 20.0:
	set(v):
		largo_turnout = maxf(12.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Estado de Aguja")
## false = Vía Izquierda  |  true = Vía Derecha
@export var ruta_derecha: bool = false:
	set(v):
		var cambio: bool = (ruta_derecha != v)
		ruta_derecha = v
		if cambio:
			_aplicar_posicion_agujas(false)
			estado_cambiado.emit(ruta_derecha)

@export_group("Dimensiones T:ANE")
@export var trocha_media: float = ProceduralTrackProfile.TROCHA_MEDIA_DEFECTO:
	set(v):
		trocha_media = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_range(3.5, 7.5, 0.25) var largo_aguja: float = 5.0:
	set(v):
		largo_aguja = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export var luz_pestana: float = 0.065
@export var paso_durmientes: float = ProceduralTrackProfile.PASO_DURMIENTES

# Nodos generados
var _nodo_balasto: MeshInstance3D = null
var _nodo_durmientes: MeshInstance3D = null
var _nodo_stock_rails: MeshInstance3D = null
var _nodo_frog: MeshInstance3D = null
var _nodo_checkrails: MeshInstance3D = null
var _nodo_slidechairs: MeshInstance3D = null
var _aguja_izq: MeshInstance3D = null    # Espadín izquierdo (cierra sobre curva_derecha)
var _aguja_der: MeshInstance3D = null    # Espadín derecho (cierra sobre curva_izquierda)
var _nodo_tirante: MeshInstance3D = null

# Datos calculados
var _len_izq: float = 20.0
var _len_der: float = 20.0
var _dist_frog: float = 14.5

var _pos_talon_i: Vector3 = Vector3.ZERO
var _pos_talon_d: Vector3 = Vector3.ZERO
var _basis_talon_i: Basis = Basis.IDENTITY
var _basis_talon_d: Basis = Basis.IDENTITY
var _rot_i_actual: float = 0.0
var _rot_d_actual: float = 0.0
var _ang_rot_aguja: float = 0.014

# Dirección y posición base del tirante (calculadas al construir)
var _dir_tirante: Vector3 = Vector3.RIGHT
var _pos_tirante_base: Vector3 = Vector3.ZERO


func _ready() -> void:
	_asegurar_materiales()
	if _nodo_stock_rails == null:
		construir_geometria()


func conmutar() -> void:
	ruta_derecha = not ruta_derecha


func limpiar() -> void:
	super.limpiar()
	_nodo_balasto = null
	_nodo_durmientes = null
	_nodo_stock_rails = null
	_nodo_frog = null
	_nodo_checkrails = null
	_nodo_slidechairs = null
	_aguja_izq = null
	_aguja_der = null
	_nodo_tirante = null
	_rot_i_actual = 0.0
	_rot_d_actual = 0.0


## Devuelve la lista de puertos de conexión en los extremos físicos de la bifurcación simétrica.
func obtener_puertos_conexion() -> Array[Dictionary]:
	if curva_izquierda == null or curva_derecha == null:
		return []
	var fwd_in: Vector3 = _tangente(curva_izquierda, 0.0)
	var fwd_izq: Vector3 = _tangente(curva_izquierda, _len_izq)
	var fwd_der: Vector3 = _tangente(curva_derecha, _len_der)
	return [
		{
			"id": "entrada_comun",
			"nombre": "Entrada Común (Talón)",
			"posicion": curva_izquierda.sample_baked(0.0),
			"direccion": -fwd_in
		},
		{
			"id": "salida_izquierda",
			"nombre": "Salida Izquierda",
			"posicion": curva_izquierda.sample_baked(_len_izq),
			"direccion": fwd_izq
		},
		{
			"id": "salida_derecha",
			"nombre": "Salida Derecha",
			"posicion": curva_derecha.sample_baked(_len_der),
			"direccion": fwd_der
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

	if curva_izquierda == null or curva_derecha == null:
		_bloqueo_reconstruccion = false
		return

	_len_izq = curva_izquierda.get_baked_length()
	_len_der = curva_derecha.get_baked_length()
	if _len_izq < 6.0 or _len_der < 6.0:
		_bloqueo_reconstruccion = false
		return

	largo_turnout = minf(largo_turnout, minf(_len_izq, _len_der))
	_asegurar_materiales()

	_dist_frog = _calcular_frog()
	var l_ag: float = clampf(largo_aguja, 3.8, _dist_frog - 2.5)
	var l_brazo: float = l_ag - 0.35
	_ang_rot_aguja = asin(clampf(0.115 / l_brazo, 0.015, 0.035))

	_construir_balasto()
	_construir_durmientes()
	_construir_silletas(l_ag)
	_construir_stock_rails()
	_construir_espadines_y_tirante(l_ag)
	_construir_frog_y_cierre(l_ag)
	_construir_contrarrieles()
	_construir_marmita_principal()

	_rot_i_actual = 0.0
	_rot_d_actual = 0.0
	_aplicar_posicion_agujas(true)
	aplicar_culling()
	if self.generar_extremos_flexibles:
		sincronizar_extremos_flexibles()

	_bloqueo_reconstruccion = false


# ===========================================================================
# HELPERS INTERNOS
# ===========================================================================

func _d_izq(d: float) -> float:
	if largo_turnout < 0.01:
		return 0.0
	return clampf(d * (_len_izq / largo_turnout), 0.0, _len_izq)


func _d_der(d: float) -> float:
	if largo_turnout < 0.01:
		return 0.0
	return clampf(d * (_len_der / largo_turnout), 0.0, _len_der)


func _calcular_frog() -> float:
	# Rieles interiores: izquierda en +trocha_media, derecha en -trocha_media
	var d_best: float = largo_turnout * 0.70
	var min_sep: float = 999.0
	var scan_d: float = 3.0
	while scan_d <= largo_turnout - 0.5:
		var pi: Vector3 = _punto_riel(curva_izquierda, _d_izq(scan_d), trocha_media)
		var pj: Vector3 = _punto_riel(curva_derecha, _d_der(scan_d), -trocha_media)
		var sep: float = pi.distance_to(pj)
		if sep < min_sep:
			min_sep = sep
			d_best = scan_d
		scan_d += 0.10

	var d_lo: float = maxf(3.0, d_best - 0.25)
	var d_hi: float = minf(largo_turnout - 0.2, d_best + 0.25)
	for _it: int in 12:
		var d_mid: float = (d_lo + d_hi) * 0.5
		var sep_m: float = _punto_riel(curva_izquierda, _d_izq(d_mid), trocha_media).distance_to(
			_punto_riel(curva_derecha, _d_der(d_mid), -trocha_media))
		var sep_p: float = _punto_riel(curva_izquierda, _d_izq(d_mid + 0.01), trocha_media).distance_to(
			_punto_riel(curva_derecha, _d_der(d_mid + 0.01), -trocha_media))
		if sep_p < sep_m:
			d_lo = d_mid
		else:
			d_hi = d_mid
		d_best = d_mid
	return d_best


# ===========================================================================
# BLOQUES DE CONSTRUCCIÓN
# ===========================================================================

func _construir_balasto() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pasos: int = maxi(4, int(ceil(largo_turnout / 1.5)))
	var anillos: Array[PackedVector3Array] = []

	for p: int in pasos + 1:
		var d: float = float(p) * largo_turnout / float(pasos)
		var p_i: Vector3 = curva_izquierda.sample_baked(_d_izq(d))
		var p_d: Vector3 = curva_derecha.sample_baked(_d_der(d))
		var fwd_i: Vector3 = _tangente(curva_izquierda, _d_izq(d))
		var fwd_d: Vector3 = _tangente(curva_derecha, _d_der(d))
		var side_i: Vector3 = Vector3.UP.cross(fwd_i).normalized()
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()

		# Hombro superior a 2.00m de trocha y talud a 2.70m en base (calce exacto con PERFIL_BALASTO)
		var pt_ext_izq: Vector3 = p_i - side_i * (trocha_media + 1.162)
		var pt_ext_der: Vector3 = p_d + side_d * (trocha_media + 1.162)
		var side_m: Vector3 = (pt_ext_der - pt_ext_izq).normalized()

		anillos.append(PackedVector3Array([
			pt_ext_izq - side_m * 0.70 + Vector3(0.0, -0.65, 0.0),
			pt_ext_der + side_m * 0.70 + Vector3(0.0, -0.65, 0.0),
			pt_ext_der + Vector3(0.0, -0.28, 0.0),
			pt_ext_izq + Vector3(0.0, -0.28, 0.0),
		]))
	_teselar_anillos(st, anillos, 4)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_balasto = MeshInstance3D.new()
		_nodo_balasto.name = "Balasto"
		_nodo_balasto.mesh = m
		_nodo_balasto.material_override = material_balasto
		agregar_a_geometria_fija(_nodo_balasto)


func _construir_durmientes() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cantidad: int = int(largo_turnout / paso_durmientes)
	var voladizo: float = 0.45

	for i: int in cantidad:
		var d: float = (float(i) + 0.5) * paso_durmientes
		var p_i: Vector3 = curva_izquierda.sample_baked(_d_izq(d))
		var p_d: Vector3 = curva_derecha.sample_baked(_d_der(d))
		var fwd_i: Vector3 = _tangente(curva_izquierda, _d_izq(d))
		var fwd_d: Vector3 = _tangente(curva_derecha, _d_der(d))
		var side_i: Vector3 = Vector3.UP.cross(fwd_i).normalized()
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()

		var pt_ext_izq: Vector3 = p_i - side_i * (trocha_media + voladizo)
		var pt_ext_der: Vector3 = p_d + side_d * (trocha_media + voladizo)

		var vec_eje: Vector3 = pt_ext_der - pt_ext_izq
		var largo_t: float = maxf(2.60, vec_eje.length())
		var dir_t: Vector3 = vec_eje.normalized()
		var fwd_t: Vector3 = dir_t.cross(Vector3.UP).normalized()
		var centro: Vector3 = (pt_ext_izq + pt_ext_der) * 0.5 + Vector3(0.0, -0.28, 0.0)

		# Primer durmiente (punta de aguja) se extiende para la marmita
		if absf(d - 0.55) < 0.35:
			largo_t += 1.20
			centro -= dir_t * 0.60

		_agregar_box_orientado(st, centro, largo_t, 0.20, 0.26, dir_t, fwd_t)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_durmientes = MeshInstance3D.new()
		_nodo_durmientes.name = "Durmientes"
		_nodo_durmientes.mesh = m
		_nodo_durmientes.material_override = material_durmiente
		agregar_a_geometria_fija(_nodo_durmientes)


func _construir_silletas(l_ag: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cantidad: int = int(l_ag / paso_durmientes)

	for i: int in cantidad:
		var d: float = (float(i) + 0.5) * paso_durmientes
		if d > l_ag:
			break
		var fwd_i: Vector3 = _tangente(curva_izquierda, _d_izq(d))
		var fwd_d: Vector3 = _tangente(curva_derecha, _d_der(d))
		var side_i: Vector3 = Vector3.UP.cross(fwd_i).normalized()
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()

		# Silleta bajo contraaguja derecha y espadín de vía izquierda (en curva_derecha, +trocha_media)
		var pd: Vector3 = _punto_riel(curva_derecha, _d_der(d), trocha_media)
		var pos_cd: Vector3 = pd - side_d * 0.08 + Vector3(0.0, -0.165, 0.0)
		_agregar_box_orientado(st, pos_cd, 0.28, 0.025, 0.18, side_d, fwd_d)

		# Silleta bajo contraaguja izquierda y espadín de vía derecha (en curva_izquierda, -trocha_media)
		var pi: Vector3 = _punto_riel(curva_izquierda, _d_izq(d), -trocha_media)
		var pos_ci: Vector3 = pi + side_i * 0.08 + Vector3(0.0, -0.165, 0.0)
		_agregar_box_orientado(st, pos_ci, 0.28, 0.025, 0.18, side_i, fwd_i)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_slidechairs = MeshInstance3D.new()
		_nodo_slidechairs.name = "Silletas"
		_nodo_slidechairs.mesh = m
		_nodo_slidechairs.material_override = material_metal
		agregar_a_geometria_fija(_nodo_slidechairs)


func _construir_stock_rails() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Exterior izquierda en -trocha_media, exterior derecha en +trocha_media
	_extruir_riel(st, curva_izquierda, 0.0, _len_izq, -trocha_media)
	_extruir_riel(st, curva_derecha, 0.0, _len_der, trocha_media)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_stock_rails = MeshInstance3D.new()
		_nodo_stock_rails.name = "StockRails"
		_nodo_stock_rails.mesh = m
		_nodo_stock_rails.material_override = material_riel
		agregar_a_geometria_fija(_nodo_stock_rails)


func _construir_espadines_y_tirante(l_ag: float) -> void:
	var d_toe: float = 0.35

	# --- 1. Espadín para Vía Izquierda (en curva_izquierda, offset +trocha_media) ---
	# Cierra contra la contraaguja derecha cuando ruta_derecha=false (ruta izquierda activa).
	# Se abre hacia el centro (115 mm) cuando ruta_derecha=true.
	var d_heel_i: float = _d_izq(l_ag)
	var d_toe_i: float = _d_izq(d_toe)
	_pos_talon_i = _punto_riel(curva_izquierda, d_heel_i, trocha_media)
	var fwd_ti: Vector3 = _tangente(curva_izquierda, d_heel_i)
	var side_ti: Vector3 = Vector3.UP.cross(fwd_ti).normalized()
	_basis_talon_i = Basis(side_ti, Vector3.UP, fwd_ti)

	var mesh_i: ArrayMesh = _generar_malla_espadin_mecanizado(
		curva_izquierda, d_toe_i, d_heel_i, trocha_media, 1.0, _pos_talon_i, _basis_talon_i
	)
	if mesh_i != null and mesh_i.get_surface_count() > 0:
		_aguja_izq = MeshInstance3D.new()
		_aguja_izq.name = "Espadin_ViaIzquierda"
		_aguja_izq.transform = Transform3D(_basis_talon_i, _pos_talon_i)
		_aguja_izq.mesh = mesh_i
		_aguja_izq.material_override = material_riel
		agregar_a_mecanismo(_aguja_izq)

	# --- 2. Espadín para Vía Derecha (en curva_derecha, offset -trocha_media) ---
	# Cierra contra la contraaguja izquierda cuando ruta_derecha=true (ruta derecha activa).
	# Se abre hacia el centro (115 mm) cuando ruta_derecha=false.
	var d_heel_d: float = _d_der(l_ag)
	var d_toe_d: float = _d_der(d_toe)
	_pos_talon_d = _punto_riel(curva_derecha, d_heel_d, -trocha_media)
	var fwd_td: Vector3 = _tangente(curva_derecha, d_heel_d)
	var side_td: Vector3 = Vector3.UP.cross(fwd_td).normalized()
	_basis_talon_d = Basis(side_td, Vector3.UP, fwd_td)

	var mesh_d: ArrayMesh = _generar_malla_espadin_mecanizado(
		curva_derecha, d_toe_d, d_heel_d, -trocha_media, -1.0, _pos_talon_d, _basis_talon_d
	)
	if mesh_d != null and mesh_d.get_surface_count() > 0:
		_aguja_der = MeshInstance3D.new()
		_aguja_der.name = "Espadin_ViaDerecha"
		_aguja_der.transform = Transform3D(_basis_talon_d, _pos_talon_d)
		_aguja_der.mesh = mesh_d
		_aguja_der.material_override = material_riel
		agregar_a_mecanismo(_aguja_der)

	# --- 3. Tirantes Transversales de Accionamiento (Doble tirante con abrazaderas) ---
	var d_bar1: float = 0.55
	var d_bar2: float = 1.60
	var p_bar1_i: Vector3 = _punto_riel(curva_izquierda, _d_izq(d_bar1), -trocha_media)
	var p_bar1_d: Vector3 = _punto_riel(curva_derecha, _d_der(d_bar1), trocha_media)
	_dir_tirante = (p_bar1_d - p_bar1_i).normalized()
	var fwd_bar1: Vector3 = (_tangente(curva_izquierda, _d_izq(d_bar1)) + _tangente(curva_derecha, _d_der(d_bar1))).normalized()
	var c_bar1: Vector3 = (p_bar1_i + p_bar1_d) * 0.5 + Vector3(0.0, -0.06, 0.0)
	var l_bar1: float = p_bar1_i.distance_to(p_bar1_d) - 0.06
	_pos_tirante_base = c_bar1

	var p_bar2_i: Vector3 = _punto_riel(curva_izquierda, _d_izq(d_bar2), -trocha_media)
	var p_bar2_d: Vector3 = _punto_riel(curva_derecha, _d_der(d_bar2), trocha_media)
	var c_bar2: Vector3 = (p_bar2_i + p_bar2_d) * 0.5 + Vector3(0.0, -0.06, 0.0)
	var l_bar2: float = p_bar2_i.distance_to(p_bar2_d) - 0.06

	var st_b: SurfaceTool = SurfaceTool.new()
	st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tirante 1 (punta)
	_agregar_box_orientado(st_b, Vector3.ZERO, l_bar1, 0.035, 0.065, _dir_tirante, fwd_bar1)
	# Tirante 2 (secundario)
	var offset_bar2: Vector3 = c_bar2 - c_bar1
	_agregar_box_orientado(st_b, offset_bar2, l_bar2, 0.030, 0.055, _dir_tirante, fwd_bar1)
	# Abrazaderas verticales de unión a las almas de los espadines
	_agregar_box_orientado(st_b, -_dir_tirante * (l_bar1 * 0.48) + Vector3(0.0, 0.04, 0.0), 0.05, 0.08, 0.08, _dir_tirante, fwd_bar1)
	_agregar_box_orientado(st_b, _dir_tirante * (l_bar1 * 0.48) + Vector3(0.0, 0.04, 0.0), 0.05, 0.08, 0.08, _dir_tirante, fwd_bar1)

	var m_b: ArrayMesh = st_b.commit()
	if m_b != null and m_b.get_surface_count() > 0:
		_nodo_tirante = MeshInstance3D.new()
		_nodo_tirante.name = "Tirantes_Accionamiento"
		_nodo_tirante.position = c_bar1
		_nodo_tirante.mesh = m_b
		_nodo_tirante.material_override = material_metal
		agregar_a_mecanismo(_nodo_tirante)


func _construir_frog_y_cierre(l_ag: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var d_ws: float = _dist_frog - 0.85
	var d_we: float = _dist_frog - 0.08
	var d_vs: float = _dist_frog + 0.08
	var d_vsp: float = _dist_frog + 1.25

	# Rieles de cierre interiores hasta la garganta
	_extruir_riel(st, curva_izquierda, _d_izq(l_ag), _d_izq(d_ws), trocha_media)
	_extruir_wing_rail(st, curva_izquierda, _d_izq(d_ws), _d_izq(d_we), trocha_media, 0.055)
	_extruir_riel(st, curva_derecha, _d_der(l_ag), _d_der(d_ws), -trocha_media)
	_extruir_wing_rail(st, curva_derecha, _d_der(d_ws), _d_der(d_we), -trocha_media, -0.055)

	# Corazón en V central
	var pasos_v: int = 10
	var anillos_v: Array[PackedVector3Array] = []
	for p: int in pasos_v + 1:
		var frac: float = float(p) / float(pasos_v)
		var d: float = lerpf(d_vs, d_vsp, frac)
		var pi: Vector3 = _punto_riel(curva_izquierda, _d_izq(d), trocha_media)
		var pd: Vector3 = _punto_riel(curva_derecha, _d_der(d), -trocha_media)
		var c_pt: Vector3 = (pi + pd) * 0.5
		var w_v: float = maxf(0.012, pi.distance_to(pd) + 0.055)
		var fwd: Vector3 = (_tangente(curva_izquierda, _d_izq(d)) + _tangente(curva_derecha, _d_der(d))).normalized()
		var side: Vector3 = Vector3.UP.cross(fwd).normalized()
		anillos_v.append(PackedVector3Array([
			c_pt - side * (w_v * 0.5),
			c_pt + side * (w_v * 0.5),
			c_pt + side * (w_v * 0.5) + Vector3(0.0, -0.150, 0.0),
			c_pt - side * (w_v * 0.5) + Vector3(0.0, -0.150, 0.0),
		]))
	_teselar_anillos(st, anillos_v, 4)

	# Rieles independientes desde corazón hasta el final
	_extruir_riel(st, curva_izquierda, _d_izq(d_vsp), _len_izq, trocha_media)
	_extruir_riel(st, curva_derecha, _d_der(d_vsp), _len_der, -trocha_media)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_frog = MeshInstance3D.new()
		_nodo_frog.name = "CorazonSimetrico"
		_nodo_frog.mesh = m
		_nodo_frog.material_override = material_riel
		agregar_a_geometria_fija(_nodo_frog)


func _construir_contrarrieles() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d0: float = maxf(1.0, _dist_frog - 1.45)
	var d1: float = minf(largo_turnout - 0.5, _dist_frog + 1.45)

	_extruir_contrarriel_acampanado(st, curva_izquierda, _d_izq(d0), _d_izq(d1), -trocha_media, luz_pestana)
	_extruir_contrarriel_acampanado(st, curva_derecha, _d_der(d0), _d_der(d1), trocha_media, -luz_pestana)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_checkrails = MeshInstance3D.new()
		_nodo_checkrails.name = "Contrarrieles"
		_nodo_checkrails.mesh = m
		_nodo_checkrails.material_override = material_metal
		agregar_a_geometria_fija(_nodo_checkrails)


func _construir_marmita_principal() -> void:
	var d_m: float = 0.55
	var p0: Vector3 = curva_izquierda.sample_baked(_d_izq(d_m))
	var fwd0: Vector3 = _tangente(curva_izquierda, _d_izq(d_m))
	var side0: Vector3 = Vector3.UP.cross(fwd0).normalized()
	var pos_m: Vector3 = p0 - side0 * (trocha_media + 1.20)
	_construir_marmita_en(pos_m, fwd0)


# ===========================================================================
# CINEMÁTICA DE AGUJAS
# ===========================================================================

## Cinemática simétrica:
##   IZQUIERDA (ruta_derecha=false): Espadín Vía Izquierda CERRADO (rot=0) / Espadín Vía Derecha ABIERTO (rot ≠ 0).
##   DERECHA   (ruta_derecha=true):  Espadín Vía Derecha CERRADO (rot=0) / Espadín Vía Izquierda ABIERTO (rot ≠ 0).
func _aplicar_posicion_agujas(inmediato: bool) -> void:
	_asegurar_materiales()

	# Espadín de vía izquierda (en +trocha_media):
	# CERRADO (rot=0) cuando ruta_izquierda (ruta_derecha=false)
	# ABIERTO  (rot=+_ang_rot_aguja hacia el centro) cuando ruta_derecha=true
	var rot_i_obj: float = _ang_rot_aguja if ruta_derecha else 0.0

	# Espadín de vía derecha (en -trocha_media):
	# CERRADO (rot=0) cuando ruta_derecha=true
	# ABIERTO  (rot=-_ang_rot_aguja hacia el centro) cuando ruta_izquierda (ruta_derecha=false)
	var rot_d_obj: float = 0.0 if ruta_derecha else -_ang_rot_aguja

	# El tirante se desplaza 115 mm entre posiciones
	var shift_tirante: float = -0.0575 if ruta_derecha else 0.0575

	var rot_farol: float = deg_to_rad(90.0) if ruta_derecha else 0.0
	var rot_pesa: float = deg_to_rad(-45.0) if ruta_derecha else deg_to_rad(45.0)

	_aplicar_estado_marmita(ruta_derecha, not inmediato, rot_farol, rot_pesa)

	if _tween_agujas != null and _tween_agujas.is_valid():
		_tween_agujas.kill()

	if inmediato or not is_inside_tree():
		_set_rot_izq(rot_i_obj)
		_set_rot_der(rot_d_obj)
		if _nodo_tirante != null:
			_nodo_tirante.position = _pos_tirante_base + _dir_tirante * shift_tirante
	else:
		_tween_agujas = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween_agujas.tween_method(_set_rot_izq, _rot_i_actual, rot_i_obj, 0.35)
		_tween_agujas.tween_method(_set_rot_der, _rot_d_actual, rot_d_obj, 0.35)
		if _nodo_tirante != null:
			_tween_agujas.tween_property(_nodo_tirante, "position", _pos_tirante_base + _dir_tirante * shift_tirante, 0.35)


func _set_rot_izq(ang: float) -> void:
	_rot_i_actual = ang
	if _aguja_izq != null:
		_aguja_izq.basis = _basis_talon_i.rotated(Vector3.UP, ang)


func _set_rot_der(ang: float) -> void:
	_rot_d_actual = ang
	if _aguja_der != null:
		_aguja_der.basis = _basis_talon_d.rotated(Vector3.UP, ang)


# ---------------------------------------------------------------------------
# INTERFAZ POLIMÓRFICA
# ---------------------------------------------------------------------------

func set_ruta_derecha(v: bool, animar: bool = true) -> void:
	ruta_derecha = v
	if not animar:
		_aplicar_posicion_agujas(true)


func obtener_curva_activa(_via_origen: int = 1) -> Curve3D:
	return curva_derecha if ruta_derecha else curva_izquierda


func obtener_trayectoria_completa(_via_origen: int = 1) -> Curve3D:
	var c_res: Curve3D = Curve3D.new()
	var g_ext: Node = get_node_or_null("ExtremosFlexibles")
	var lead_in: Node = g_ext.get_node_or_null("Extremo_Entrada_Comun") if g_ext != null else null
	var id_out: String = "Extremo_Salida_Derecha" if ruta_derecha else "Extremo_Salida_Izquierda"
	var lead_out: Node = g_ext.get_node_or_null(id_out) if g_ext != null else null
	var c_core: Curve3D = obtener_curva_activa()

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
	return "TIPO_B"


func get_estado_descripcion() -> String:
	return "RAMA_DERECHA" if ruta_derecha else "RAMA_IZQUIERDA"


func is_desviado() -> bool:
	return ruta_derecha


func conmutar_a(modo: int = 0) -> void:
	set_ruta_derecha(modo != 0)


func get_largo_aparato() -> float:
	return largo_turnout

