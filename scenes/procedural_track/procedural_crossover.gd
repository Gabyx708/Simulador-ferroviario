@tool
class_name ProceduralCrossover
extends BaseTurnout
## Tipo D: Crossover / Escape entre Vías Paralelas en H (Parallel Crossover).
##
## Modela la infraestructura completa de un escape entre dos vías paralelas según
## los estándares UIC / T:ANE y la lámina técnica de referencia (Fig. F: "Two turnouts
## combining to join two parallel tracks"):
##   • Dos vías paralelas separadas por 'distancia_ejes' (típicamente 4.5m - 5.0m).
##   • Desvío 1 (Vía 1): Desvío estándar con espadines en el talón de entrada y corazón en V.
##   • Desvío 2 (Vía 2): Desvío estándar enfrentado con corazón en V y espadines en la salida.
##   • Tramo diagonal de enlace con geometría tangencial continua C^1.
##   • Tramos de continuidad recta en ambas vías a través de toda la zona del aparato.
##   • Enclavamiento sincronizado: conmutar un desvío conmuta simultáneamente ambos.
##   • Dos marmitas 3D animadas con faroles rotativos y palancas de contrapeso.

signal estado_cambiado(ruta_cruzada: bool)

@export_group("Geometría de Trazado")
## Centro longitudinal y transversal del aparato de vía en el espacio local.
@export var posicion_centro: Vector3 = Vector3.ZERO:
	set(v):
		posicion_centro = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Distancia transversal entre los ejes de las dos vías paralelas (trocha media a trocha media).
