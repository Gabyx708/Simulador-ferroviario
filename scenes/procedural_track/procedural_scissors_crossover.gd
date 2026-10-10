@tool
class_name ProceduralScissorsCrossover
extends BaseTurnout
## Tipo E: Escape Doble en X / Bretelle / Scissors Crossover (Double Crossover).
##
## Modela la infraestructura completa de un escape doble entre dos vías paralelas según
## los estándares UIC / T:ANE y lámina técnica de referencia (Fig. H: "Scissors Crossover / Bretelle"):
##   • Dos vías paralelas continuas (Vía 1 y Vía 2) separadas por 'distancia_ejes' (4.5m - 5.0m).
##   • Cuatro desvíos independientes (dos de entrada 1A/2A y dos de salida 1B/2B).
##   • Cruce central en diamante a nivel (Diamond Crossing) en la intersección de ambas diagonales.
##   • Tramos de continuidad recta en ambas vías entre los talones de los desvíos.
##   • Enclavamiento completo con 3 modos de circulación:
##       - Modo 0: Rutas paralelas directas independientes (ambas vías en verde).
##       - Modo 1: Cruce Vía 1 -> Vía 2 activo (Diagonal 1 con cruce central en Vía A).
##       - Modo 2: Cruce Vía 2 -> Vía 1 activo (Diagonal 2 con cruce central en Vía B).
##   • Cuatro marmitas 3D animadas con faroles rotativos y palancas de contrapeso.

enum ModoRuta {
	PARALELAS_DIRECTAS = 0, ## Rutas rectas directas independientes
	CRUCE_1_A_2 = 1,        ## Cruce activo desde Vía 1 hacia Vía 2
	CRUCE_2_A_1 = 2         ## Cruce activo desde Vía 2 hacia Vía 1
}

signal estado_cambiado(modo: int)

@export_group("Geometría de Trazado")
## Centro longitudinal y transversal del aparato de vía.
@export var posicion_centro: Vector3 = Vector3.ZERO:
	set(v):
		posicion_centro = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Distancia transversal entre los ejes de las dos vías paralelas.
