@tool
class_name ProceduralTurnout
extends BaseTurnout
## Tipo A: Desvío Estándar Asimétrico (Standard Turnout) según norma T:ANE / UIC.
##
## Geometría canónica:
##   • Dos contraagujas exteriores continuas (stock rails).
##   • Dos espadines cónicos móviles (switch blades) articulados en el talón.
##   • Barra de tracción transversal (stretcher bar).
##   • Rieles de cierre + patas de liebre + corazón en V mecanizado (frog).
##   • Contrarrieles protectores con bocas acampanadas.
##   • Marmita interactiva 3D con farol giratorio.
##
## Cinemática de agujas:
##   DIRECTA  (aguja_desviada=false): Espadín interior cerrado   / Espadín curvo abierto.
##   DESVIADA (aguja_desviada=true):  Espadín interior abierto   / Espadín curvo cerrado.

signal estado_cambiado(es_desviada: bool)

@export_group("Geometría de Trazado")
@export var curva_directa: Curve3D = null:
	set(v):
		curva_directa = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export var curva_desviada: Curve3D = null:
	set(v):
		curva_desviada = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_range(14.0, 35.0, 0.5) var largo_turnout: float = 22.0:
	set(v):
		largo_turnout = maxf(12.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Estado de Aguja")
## false = Vía Directa  |  true = Vía Desviada
@export var aguja_desviada: bool = false:
	set(v):
		var cambio: bool = (aguja_desviada != v)
		aguja_desviada = v
		if cambio:
			_aplicar_posicion_agujas(false)
			estado_cambiado.emit(aguja_desviada)

@export_group("Dimensiones T:ANE")
@export var trocha_media: float = ProceduralTrackProfile.TROCHA_MEDIA_DEFECTO:
	set(v):
		trocha_media = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_range(3.5, 7.5, 0.25) var largo_aguja: float = 5.5:
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
var _aguja_interior: MeshInstance3D = null   # Espadín interior (lado del desvío)
var _aguja_exterior: MeshInstance3D = null   # Espadín exterior (lado continuo)
var _nodo_tirante: MeshInstance3D = null

# Datos calculados
var _lado_s: float = 1.0         # +1.0 = desvío a Derecha (+X), -1.0 = a Izquierda (-X)
var _len_desv: float = 22.0
var _dist_frog: float = 18.0

# Talones de cada espadín (pivotes de rotación)
var _pos_talon_int: Vector3 = Vector3.ZERO   # Talón del espadín interior
var _pos_talon_ext: Vector3 = Vector3.ZERO   # Talón del espadín exterior
var _basis_talon_int: Basis = Basis.IDENTITY
var _basis_talon_ext: Basis = Basis.IDENTITY

# Ángulo actual de rotación de cada espadín (se mantiene entre frames para tween suave)
var _rot_int_actual: float = 0.0
var _rot_ext_actual: float = 0.0
var _ang_rot_aguja: float = 0.013

# Dirección lateral del tirante y posición base (calculadas al construir)
var _dir_tirante: Vector3 = Vector3.RIGHT
var _pos_tirante_base: Vector3 = Vector3.ZERO


func _ready() -> void:
	_asegurar_materiales()
	if _nodo_stock_rails == null:
		construir_geometria()


func conmutar() -> void:
	aguja_desviada = not aguja_desviada


func limpiar() -> void:
	super.limpiar()
	_nodo_balasto = null
	_nodo_durmientes = null
	_nodo_stock_rails = null
	_nodo_frog = null
	_nodo_checkrails = null
	_nodo_slidechairs = null
	_aguja_interior = null
	_aguja_exterior = null
	_nodo_tirante = null
	_rot_int_actual = 0.0
	_rot_ext_actual = 0.0


## Devuelve la lista de puertos de conexión en los extremos físicos del desvío.
func obtener_puertos_conexion() -> Array[Dictionary]:
	if curva_directa == null or curva_desviada == null:
		return []
	var fwd_in: Vector3 = _tangente(curva_directa, 0.0)
	var fwd_dir: Vector3 = _tangente(curva_directa, largo_turnout)
	var fwd_desv: Vector3 = _tangente(curva_desviada, _len_desv)
	return [
		{
			"id": "entrada_comun",
			"nombre": "Entrada Común (Talón)",
			"posicion": curva_directa.sample_baked(0.0),
			"direccion": -fwd_in
		},
		{
			"id": "salida_directa",
			"nombre": "Salida Directa",
			"posicion": curva_directa.sample_baked(largo_turnout),
			"direccion": fwd_dir
		},
		{
			"id": "salida_desviada",
			"nombre": "Salida Desviada",
			"posicion": curva_desviada.sample_baked(_len_desv),
			"direccion": fwd_desv
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

	if curva_directa == null or curva_desviada == null:
		_bloqueo_reconstruccion = false
		return

	var l_dir: float = curva_directa.get_baked_length()
	_len_desv = curva_desviada.get_baked_length()
	if l_dir < 6.0 or _len_desv < 6.0:
		_bloqueo_reconstruccion = false
		return

	largo_turnout = minf(largo_turnout, l_dir)
	_asegurar_materiales()

	_lado_s = _determinar_lado()
	_dist_frog = _calcular_frog()

	var l_ag: float = clampf(largo_aguja, 3.8, _dist_frog - 3.5)
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

	# Aplica posición inicial de agujas sin animación
	_rot_int_actual = 0.0
	_rot_ext_actual = 0.0
	_aplicar_posicion_agujas(true)
	aplicar_culling()
	if self.generar_extremos_flexibles:
		sincronizar_extremos_flexibles()

	_bloqueo_reconstruccion = false


# ===========================================================================
# HELPERS INTERNOS DE CURVA
# ===========================================================================

## Mapea d de la vía directa al arc-length equivalente en la curva desviada.
func _d_desv(d_dir: float) -> float:
	if largo_turnout < 0.01:
		return 0.0
	return clampf(d_dir * (_len_desv / largo_turnout), 0.0, _len_desv)


func _determinar_lado() -> float:
	var d_test: float = minf(4.0, largo_turnout * 0.35)
	var p_d: Vector3 = curva_directa.sample_baked(d_test)
	var p_v: Vector3 = curva_desviada.sample_baked(_d_desv(d_test))
	var fwd: Vector3 = _tangente(curva_directa, d_test)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	return 1.0 if (p_v - p_d).dot(side) >= 0.0 else -1.0


func _calcular_frog() -> float:
	# Búsqueda gruesa del punto de separación mínima entre rieles interiores
	var d_best: float = largo_turnout * 0.75
	var min_sep: float = 999.0
	var scan_d: float = 4.0
	while scan_d <= largo_turnout - 0.5:
		var pi: Vector3 = _punto_riel(curva_directa, scan_d, trocha_media * _lado_s)
		var pj: Vector3 = _punto_riel(curva_desviada, _d_desv(scan_d), trocha_media * -_lado_s)
		var sep: float = pi.distance_to(pj)
		if sep < min_sep:
			min_sep = sep
			d_best = scan_d
		scan_d += 0.10

	# Refinamiento binario
	var d_lo: float = maxf(4.0, d_best - 0.25)
	var d_hi: float = minf(largo_turnout - 0.2, d_best + 0.25)
	for _it: int in 12:
		var d_mid: float = (d_lo + d_hi) * 0.5
		var sep_mid: float = _punto_riel(curva_directa, d_mid, trocha_media * _lado_s).distance_to(
			_punto_riel(curva_desviada, _d_desv(d_mid), trocha_media * -_lado_s))
		var sep_p: float = _punto_riel(curva_directa, d_mid + 0.01, trocha_media * _lado_s).distance_to(
			_punto_riel(curva_desviada, _d_desv(d_mid + 0.01), trocha_media * -_lado_s))
		if sep_p < sep_mid:
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
		var p_d: Vector3 = curva_directa.sample_baked(d)
		var p_v: Vector3 = curva_desviada.sample_baked(_d_desv(d))
		var fwd_d: Vector3 = _tangente(curva_directa, d)
		var fwd_v: Vector3 = _tangente(curva_desviada, _d_desv(d))
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()
		var side_v: Vector3 = Vector3.UP.cross(fwd_v).normalized()

		# Hombro superior a 2.00m de trocha y talud a 2.70m en base (calce exacto con PERFIL_BALASTO)
		var pt_ext_cont: Vector3 = p_d - side_d * (trocha_media + 1.162) * _lado_s
		var pt_ext_desv: Vector3 = p_v + side_v * (trocha_media + 1.162) * _lado_s
		var pt_izq: Vector3 = pt_ext_cont if _lado_s > 0.0 else pt_ext_desv
		var pt_der: Vector3 = pt_ext_desv if _lado_s > 0.0 else pt_ext_cont

		var side_m: Vector3 = (pt_der - pt_izq).normalized()
		var v0: Vector3 = pt_izq - side_m * 0.70 + Vector3(0.0, -0.65, 0.0)
		var v1: Vector3 = pt_der + side_m * 0.70 + Vector3(0.0, -0.65, 0.0)
		var v2: Vector3 = pt_der + Vector3(0.0, -0.28, 0.0)
		var v3: Vector3 = pt_izq + Vector3(0.0, -0.28, 0.0)
		anillos.append(PackedVector3Array([v0, v1, v2, v3]))
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
		var p_d: Vector3 = curva_directa.sample_baked(d)
		var p_v: Vector3 = curva_desviada.sample_baked(_d_desv(d))
		var fwd_d: Vector3 = _tangente(curva_directa, d)
		var fwd_v: Vector3 = _tangente(curva_desviada, _d_desv(d))
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()
		var side_v: Vector3 = Vector3.UP.cross(fwd_v).normalized()
		var fwd_m: Vector3 = (fwd_d + fwd_v).normalized()

		var p_ext_cont: Vector3 = p_d - side_d * (trocha_media + voladizo) * _lado_s
		var p_ext_desv: Vector3 = p_v + side_v * (trocha_media + voladizo) * _lado_s
		if d < 2.2:
			p_ext_cont -= side_d * (1.10 * _lado_s)

		var p_izq: Vector3 = p_ext_cont if _lado_s > 0.0 else p_ext_desv
		var p_der: Vector3 = p_ext_desv if _lado_s > 0.0 else p_ext_cont
		var largo_d: float = p_izq.distance_to(p_der)
		var centro: Vector3 = (p_izq + p_der) * 0.5 + Vector3(0.0, -0.25, 0.0)
		var dir_d: Vector3 = (p_der - p_izq).normalized()
		_agregar_box_orientado(st, centro, largo_d, 0.20, 0.26, dir_d, fwd_m)

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
	var n: int = int(l_ag / paso_durmientes)

	for i: int in n:
		var d: float = (float(i) + 0.5) * paso_durmientes
		var fwd_d: Vector3 = _tangente(curva_directa, d)
		var side_d: Vector3 = Vector3.UP.cross(fwd_d).normalized()

		# Silleta bajo espadín interior (lado del desvío)
		var pa: Vector3 = _punto_riel(curva_directa, d, trocha_media * _lado_s)
		var pos_a: Vector3 = pa - side_d * (0.07 * _lado_s) + Vector3(0.0, -0.165, 0.0)
		_agregar_box_orientado(st, pos_a, 0.38, 0.025, 0.22, side_d, fwd_d)

		# Silleta bajo espadín exterior (lado continuo)
		var pb: Vector3 = _punto_riel(curva_desviada, _d_desv(d), trocha_media * -_lado_s)
		var pos_b: Vector3 = pb + side_d * (0.07 * _lado_s) + Vector3(0.0, -0.165, 0.0)
		_agregar_box_orientado(st, pos_b, 0.38, 0.025, 0.22, side_d, fwd_d)

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

	# Contraaguja recta exterior (lado continuo, opuesto al desvío)
	_extruir_riel(st, curva_directa, 0.0, largo_turnout, trocha_media * -_lado_s)
	# Contraaguja curva exterior (curva desviada, lado exterior)
	_extruir_riel(st, curva_desviada, 0.0, _len_desv, trocha_media * _lado_s)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_stock_rails = MeshInstance3D.new()
		_nodo_stock_rails.name = "StockRails"
		_nodo_stock_rails.mesh = m
		_nodo_stock_rails.material_override = material_riel
		agregar_a_geometria_fija(_nodo_stock_rails)


func _construir_espadines_y_tirante(l_ag: float) -> void:
	var d_toe: float = 0.35

	# 1. ESPADÍN RECTO (sobre curva_directa, del lado de la divergencia +lado)
	# CERRADO en DIRECTA (apoya contra la contraaguja curva), ABIERTO en DESVIADA (115 mm de luz)
	_pos_talon_int = _punto_riel(curva_directa, l_ag, trocha_media * _lado_s)
	var fwd_t_int: Vector3 = _tangente(curva_directa, l_ag)
	var side_t_int: Vector3 = Vector3.UP.cross(fwd_t_int).normalized()
	_basis_talon_int = Basis(side_t_int, Vector3.UP, fwd_t_int)

	var mesh_recto: ArrayMesh = _generar_malla_espadin_mecanizado(
		curva_directa, d_toe, l_ag, trocha_media * _lado_s, _lado_s, _pos_talon_int, _basis_talon_int
	)
	if mesh_recto != null and mesh_recto.get_surface_count() > 0:
		_aguja_interior = MeshInstance3D.new()
		_aguja_interior.name = "Espadin_Recto"
		_aguja_interior.transform = Transform3D(_basis_talon_int, _pos_talon_int)
		_aguja_interior.mesh = mesh_recto
		_aguja_interior.material_override = material_riel
		agregar_a_mecanismo(_aguja_interior)

	# 2. ESPADÍN CURVO (sobre curva_desviada, del lado recto -lado)
	# ABIERTO en DIRECTA (115 mm de luz), CERRADO en DESVIADA (apoya contra contraaguja recta)
	var d_heel_desv: float = _d_desv(l_ag)
	_pos_talon_ext = _punto_riel(curva_desviada, d_heel_desv, trocha_media * -_lado_s)
	var fwd_t_ext: Vector3 = _tangente(curva_desviada, d_heel_desv)
	var side_t_ext: Vector3 = Vector3.UP.cross(fwd_t_ext).normalized()
	_basis_talon_ext = Basis(side_t_ext, Vector3.UP, fwd_t_ext)

	var mesh_curvo: ArrayMesh = _generar_malla_espadin_mecanizado(
		curva_desviada, d_toe, d_heel_desv, trocha_media * -_lado_s, -_lado_s, _pos_talon_ext, _basis_talon_ext
	)
	if mesh_curvo != null and mesh_curvo.get_surface_count() > 0:
		_aguja_exterior = MeshInstance3D.new()
		_aguja_exterior.name = "Espadin_Curvo"
		_aguja_exterior.transform = Transform3D(_basis_talon_ext, _pos_talon_ext)
		_aguja_exterior.mesh = mesh_curvo
		_aguja_exterior.material_override = material_riel
		agregar_a_mecanismo(_aguja_exterior)

	# 3. TIRANTES TRANSVERSALES DE ACCIONAMIENTO (Doble tirante con abrazaderas)
	var d_bar1: float = 0.55
	var d_bar2: float = 1.60
	var p_bar_a: Vector3 = _punto_riel(curva_directa, d_bar1, trocha_media * _lado_s)
	var p_bar_b: Vector3 = _punto_riel(curva_desviada, _d_desv(d_bar1), trocha_media * -_lado_s)
	_dir_tirante = (p_bar_b - p_bar_a).normalized()
	var fwd_bar: Vector3 = _tangente(curva_directa, d_bar1)
	var c_bar1: Vector3 = (p_bar_a + p_bar_b) * 0.5 + Vector3(0.0, -0.06, 0.0)
	var l_bar1: float = p_bar_a.distance_to(p_bar_b) - 0.06
	_pos_tirante_base = c_bar1

	var p2_a: Vector3 = _punto_riel(curva_directa, d_bar2, trocha_media * _lado_s)
	var p2_b: Vector3 = _punto_riel(curva_desviada, _d_desv(d_bar2), trocha_media * -_lado_s)
	var c_bar2: Vector3 = (p2_a + p2_b) * 0.5 + Vector3(0.0, -0.06, 0.0)
	var l_bar2: float = p2_a.distance_to(p2_b) - 0.06

	var st_b: SurfaceTool = SurfaceTool.new()
	st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tirante 1 (punta)
	_agregar_box_orientado(st_b, Vector3.ZERO, l_bar1, 0.035, 0.065, _dir_tirante, fwd_bar)
	# Tirante 2 (secundario)
	var offset_bar2: Vector3 = c_bar2 - c_bar1
	_agregar_box_orientado(st_b, offset_bar2, l_bar2, 0.030, 0.055, _dir_tirante, fwd_bar)
	# Abrazaderas verticales de unión a las almas de los espadines
	_agregar_box_orientado(st_b, -_dir_tirante * (l_bar1 * 0.48) + Vector3(0.0, 0.04, 0.0), 0.05, 0.08, 0.08, _dir_tirante, fwd_bar)
	_agregar_box_orientado(st_b, _dir_tirante * (l_bar1 * 0.48) + Vector3(0.0, 0.04, 0.0), 0.05, 0.08, 0.08, _dir_tirante, fwd_bar)

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

	var off_int: float = trocha_media * _lado_s    # riel interior (lado desvío)
	var off_ext: float = trocha_media * -_lado_s   # riel interior (lado continuo)

	var d_ws: float = _dist_frog - 0.90
	var d_we: float = _dist_frog - 0.10
	var d_vs: float = _dist_frog + 0.10
	var d_vsp: float = _dist_frog + 1.25

	# Rieles de cierre interiores hasta la garganta
	_extruir_riel(st, curva_directa, l_ag, d_ws, off_int)
	_extruir_wing_rail(st, curva_directa, d_ws, d_we, off_int, 0.055 * _lado_s)

	_extruir_riel(st, curva_desviada, _d_desv(l_ag), _d_desv(d_ws), off_ext)
	_extruir_wing_rail(st, curva_desviada, _d_desv(d_ws), _d_desv(d_we), off_ext, 0.055 * -_lado_s)

	# Corazón en V
	var pasos_v: int = 12
	var anillos_v: Array[PackedVector3Array] = []
	for p: int in pasos_v + 1:
		var frac: float = float(p) / float(pasos_v)
		var d: float = lerpf(d_vs, d_vsp, frac)
		var pd: Vector3 = _punto_riel(curva_directa, d, off_int)
		var pv: Vector3 = _punto_riel(curva_desviada, _d_desv(d), off_ext)
		var c_pt: Vector3 = (pd + pv) * 0.5
		var w_v: float = maxf(0.015, pd.distance_to(pv) + 0.055)
		var fwd: Vector3 = _tangente(curva_directa, d)
		var side: Vector3 = Vector3.UP.cross(fwd).normalized()
		anillos_v.append(PackedVector3Array([
			c_pt - side * (w_v * 0.5),
			c_pt + side * (w_v * 0.5),
			c_pt + side * (w_v * 0.5) + Vector3(0.0, -0.150, 0.0),
			c_pt - side * (w_v * 0.5) + Vector3(0.0, -0.150, 0.0),
		]))
	_teselar_anillos(st, anillos_v, 4)

	# Rieles independientes desde corazón hasta el final
	_extruir_riel(st, curva_directa, d_vsp, largo_turnout, off_int)
	_extruir_riel(st, curva_desviada, _d_desv(d_vsp), _len_desv, off_ext)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_frog = MeshInstance3D.new()
		_nodo_frog.name = "CorazonYCierre"
		_nodo_frog.mesh = m
		_nodo_frog.material_override = material_riel
		agregar_a_geometria_fija(_nodo_frog)


func _construir_contrarrieles() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var d0: float = maxf(1.0, _dist_frog - 1.50)
	var d1: float = minf(largo_turnout - 0.5, _dist_frog + 1.50)

	_extruir_contrarriel_acampanado(st, curva_directa, d0, d1, trocha_media * -_lado_s, 0.045 * _lado_s)
	_extruir_contrarriel_acampanado(st, curva_desviada, _d_desv(d0), _d_desv(d1), trocha_media * _lado_s, 0.045 * -_lado_s)

	var m: ArrayMesh = st.commit()
	if m != null and m.get_surface_count() > 0:
		_nodo_checkrails = MeshInstance3D.new()
		_nodo_checkrails.name = "Contrarrieles"
		_nodo_checkrails.mesh = m
		_nodo_checkrails.material_override = material_metal
		agregar_a_geometria_fija(_nodo_checkrails)


func _construir_marmita_principal() -> void:
	var p0: Vector3 = curva_directa.sample_baked(0.55)
	var fwd0: Vector3 = _tangente(curva_directa, 0.55)
	var side0: Vector3 = Vector3.UP.cross(fwd0).normalized()
	var pos_m: Vector3 = p0 - side0 * (trocha_media + 1.20) * _lado_s
	_construir_marmita_en(pos_m, fwd0)


# ===========================================================================
# CINEMÁTICA DE AGUJAS
# ===========================================================================

## Calcula los ángulos objetivo y anima (o aplica directamente) la posición de los espadines.
## Lógica corregida:
##   DIRECTA  → Espadín interior CERRADO (rot=0), espadín exterior ABIERTO (rot ≠ 0).
##   DESVIADA → Espadín interior ABIERTO (rot ≠ 0), espadín exterior CERRADO (rot=0).
func _aplicar_posicion_agujas(inmediato: bool) -> void:
	_asegurar_materiales()

	# Espadín interior: rota alejándose de la contraaguja exterior cuando DESVIADA
	var rot_int_obj: float = (_ang_rot_aguja * _lado_s) if aguja_desviada else 0.0
	# Espadín exterior: rota alejándose de la contraaguja interior cuando DIRECTA
	var rot_ext_obj: float = 0.0 if aguja_desviada else (-_ang_rot_aguja * _lado_s)

	# Desplazamiento del tirante (en dirección lateral real, no solo en X)
	var shift_tirante: float = 0.115 if aguja_desviada else 0.0


	var rot_farol: float = deg_to_rad(90.0) if aguja_desviada else 0.0
	var rot_pesa: float = deg_to_rad(-45.0) if aguja_desviada else deg_to_rad(45.0)

	# Actualiza farol inmediatamente (visual, no afecta física)
	_aplicar_estado_marmita(aguja_desviada, not inmediato, rot_farol, rot_pesa)

	if _tween_agujas != null and _tween_agujas.is_valid():
		_tween_agujas.kill()

	if inmediato or not is_inside_tree():
		_set_rot_int(rot_int_obj)
		_set_rot_ext(rot_ext_obj)
		if _nodo_tirante != null:
			_nodo_tirante.position = _pos_tirante_base + _dir_tirante * shift_tirante
	else:
		_tween_agujas = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween_agujas.tween_method(_set_rot_int, _rot_int_actual, rot_int_obj, 0.35)
		_tween_agujas.tween_method(_set_rot_ext, _rot_ext_actual, rot_ext_obj, 0.35)
		if _nodo_tirante != null:
			_tween_agujas.tween_property(_nodo_tirante, "position", _pos_tirante_base + _dir_tirante * shift_tirante, 0.35)




func _set_rot_int(ang: float) -> void:
	_rot_int_actual = ang
	if _aguja_interior != null:
		_aguja_interior.basis = _basis_talon_int.rotated(Vector3.UP, ang)


func _set_rot_ext(ang: float) -> void:
	_rot_ext_actual = ang
	if _aguja_exterior != null:
		_aguja_exterior.basis = _basis_talon_ext.rotated(Vector3.UP, ang)


# ---------------------------------------------------------------------------
# INTERFAZ POLIMÓRFICA
# ---------------------------------------------------------------------------

func set_desviada(v: bool, animar: bool = true) -> void:
	aguja_desviada = v
	if not animar:
		_aplicar_posicion_agujas(true)


func obtener_curva_activa(_via_origen: int = 1) -> Curve3D:
	return curva_desviada if aguja_desviada else curva_directa


func obtener_trayectoria_completa(_via_origen: int = 1) -> Curve3D:
	var c_res: Curve3D = Curve3D.new()
	var g_ext: Node = get_node_or_null("ExtremosFlexibles")
	var lead_in: Node = g_ext.get_node_or_null("Extremo_Entrada_Comun") if g_ext != null else null
	var id_out: String = "Extremo_Salida_Desviada" if aguja_desviada else "Extremo_Salida_Directa"
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
	return "TIPO_A"


func get_estado_descripcion() -> String:
	return "DESVIADA" if aguja_desviada else "DIRECTA"


func is_desviado() -> bool:
	return aguja_desviada


func conmutar_a(modo: int = 0) -> void:
	set_desviada(modo != 0)


func get_largo_aparato() -> float:
	return largo_turnout