@export_range(3.5, 9.0, 0.25) var distancia_ejes: float = 5.0:
	set(v):
		distancia_ejes = maxf(3.5, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Longitud longitudinal total del aparato a lo largo de cada vía.
@export_range(28.0, 70.0, 1.0) var largo_crossover: float = 44.0:
	set(v):
		largo_crossover = maxf(28.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Longitud de cada uno de los dos desvíos que componen el crossover.
@export_range(12.0, 24.0, 0.5) var largo_turnout: float = 16.0:
	set(v):
		largo_turnout = maxf(10.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Curvas opcionales provistas externamente para Vía 1 y Vía 2.
@export var curva_via_1: Curve3D = null:
	set(v):
		curva_via_1 = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export var curva_via_2: Curve3D = null:
	set(v):
		curva_via_2 = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Si está activo, el cruce diagonal va desde Vía 2 hacia Vía 1 en vez de Vía 1 hacia Vía 2.
@export var diagonal_invertida: bool = false:
	set(v):
		diagonal_invertida = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Estado de Enclavamiento")
## false = Rutas rectas directas en ambas vías (circulación paralela independiente)
## true  = Ruta cruzada en H activa (trenes cruzan de Vía 1 a Vía 2 o viceversa)
@export var ruta_cruzada: bool = false:
	set(v):
		var cambio: bool = (ruta_cruzada != v)
		ruta_cruzada = v
		if cambio:
			_aplicar_posicion_agujas(false)
			estado_cambiado.emit(ruta_cruzada)

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

# Sub-aparatos y tramos generados
var _desvio_1: ProceduralTurnout = null
var _desvio_2: ProceduralTurnout = null
var _tramo_diagonal: ProceduralTrackSegment = null
var _tramo_recto_via1: ProceduralTrackSegment = null
var _tramo_recto_via2: ProceduralTrackSegment = null

# Curva maestra S del crossover
var _curva_maestra_cruce: Curve3D = null
var _curva_directa_1: Curve3D = null
var _curva_directa_2: Curve3D = null


func _ready() -> void:
	_asegurar_materiales()
	if _desvio_1 == null:
		construir_geometria()


func conmutar() -> void:
	ruta_cruzada = not ruta_cruzada


func limpiar() -> void:
	super.limpiar()
	_desvio_1 = null
	_desvio_2 = null
	_tramo_diagonal = null
	_tramo_recto_via1 = null
	_tramo_recto_via2 = null
	_curva_maestra_cruce = null
	_curva_directa_1 = null
	_curva_directa_2 = null


## Devuelve la lista de puertos de conexión en los 4 extremos físicos del escape.
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

	# Coordenadas locales de las dos vías paralelas
	var x1: float = posicion_centro.x - distancia_ejes * 0.5
	var x2: float = posicion_centro.x + distancia_ejes * 0.5
	var y_c: float = posicion_centro.y
	var z_start: float = posicion_centro.z - largo_crossover * 0.5
	var z_end: float = posicion_centro.z + largo_crossover * 0.5

	var xa: float = x2 if diagonal_invertida else x1
	var xb: float = x1 if diagonal_invertida else x2

	# Ajustar largo de desvío si excede el largo total del aparato
	var l_to: float = minf(largo_turnout, (largo_crossover - 2.0) * 0.45)

	# 1. Curvas Directas de Vía 1 y Vía 2
	_curva_directa_1 = Curve3D.new()
	_curva_directa_1.add_point(Vector3(x1, y_c, z_start))
	_curva_directa_1.add_point(Vector3(x1, y_c, z_end))

	_curva_directa_2 = Curve3D.new()
	_curva_directa_2.add_point(Vector3(x2, y_c, z_start))
	_curva_directa_2.add_point(Vector3(x2, y_c, z_end))

	# 2. Curva Maestra S de enlace entre Vía 1 y Vía 2
	_curva_maestra_cruce = Curve3D.new()
	var hz: float = (z_end - z_start) * 0.38
	_curva_maestra_cruce.add_point(Vector3(xa, y_c, z_start), Vector3.ZERO, Vector3(0.0, 0.0, hz))
	_curva_maestra_cruce.add_point(Vector3(xb, y_c, z_end), Vector3(0.0, 0.0, -hz), Vector3.ZERO)

	var len_cruce: float = _curva_maestra_cruce.get_baked_length()
	var n_pts_desv: int = 32

	# 3. Desvío 1 (en Vía xa, orientado hacia +Z)
	var c_dir1: Curve3D = Curve3D.new()
	c_dir1.add_point(Vector3(xa, y_c, z_start))
	c_dir1.add_point(Vector3(xa, y_c, z_start + l_to))

	var c_desv1: Curve3D = Curve3D.new()
	var step_d1: float = l_to / float(n_pts_desv)
	for i: int in range(n_pts_desv + 1):
		var d: float = float(i) * step_d1
		var pt: Vector3 = _curva_maestra_cruce.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_cruce, d + 0.05)
		var fwd: Vector3 = (_curva_maestra_cruce.sample_baked(d_next) - _curva_maestra_cruce.sample_baked(d_prev)).normalized()
		var h: Vector3 = fwd * (step_d1 * 0.35)
		c_desv1.add_point(pt, -h, h)

	_desvio_1 = ProceduralTurnout.new()
	_desvio_1.name = "Desvio_1"
	_desvio_1.curva_directa = c_dir1
	_desvio_1.curva_desviada = c_desv1
	_desvio_1.largo_turnout = l_to
	_desvio_1.largo_aguja = largo_aguja
	_desvio_1.trocha_media = trocha_media
	_desvio_1.luz_pestana = luz_pestana
	_desvio_1.paso_durmientes = paso_durmientes
	_desvio_1.material_riel = material_riel
	_desvio_1.material_balasto = material_balasto
	_desvio_1.material_durmiente = material_durmiente
	_desvio_1.material_metal = material_metal
	_desvio_1.generar_extremos_flexibles = false
	agregar_a_mecanismo(_desvio_1)
	_desvio_1.construir_geometria()

	# 4. Desvío 2 (en Vía xb, orientado hacia -Z)
	var c_dir2: Curve3D = Curve3D.new()
	c_dir2.add_point(Vector3(xb, y_c, z_end))
	c_dir2.add_point(Vector3(xb, y_c, z_end - l_to))

	var c_desv2: Curve3D = Curve3D.new()
	for i: int in range(n_pts_desv + 1):
		var d: float = len_cruce - float(i) * step_d1
		var pt: Vector3 = _curva_maestra_cruce.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_cruce, d + 0.05)
		# En c_desv2 el avance es hacia -Z (d decreciente en la curva maestra), por lo que fwd apunta hacia -Z
		var fwd: Vector3 = (_curva_maestra_cruce.sample_baked(d_prev) - _curva_maestra_cruce.sample_baked(d_next)).normalized()
		var h: Vector3 = fwd * (step_d1 * 0.35)
		c_desv2.add_point(pt, -h, h)

	_desvio_2 = ProceduralTurnout.new()
	_desvio_2.name = "Desvio_2"
	_desvio_2.curva_directa = c_dir2
	_desvio_2.curva_desviada = c_desv2
	_desvio_2.largo_turnout = l_to
	_desvio_2.largo_aguja = largo_aguja
	_desvio_2.trocha_media = trocha_media
	_desvio_2.luz_pestana = luz_pestana
	_desvio_2.paso_durmientes = paso_durmientes
	_desvio_2.material_riel = material_riel
	_desvio_2.material_balasto = material_balasto
	_desvio_2.material_durmiente = material_durmiente
	_desvio_2.material_metal = material_metal
	_desvio_2.generar_extremos_flexibles = false
	agregar_a_mecanismo(_desvio_2)
	_desvio_2.construir_geometria()

	# 5. Tramo Diagonal de Enlace Central
	var c_diag: Curve3D = Curve3D.new()
	var d_span: float = (len_cruce - l_to) - l_to
	var step_diag: float = d_span / float(n_pts_desv)
	for i: int in range(n_pts_desv + 1):
		var d: float = l_to + float(i) * step_diag
		var pt: Vector3 = _curva_maestra_cruce.sample_baked(d)
		var d_prev: float = maxf(0.0, d - 0.05)
		var d_next: float = minf(len_cruce, d + 0.05)
		var fwd: Vector3 = (_curva_maestra_cruce.sample_baked(d_next) - _curva_maestra_cruce.sample_baked(d_prev)).normalized()
		var h: Vector3 = fwd * (step_diag * 0.35)
		c_diag.add_point(pt, -h, h)

	_tramo_diagonal = ProceduralTrackSegment.new()
	_tramo_diagonal.name = "Diagonal_Enlace"
	_tramo_diagonal.curve = c_diag
	_tramo_diagonal.trocha_media = trocha_media
	_tramo_diagonal.paso_durmientes = paso_durmientes
	_tramo_diagonal.material_riel = material_riel
	_tramo_diagonal.material_balasto = material_balasto
	_tramo_diagonal.material_durmiente = material_durmiente
	agregar_a_geometria_fija(_tramo_diagonal)
	_tramo_diagonal.construir_geometria()

	# 6. Tramos Rectos de Continuidad
	var c_recto1: Curve3D = Curve3D.new()
	c_recto1.add_point(Vector3(xa, y_c, z_start + l_to))
	c_recto1.add_point(Vector3(xa, y_c, z_end))

	_tramo_recto_via1 = ProceduralTrackSegment.new()
	_tramo_recto_via1.name = "Continuidad_Via1"
	_tramo_recto_via1.curve = c_recto1
	_tramo_recto_via1.trocha_media = trocha_media
	_tramo_recto_via1.paso_durmientes = paso_durmientes
	_tramo_recto_via1.material_riel = material_riel
	_tramo_recto_via1.material_balasto = material_balasto
	_tramo_recto_via1.material_durmiente = material_durmiente
	agregar_a_geometria_fija(_tramo_recto_via1)
	_tramo_recto_via1.construir_geometria()

	var c_recto2: Curve3D = Curve3D.new()
	c_recto2.add_point(Vector3(xb, y_c, z_start))
	c_recto2.add_point(Vector3(xb, y_c, z_end - l_to))

	_tramo_recto_via2 = ProceduralTrackSegment.new()
	_tramo_recto_via2.name = "Continuidad_Via2"
	_tramo_recto_via2.curve = c_recto2
	_tramo_recto_via2.trocha_media = trocha_media
	_tramo_recto_via2.paso_durmientes = paso_durmientes
	_tramo_recto_via2.material_riel = material_riel
	_tramo_recto_via2.material_balasto = material_balasto
	_tramo_recto_via2.material_durmiente = material_durmiente
	agregar_a_geometria_fija(_tramo_recto_via2)
	_tramo_recto_via2.construir_geometria()

	# 7. Sincronización de Enclavamiento Bidireccional
	_desvio_1.estado_cambiado.connect(func(desv: bool) -> void:
		if ruta_cruzada != desv:
			ruta_cruzada = desv
	)
	_desvio_2.estado_cambiado.connect(func(desv: bool) -> void:
		if ruta_cruzada != desv:
			ruta_cruzada = desv
	)

	# Aplicar posición inicial
	_aplicar_posicion_agujas(true)
	aplicar_culling()
	if self.generar_extremos_flexibles:
		sincronizar_extremos_flexibles()
	_bloqueo_reconstruccion = false


# ===========================================================================
# CINEMÁTICA Y ENCLAVAMIENTO SINCRONIZADO
# ===========================================================================

func _aplicar_posicion_agujas(inmediato: bool) -> void:
	if _desvio_1 != null and _desvio_1.aguja_desviada != ruta_cruzada:
		if inmediato:
			_desvio_1.set("aguja_desviada", ruta_cruzada)
			_desvio_1.call("_aplicar_posicion_agujas", true)
		else:
			_desvio_1.aguja_desviada = ruta_cruzada

	if _desvio_2 != null and _desvio_2.aguja_desviada != ruta_cruzada:
		if inmediato:
			_desvio_2.set("aguja_desviada", ruta_cruzada)
			_desvio_2.call("_aplicar_posicion_agujas", true)
		else:
			_desvio_2.aguja_desviada = ruta_cruzada


# ===========================================================================
# CONSULTAS DE TRAYECTORIAS PARA VEHÍCULOS Y CARROS DE PRUEBA
# ===========================================================================

func obtener_curva_via_1() -> Curve3D:
	return _curva_directa_1


func obtener_curva_via_2() -> Curve3D:
	return _curva_directa_2


func obtener_curva_cruce_1_a_2() -> Curve3D:
	return _curva_maestra_cruce


func obtener_curva_cruce_2_a_1() -> Curve3D:
	if _curva_maestra_cruce == null:
		return null
	var c_inv: Curve3D = Curve3D.new()
	var len_c: float = _curva_maestra_cruce.get_baked_length()
	var steps: int = 32
	for i: int in range(steps + 1):
		var d: float = len_c - (float(i) / float(steps)) * len_c
		c_inv.add_point(_curva_maestra_cruce.sample_baked(d))
	return c_inv


func obtener_ruta_activa(desde_via_1: bool = true) -> Curve3D:
	if not diagonal_invertida:
		if desde_via_1:
			return _curva_maestra_cruce if ruta_cruzada else _curva_directa_1
		else:
			return obtener_curva_cruce_2_a_1() if ruta_cruzada else _curva_directa_2
	else:
		if not desde_via_1:
			return _curva_maestra_cruce if ruta_cruzada else _curva_directa_2
		else:
			return obtener_curva_cruce_2_a_1() if ruta_cruzada else _curva_directa_1


# ---------------------------------------------------------------------------
# INTERFAZ POLIMÓRFICA
# ---------------------------------------------------------------------------

func set_ruta_cruzada(v: bool, animar: bool = true) -> void:
	ruta_cruzada = v
	if not animar:
		_aplicar_posicion_agujas(true)


func obtener_curva_activa(via_origen: int = 1) -> Curve3D:
	return obtener_ruta_activa(via_origen == 1)


func obtener_trayectoria_completa(via_origen: int = 1) -> Curve3D:
	var c_res: Curve3D = Curve3D.new()
	var g_ext: Node = get_node_or_null("ExtremosFlexibles")
	var id_in: String = "Extremo_Via_1_Entrada" if via_origen == 1 else "Extremo_Via_2_Entrada"
	var id_out: String
	if not diagonal_invertida:
		if via_origen == 1:
			id_out = "Extremo_Via_2_Salida" if ruta_cruzada else "Extremo_Via_1_Salida"
		else:
			id_out = "Extremo_Via_1_Salida" if ruta_cruzada else "Extremo_Via_2_Salida"
	else:
		if via_origen == 2:
			id_out = "Extremo_Via_1_Salida" if ruta_cruzada else "Extremo_Via_2_Salida"
		else:
			id_out = "Extremo_Via_2_Salida" if ruta_cruzada else "Extremo_Via_1_Salida"

	var lead_in: Node = g_ext.get_node_or_null(id_in) if g_ext != null else null
	var lead_out: Node = g_ext.get_node_or_null(id_out) if g_ext != null else null
	var c_core: Curve3D = obtener_curva_activa(via_origen)

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
	return "TIPO_D"


func get_estado_descripcion() -> String:
	return "CRUZADA" if ruta_cruzada else "DIRECTA"


func is_desviado() -> bool:
	return ruta_cruzada


func conmutar_a(modo: int = 0) -> void:
	set_ruta_cruzada(modo != 0)


func get_largo_aparato() -> float:
	return largo_crossover