@export_range(3.5, 9.0, 0.25) var distancia_ejes: float = 5.0:
	set(v):
		distancia_ejes = maxf(3.5, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Longitud longitudinal total del aparato de vía.
@export_range(32.0, 80.0, 1.0) var largo_crossover: float = 46.0:
	set(v):
		largo_crossover = maxf(32.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Longitud de cada uno de los cuatro desvíos componentes.
@export_range(12.0, 24.0, 0.5) var largo_turnout: float = 16.0:
	set(v):
		largo_turnout = maxf(10.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Estado de Enclavamiento")
## Modo de circulación activo en el bretelle.
@export var modo_ruta: ModoRuta = ModoRuta.PARALELAS_DIRECTAS:
	set(v):
		var cambio: bool = (modo_ruta != v)
		modo_ruta = v
		if cambio:
			_aplicar_posicion_agujas(false)
			estado_cambiado.emit(int(modo_ruta))

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

@export var luz_pestana: float = ProceduralTrackProfile.LUZ_PESTANA
@export var paso_durmientes: float = ProceduralTrackProfile.PASO_DURMIENTES

# Sub-aparatos internos
var _desvio_1a: ProceduralTurnout = null
var _desvio_1b: ProceduralTurnout = null
var _desvio_2a: ProceduralTurnout = null
var _desvio_2b: ProceduralTurnout = null
var _cruce_central: ProceduralCrossing = null
var _tramo_recto_1: ProceduralTrackSegment = null
var _tramo_recto_2: ProceduralTrackSegment = null

# Curvas maestras de referencia
var _curva_directa_1: Curve3D = null
var _curva_directa_2: Curve3D = null
var _curva_diagonal_1: Curve3D = null
var _curva_diagonal_2: Curve3D = null


func _ready() -> void:
	_asegurar_materiales()
	if _desvio_1a == null:
		construir_geometria()


func conmutar() -> void:
	var prox: int = (int(modo_ruta) + 1) % 3
	modo_ruta = prox as ModoRuta


func fijar_modo_ruta(nuevo_modo: ModoRuta) -> void:
	modo_ruta = nuevo_modo


func limpiar() -> void:
	super.limpiar()
	_desvio_1a = null
	_desvio_1b = null
	_desvio_2a = null
	_desvio_2b = null
	_cruce_central = null
	_tramo_recto_1 = null
	_tramo_recto_2 = null
	_curva_directa_1 = null
	_curva_directa_2 = null
	_curva_diagonal_1 = null
	_curva_diagonal_2 = null


## Devuelve la lista de puertos de conexión en los 4 extremos físicos del bretelle.
func obtener_puertos_conexion() -> Array[Dictionary]:
	var x1: float = posicion_centro.x - distancia_ejes * 0.5
	var x2: float = posicion_centro.x + distancia_ejes * 0.5
	var y_c: float = posicion_centro.y
	var z_start: float = posicion_centro.z - largo_crossover * 0.5
	var z_end: float = posicion_centro.z + largo_crossover * 0.5
	return [
		{
			"id": "via_1_entrada",
			"nombre": "Vía 1 (Entrada)",
			"posicion": Vector3(x1, y_c, z_start),
			"direccion": Vector3(0.0, 0.0, -1.0)
		},
		{
			"id": "via_1_salida",
			"nombre": "Vía 1 (Salida)",
			"posicion": Vector3(x1, y_c, z_end),
			"direccion": Vector3(0.0, 0.0, 1.0)
		},
		{
			"id": "via_2_entrada",
			"nombre": "Vía 2 (Entrada)",
			"posicion": Vector3(x2, y_c, z_start),
			"direccion": Vector3(0.0, 0.0, -1.0)
		},
		{
			"id": "via_2_salida",
			"nombre": "Vía 2 (Salida)",
			"posicion": Vector3(x2, y_c, z_end),
			"direccion": Vector3(0.0, 0.0, 1.0)
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

	var x1: float = posicion_centro.x - distancia_ejes * 0.5
	var x2: float = posicion_centro.x + distancia_ejes * 0.5
	var y_c: float = posicion_centro.y
	var z_start: float = posicion_centro.z - largo_crossover * 0.5
	var z_end: float = posicion_centro.z + largo_crossover * 0.5

	var l_to: float = minf(largo_turnout, (largo_crossover - 4.0) * 0.45)
	var hz: float = (z_end - z_start) * 0.38

	# 1. Curvas Directas de Vía 1 y Vía 2
	_curva_directa_1 = Curve3D.new()
	_curva_directa_1.add_point(Vector3(x1, y_c, z_start))
	_curva_directa_1.add_point(Vector3(x1, y_c, z_end))

	_curva_directa_2 = Curve3D.new()
	_curva_directa_2.add_point(Vector3(x2, y_c, z_start))
	_curva_directa_2.add_point(Vector3(x2, y_c, z_end))

	# 2. Curvas Maestras de Enlace Diagonal S
	_curva_diagonal_1 = Curve3D.new()
	_curva_diagonal_1.add_point(Vector3(x1, y_c, z_start), Vector3.ZERO, Vector3(0.0, 0.0, hz))
	_curva_diagonal_1.add_point(Vector3(x2, y_c, z_end), Vector3(0.0, 0.0, -hz), Vector3.ZERO)

	_curva_diagonal_2 = Curve3D.new()
	_curva_diagonal_2.add_point(Vector3(x2, y_c, z_start), Vector3.ZERO, Vector3(0.0, 0.0, hz))
	_curva_diagonal_2.add_point(Vector3(x1, y_c, z_end), Vector3(0.0, 0.0, -hz), Vector3.ZERO)

	var len_d1: float = _curva_diagonal_1.get_baked_length()
	var len_d2: float = _curva_diagonal_2.get_baked_length()
	var n_pts: int = 32
	var step_d: float = l_to / float(n_pts)

	# 3. Desvío 1A (Vía 1 Entrada, abre a la derecha hacia Vía 2)
	var c_dir_1a: Curve3D = Curve3D.new()
	c_dir_1a.add_point(Vector3(x1, y_c, z_start))
	c_dir_1a.add_point(Vector3(x1, y_c, z_start + l_to))

	var c_desv_1a: Curve3D = Curve3D.new()
	for i: int in range(n_pts + 1):
		var d: float = float(i) * step_d
		var pt: Vector3 = _curva_diagonal_1.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d1, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_1.sample_baked(d_next) - _curva_diagonal_1.sample_baked(d_prev)).normalized()
		var h: Vector3 = fwd * (step_d * 0.35)
		c_desv_1a.add_point(pt, -h, h)

	_desvio_1a = _crear_instancia_desvio("Desvio_1A", c_dir_1a, c_desv_1a, l_to)
	agregar_a_mecanismo(_desvio_1a)
	_desvio_1a.construir_geometria()

	# 4. Desvío 2A (Vía 2 Entrada, abre a la izquierda hacia Vía 1)
	var c_dir_2a: Curve3D = Curve3D.new()
	c_dir_2a.add_point(Vector3(x2, y_c, z_start))
	c_dir_2a.add_point(Vector3(x2, y_c, z_start + l_to))

	var c_desv_2a: Curve3D = Curve3D.new()
	for i: int in range(n_pts + 1):
		var d: float = float(i) * step_d
		var pt: Vector3 = _curva_diagonal_2.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d2, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_2.sample_baked(d_next) - _curva_diagonal_2.sample_baked(d_prev)).normalized()
		var h: Vector3 = fwd * (step_d * 0.35)
		c_desv_2a.add_point(pt, -h, h)

	_desvio_2a = _crear_instancia_desvio("Desvio_2A", c_dir_2a, c_desv_2a, l_to)
	agregar_a_mecanismo(_desvio_2a)
	_desvio_2a.construir_geometria()

	# 5. Desvío 1B (Vía 1 Salida, mirando hacia -Z, recibe Diagonal 2)
	var c_dir_1b: Curve3D = Curve3D.new()
	c_dir_1b.add_point(Vector3(x1, y_c, z_end))
	c_dir_1b.add_point(Vector3(x1, y_c, z_end - l_to))

	var c_desv_1b: Curve3D = Curve3D.new()
	for i: int in range(n_pts + 1):
		var d: float = len_d2 - float(i) * step_d
		var pt: Vector3 = _curva_diagonal_2.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d2, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_2.sample_baked(d_prev) - _curva_diagonal_2.sample_baked(d_next)).normalized()
		var h: Vector3 = fwd * (step_d * 0.35)
		c_desv_1b.add_point(pt, -h, h)

	_desvio_1b = _crear_instancia_desvio("Desvio_1B", c_dir_1b, c_desv_1b, l_to)
	agregar_a_mecanismo(_desvio_1b)
	_desvio_1b.construir_geometria()

	# 6. Desvío 2B (Vía 2 Salida, mirando hacia -Z, recibe Diagonal 1)
	var c_dir_2b: Curve3D = Curve3D.new()
	c_dir_2b.add_point(Vector3(x2, y_c, z_end))
	c_dir_2b.add_point(Vector3(x2, y_c, z_end - l_to))

	var c_desv_2b: Curve3D = Curve3D.new()
	for i: int in range(n_pts + 1):
		var d: float = len_d1 - float(i) * step_d
		var pt: Vector3 = _curva_diagonal_1.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d1, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_1.sample_baked(d_prev) - _curva_diagonal_1.sample_baked(d_next)).normalized()
		var h: Vector3 = fwd * (step_d * 0.35)
		c_desv_2b.add_point(pt, -h, h)

	_desvio_2b = _crear_instancia_desvio("Desvio_2B", c_dir_2b, c_desv_2b, l_to)
	agregar_a_mecanismo(_desvio_2b)
	_desvio_2b.construir_geometria()

	# 7. Cruce Diamante Central (Intersección de las dos diagonales)
	var l_cruce_span: float = (len_d1 - 2.0 * l_to)
	var tang1: Vector3 = (_curva_diagonal_1.sample_baked(len_d1 * 0.5 + 0.1) - _curva_diagonal_1.sample_baked(len_d1 * 0.5 - 0.1)).normalized()
	var tang2: Vector3 = (_curva_diagonal_2.sample_baked(len_d2 * 0.5 + 0.1) - _curva_diagonal_2.sample_baked(len_d2 * 0.5 - 0.1)).normalized()
	var ang_cruce: float = acos(clampf(tang1.dot(tang2), -1.0, 1.0))

	var c_cr_a: Curve3D = Curve3D.new()
	var step_diag: float = l_cruce_span / float(n_pts)
	for i: int in range(n_pts + 1):
		var d: float = l_to + float(i) * step_diag
		var pt: Vector3 = _curva_diagonal_1.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d1, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_1.sample_baked(d_next) - _curva_diagonal_1.sample_baked(d_prev)).normalized()
		c_cr_a.add_point(pt, -fwd * (step_diag * 0.35), fwd * (step_diag * 0.35))

	var c_cr_b: Curve3D = Curve3D.new()
	for i: int in range(n_pts + 1):
		var d: float = l_to + float(i) * step_diag
		var pt: Vector3 = _curva_diagonal_2.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_d2, d + 0.05)
		var fwd: Vector3 = (_curva_diagonal_2.sample_baked(d_next) - _curva_diagonal_2.sample_baked(d_prev)).normalized()
		c_cr_b.add_point(pt, -fwd * (step_diag * 0.35), fwd * (step_diag * 0.35))

	_cruce_central = ProceduralCrossing.new()
	_cruce_central.name = "CruceDiamante_Central"
	_cruce_central.material_riel = material_riel
	_cruce_central.material_balasto = material_balasto
	_cruce_central.material_durmiente = material_durmiente
	_cruce_central.material_metal = material_metal
	_cruce_central.posicion_centro = posicion_centro
	_cruce_central.angulo_cruce_rad = ang_cruce
	_cruce_central.largo_zona_cruce = l_cruce_span
	_cruce_central.curva_a = c_cr_a
	_cruce_central.curva_b = c_cr_b
	_cruce_central.mostrar_marmita = false
	_cruce_central.generar_extremos_flexibles = false
	agregar_a_geometria_fija(_cruce_central)
	_cruce_central.construir_geometria()

	# 8. Tramos Rectos Intermedios en Vía 1 y Vía 2
	var c_mid1: Curve3D = Curve3D.new()
	c_mid1.add_point(Vector3(x1, y_c, z_start + l_to))
	c_mid1.add_point(Vector3(x1, y_c, z_end - l_to))

	_tramo_recto_1 = ProceduralTrackSegment.new()
	_tramo_recto_1.name = "Recto_Intermedio_Via1"
	_tramo_recto_1.curve = c_mid1
	_tramo_recto_1.trocha_media = trocha_media
	_tramo_recto_1.paso_durmientes = paso_durmientes
	_tramo_recto_1.material_riel = material_riel
	_tramo_recto_1.material_balasto = material_balasto
	_tramo_recto_1.material_durmiente = material_durmiente
	agregar_a_geometria_fija(_tramo_recto_1)
	_tramo_recto_1.construir_geometria()

	var c_mid2: Curve3D = Curve3D.new()
	c_mid2.add_point(Vector3(x2, y_c, z_start + l_to))
	c_mid2.add_point(Vector3(x2, y_c, z_end - l_to))

	_tramo_recto_2 = ProceduralTrackSegment.new()
	_tramo_recto_2.name = "Recto_Intermedio_Via2"
	_tramo_recto_2.curve = c_mid2
	_tramo_recto_2.trocha_media = trocha_media
	_tramo_recto_2.paso_durmientes = paso_durmientes
	_tramo_recto_2.material_riel = material_riel
	_tramo_recto_2.material_balasto = material_balasto
	_tramo_recto_2.material_durmiente = material_durmiente
	agregar_a_geometria_fija(_tramo_recto_2)
	_tramo_recto_2.construir_geometria()

	# 9. Conectar eventos interactivos de las marmitas
	_conectar_marmitas_interactivas()

	# Aplicar posición inicial
	_aplicar_posicion_agujas(true)
	aplicar_culling()
	if self.generar_extremos_flexibles:
		sincronizar_extremos_flexibles()
	_bloqueo_reconstruccion = false


