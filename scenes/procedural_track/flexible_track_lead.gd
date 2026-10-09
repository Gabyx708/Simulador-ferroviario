@tool
class_name FlexibleTrackLead
extends ProceduralTrackSegment
## Tramo de vía procedural adaptable y flexible para extremos de aparatos de vía.
##
## Conecta de forma milimétrica (cero huecos) un borne físico de un switch
## con una vía externa o tramo de la red real (Path3D).
## Utiliza interpolación Hermite/Bézier continua (G1) para asegurar
## que los rieles y el balasto no tengan quiebres ni saltos bruscos.

@export_group("Conexión de Extremo")
## Punto de inicio (anclado con tolerancia cero al borne del switch en coordenadas locales).
@export var punto_inicio: Vector3 = Vector3.ZERO:
	set(v):
		punto_inicio = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Vector unitario que indica la dirección en que sale la vía desde el switch.
@export var direccion_inicio: Vector3 = Vector3.FORWARD:
	set(v):
		direccion_inicio = v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

@export_group("Geometría Adaptativa")
## Longitud longitudinal en metros del tramo de transición flexible.
@export_range(5.0, 500.0, 1.0) var longitud_extension: float = 20.0:
	set(v):
		longitud_extension = maxf(3.0, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Desplazamiento lateral en metros en el extremo exterior (+X relativo / derecha).
@export_range(-15.0, 15.0, 0.25) var offset_lateral: float = 0.0:
	set(v):
		offset_lateral = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Desplazamiento vertical en metros en el extremo exterior (+Y / pendiente).
@export_range(-5.0, 5.0, 0.1) var offset_vertical: float = 0.0:
	set(v):
		offset_vertical = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Ángulo de desviación en grados en el extremo exterior (curvatura tangencial).
@export_range(-45.0, 45.0, 1.0) var angulo_curva_deg: float = 0.0:
	set(v):
		angulo_curva_deg = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Factor proporcional de manijas tangenciales Hermite (0.25 a 0.50).
@export_range(0.2, 0.6, 0.02) var factor_tangente: float = 0.38:
	set(v):
		factor_tangente = clampf(v, 0.15, 0.65)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

@export_group("Control Manual / Red Real")
## Si es verdadero, el extremo exterior se fija manualmente con punto_fin_manual y direccion_fin_manual.
@export var usar_extremo_manual: bool = false:
	set(v):
		usar_extremo_manual = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Posición exacta del extremo exterior (usado al conectar a un Path3D real).
@export var punto_fin_manual: Vector3 = Vector3.ZERO:
	set(v):
		punto_fin_manual = v
		if is_inside_tree() and usar_extremo_manual and not _bloqueo_reconstruccion:
			reconstruir_tramo()

## Dirección tangencial de salida en el extremo exterior (usado al conectar a un Path3D real).
@export var direccion_fin_manual: Vector3 = Vector3.FORWARD:
	set(v):
		direccion_fin_manual = v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD
		if is_inside_tree() and usar_extremo_manual and not _bloqueo_reconstruccion:
			reconstruir_tramo()

@export_group("Herramientas de Edición")
## Reajusta el punto 0 y su tangente exactamente al borne del switch si se descalibró al editar en el viewport.
@export var reajustar_a_borne: bool = false:
	set(v):
		if v:
			reajustar_a_borne = false
			conectar_a_borne(punto_inicio, direccion_inicio)

## Si está activo, el anclaje automático NO toca este extremo: se conserva la
## posición/dirección fijada a mano y se persiste en el journal de ediciones.
@export var respetar_edicion_manual: bool = false

## Pulsador: fija el extremo en su pose actual y bloquea el anclaje automático.
@export var boton_fijar_extremo: bool = false:
	set(v):
		if v:
			boton_fijar_extremo = false
			if not usar_extremo_manual:
				punto_fin_manual = _calcular_punto_fin_automatico()
				direccion_fin_manual = _calcular_direccion_fin_automatica()
				usar_extremo_manual = true
			respetar_edicion_manual = true
			reconstruir_tramo()

## Pulsador: libera el extremo para que el anclaje automático vuelva a gobernarlo.
@export var boton_liberar_extremo: bool = false:
	set(v):
		if v:
			boton_liberar_extremo = false
			respetar_edicion_manual = false


func _ready() -> void:
	super._ready()
	if curve == null or curve.point_count < 2:
		reconstruir_tramo()


## Ancla este tramo con tolerancia cero al borne del aparato de vía.
func conectar_a_borne(pos_borne: Vector3, dir_saliente: Vector3) -> void:
	punto_inicio = pos_borne
	direccion_inicio = dir_saliente.normalized() if dir_saliente.length_squared() > 1e-4 else Vector3.FORWARD
	if curve != null and curve.point_count >= 2:
		_bloqueo_reconstruccion = true
		curve.set_point_position(0, punto_inicio)
		curve.set_point_in(0, Vector3.ZERO)
		var h_len: float = curve.get_point_out(0).length()
		if h_len < 0.5:
			h_len = maxf(1.0, longitud_extension * factor_tangente)
		curve.set_point_out(0, direccion_inicio * h_len)
		_bloqueo_reconstruccion = false
		construir_geometria()
	else:
		reconstruir_tramo()


## Conecta el extremo exterior a una vía o posición de tramo real.
func conectar_a_via_externa(pos_ext: Vector3, dir_exterior: Vector3) -> void:
	usar_extremo_manual = true
	punto_fin_manual = pos_ext
	var d_ext: Vector3 = dir_exterior.normalized() if dir_exterior.length_squared() > 1e-4 else direccion_inicio
	if d_ext.dot(direccion_inicio) < 0.0:
		d_ext = -d_ext
	direccion_fin_manual = d_ext
	reconstruir_tramo()


## Obtiene la posición 3D actual del extremo exterior móvil.
func obtener_posicion_extremo_exterior() -> Vector3:
	if usar_extremo_manual:
		return punto_fin_manual
	return _calcular_punto_fin_automatico()


## Obtiene la dirección tangencial en el extremo exterior móvil.
func obtener_direccion_extremo_exterior() -> Vector3:
	if usar_extremo_manual:
		return direccion_fin_manual
	return _calcular_direccion_fin_automatica()


func _calcular_punto_fin_automatico() -> Vector3:
	var fwd: Vector3 = direccion_inicio.normalized()
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	return punto_inicio + fwd * longitud_extension + side * offset_lateral + Vector3.UP * offset_vertical


func _calcular_direccion_fin_automatica() -> Vector3:
	var fwd: Vector3 = direccion_inicio.normalized()
	var rot: Basis = Basis(Vector3.UP, deg_to_rad(angulo_curva_deg))
	return (rot * fwd).normalized()


## Genera la Curve3D cúbica con continuidad tangencial G1 y construye la malla.
func reconstruir_tramo() -> void:
	var p0: Vector3 = punto_inicio
	var d0: Vector3 = direccion_inicio.normalized()

	var p1: Vector3 = punto_fin_manual if usar_extremo_manual else _calcular_punto_fin_automatico()
	var d1: Vector3 = direccion_fin_manual.normalized() if usar_extremo_manual else _calcular_direccion_fin_automatica()

	var dist: float = p0.distance_to(p1)
	var proj_fwd: float = (p1 - p0).dot(d0)
	# Si el punto exterior se encuentra por detrás del borne del switch o es puramente lateral
	# (el aparato ya cubrió o sobrepasó esa unión), no retroceder ni quebrar hacia adentro.
	var degenerada: bool = dist < 0.2 or (usar_extremo_manual and proj_fwd < 0.15)
	var c: Curve3D = Curve3D.new()
	if not degenerada:
		var h_len: float = clampf(proj_fwd * factor_tangente, 0.2, dist * 0.5)
		c.add_point(p0, Vector3.ZERO, d0 * h_len)
		c.add_point(p1, -d1 * h_len, Vector3.ZERO)

	# Sin cambios reales no se re-genera la malla: el re-anclaje se ejecuta sobre
	# todos los puertos en cada edición de la red, y re-mallar cada extremo era el
	# costo dominante del congelamiento del editor.
	if _curva_equivalente(curve, c):
		return
	if degenerada:
		limpiar()
		curve = c
		return

	curve = c
	construir_geometria()


## Compara dos curvas punto a punto para decidir si hace falta re-generar la malla.
func _curva_equivalente(a: Curve3D, b: Curve3D) -> bool:
	var na: int = a.point_count if a != null else 0
	var nb: int = b.point_count if b != null else 0
	if na != nb:
		return false
	if na == 0:
		return true
	for i: int in na:
		if a.get_point_position(i).distance_squared_to(b.get_point_position(i)) > 1e-8:
			return false
		if a.get_point_in(i).distance_squared_to(b.get_point_in(i)) > 1e-8:
			return false
		if a.get_point_out(i).distance_squared_to(b.get_point_out(i)) > 1e-8:
			return false
	return true