func _crear_instancia_desvio(nombre: String, c_dir: Curve3D, c_desv: Curve3D, l_to: float) -> ProceduralTurnout:
	var to: ProceduralTurnout = ProceduralTurnout.new()
	to.name = nombre
	to.curva_directa = c_dir
	to.curva_desviada = c_desv
	to.largo_turnout = l_to
	to.largo_aguja = largo_aguja
	to.trocha_media = trocha_media
	to.luz_pestana = luz_pestana
	to.paso_durmientes = paso_durmientes
	to.material_riel = material_riel
	to.material_balasto = material_balasto
	to.material_durmiente = material_durmiente
	to.material_metal = material_metal
	to.generar_extremos_flexibles = false
	return to


func _conectar_marmitas_interactivas() -> void:
	if _desvio_1a != null:
		_desvio_1a.estado_cambiado.connect(func(st: bool) -> void:
			if st: modo_ruta = ModoRuta.CRUCE_1_A_2
			elif modo_ruta == ModoRuta.CRUCE_1_A_2: modo_ruta = ModoRuta.PARALELAS_DIRECTAS
		)
	if _desvio_2b != null:
		_desvio_2b.estado_cambiado.connect(func(st: bool) -> void:
			if st: modo_ruta = ModoRuta.CRUCE_1_A_2
			elif modo_ruta == ModoRuta.CRUCE_1_A_2: modo_ruta = ModoRuta.PARALELAS_DIRECTAS
		)
	if _desvio_2a != null:
		_desvio_2a.estado_cambiado.connect(func(st: bool) -> void:
			if st: modo_ruta = ModoRuta.CRUCE_2_A_1
			elif modo_ruta == ModoRuta.CRUCE_2_A_1: modo_ruta = ModoRuta.PARALELAS_DIRECTAS
		)
	if _desvio_1b != null:
		_desvio_1b.estado_cambiado.connect(func(st: bool) -> void:
			if st: modo_ruta = ModoRuta.CRUCE_2_A_1
			elif modo_ruta == ModoRuta.CRUCE_2_A_1: modo_ruta = ModoRuta.PARALELAS_DIRECTAS
		)


# ===========================================================================
# CINEMÁTICA Y ENCLAVAMIENTO SINCRONIZADO
# ===========================================================================

func _aplicar_posicion_agujas(inmediato: bool) -> void:
	var st_1a: bool = (modo_ruta == ModoRuta.CRUCE_1_A_2)
	var st_2b: bool = (modo_ruta == ModoRuta.CRUCE_1_A_2)
	var st_2a: bool = (modo_ruta == ModoRuta.CRUCE_2_A_1)
	var st_1b: bool = (modo_ruta == ModoRuta.CRUCE_2_A_1)

	_actualizar_desvio_estado(_desvio_1a, st_1a, inmediato)
	_actualizar_desvio_estado(_desvio_2b, st_2b, inmediato)
	_actualizar_desvio_estado(_desvio_2a, st_2a, inmediato)
	_actualizar_desvio_estado(_desvio_1b, st_1b, inmediato)

	if _cruce_central != null:
		_cruce_central.via_b_activa = (modo_ruta == ModoRuta.CRUCE_2_A_1)


func _actualizar_desvio_estado(desvio: ProceduralTurnout, desviada: bool, inmediato: bool) -> void:
	if desvio == null or desvio.aguja_desviada == desviada:
		return
	if inmediato:
		desvio.set("aguja_desviada", desviada)
		desvio.call("_aplicar_posicion_agujas", true)
	else:
		desvio.aguja_desviada = desviada


# ===========================================================================
# CONSULTAS DE TRAYECTORIAS PARA VEHÍCULOS
# ===========================================================================

func obtener_curva_via_1() -> Curve3D:
	return _curva_directa_1


func obtener_curva_via_2() -> Curve3D:
	return _curva_directa_2


func obtener_curva_diagonal_1() -> Curve3D:
	return _curva_diagonal_1


func obtener_curva_diagonal_2() -> Curve3D:
	return _curva_diagonal_2


func obtener_ruta_activa(desde_via_1: bool = true) -> Curve3D:
	if desde_via_1:
		match modo_ruta:
			ModoRuta.CRUCE_1_A_2:
				return _curva_diagonal_1
			_:
				return _curva_directa_1
	else:
		match modo_ruta:
			ModoRuta.CRUCE_2_A_1:
				return _curva_diagonal_2
			_:
				return _curva_directa_2


# ---------------------------------------------------------------------------
# INTERFAZ POLIMÓRFICA
# ---------------------------------------------------------------------------

func set_modo_ruta(m: ModoRuta, animar: bool = true) -> void:
	modo_ruta = m
	if not animar:
		_aplicar_posicion_agujas(true)


func obtener_curva_activa(via_origen: int = 1) -> Curve3D:
	return obtener_ruta_activa(via_origen == 1)


func obtener_trayectoria_completa(via_origen: int = 1) -> Curve3D:
	var c_res: Curve3D = Curve3D.new()
	var g_ext: Node = get_node_or_null("ExtremosFlexibles")
	var lead_in: Node = null
	var lead_out: Node = null
	var c_core: Curve3D = null

	if via_origen == 1:
		match modo_ruta:
			ModoRuta.CRUCE_1_A_2:
				lead_in = g_ext.get_node_or_null("Extremo_Via_1_Entrada") if g_ext != null else null
				lead_out = g_ext.get_node_or_null("Extremo_Via_2_Salida") if g_ext != null else null
				c_core = _curva_diagonal_1
			_:
				lead_in = g_ext.get_node_or_null("Extremo_Via_1_Entrada") if g_ext != null else null
				lead_out = g_ext.get_node_or_null("Extremo_Via_1_Salida") if g_ext != null else null
				c_core = _curva_directa_1
	else:
		match modo_ruta:
			ModoRuta.CRUCE_2_A_1:
				lead_in = g_ext.get_node_or_null("Extremo_Via_2_Entrada") if g_ext != null else null
				lead_out = g_ext.get_node_or_null("Extremo_Via_1_Salida") if g_ext != null else null
				c_core = _curva_diagonal_2
			_:
				lead_in = g_ext.get_node_or_null("Extremo_Via_2_Entrada") if g_ext != null else null
				lead_out = g_ext.get_node_or_null("Extremo_Via_2_Salida") if g_ext != null else null
				c_core = _curva_directa_2

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
	return "TIPO_E"


func get_estado_descripcion() -> String:
	match modo_ruta:
		ModoRuta.PARALELAS_DIRECTAS:
			return "PARALELAS_DIRECTAS"
		ModoRuta.CRUCE_1_A_2:
			return "CRUCE_1_A_2"
		ModoRuta.CRUCE_2_A_1:
			return "CRUCE_2_A_1"
		_:
			return "DESCONOCIDO"


func is_desviado() -> bool:
	return modo_ruta != ModoRuta.PARALELAS_DIRECTAS


func conmutar_a(modo: int = 0) -> void:
	var m: int = clampi(modo, 0, 2)
	set_modo_ruta(m as ModoRuta)


func get_largo_aparato() -> float:
	return largo_crossover
