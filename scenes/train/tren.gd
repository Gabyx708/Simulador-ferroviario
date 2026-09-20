@tool
extends Node3D
class_name Tren
## Clase base genérica para formaciones ferroviarias sobre un Path3D.
##
## Cada coche calcula su orientación siguiendo los bogies delantero y trasero
## muestreados directamente sobre la curva del Path3D para un trazado curvo realista.
##
## Admite circulación bidireccional (Ascendente / Descendente) invirtiendo el sentido
## de avance, con ajuste dinámico de cabeceras, andenes y orientación de coches.
##
## Ejecutable en el editor (@tool) para previsualización y animación en tiempo real.
## Permite arrastrar el tren en el editor 3D y ajustarlo automáticamente
## a la vía al soltar el mouse, tal como las estaciones.
## Compatible con Godot 4.x / 4.7

signal velocidad_cambiada(kmh: float)
signal parada_alcanzada(indice_parada: int)
signal marcha_reanudada()
signal seleccionado() ## Emitida al hacer clic izquierdo sobre algún coche de la formación.

@export_group("Previsualización en Editor")
## Si está activo, el tren se desplaza y simula su marcha dentro del visor del editor 3D.
@export var animar_en_editor: bool = false:
	set(v):
		animar_en_editor = v
		if Engine.is_editor_hint():
			set_process(true)
			if animar_en_editor:
				_detenido = false
				_espera = 0.0
				_debe_invertir_en_salida = false
				_buscar_proxima_parada(true)
				_aceleracion_actual = 0.0
			else:
				_vel = 0.0
				_detenido = false
				_debe_invertir_en_salida = false
				_avance = avance_inicial
				if is_inside_tree() and _cuerpos.size() > 0:
					_ubicar(0.0)

## Pulsador para forzar la reconstrucción de la formación en el editor.
@export var regenerar: bool = false:
	set(v):
		regenerar = false
		if is_inside_tree():
			_reconstruir()

@export_group("Vinculación a la Vía")
## La traza (Path3D) sobre la cual circula la formación.
@export var traza: Path3D:
	set(v):
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.disconnect(_on_curva_cambiada)
		traza = v
		if traza != null and is_instance_valid(traza) and traza.curve != null:
			if not traza.curve.changed.is_connected(_on_curva_cambiada):
				traza.curve.changed.connect(_on_curva_cambiada)
		if is_inside_tree():
			_reconstruir()
			_recalcular_paradas_dinamicas()

## Si está activo, el tren se ajusta automáticamente a la traza al moverlo en el editor 3D.
@export var alinear_a_via: bool = true:
	set(v):
		var se_acaba_de_activar: bool = not alinear_a_via and v
		alinear_a_via = v
		if is_inside_tree() and alinear_a_via:
			if se_acaba_de_activar:
				_snap_a_posicion_actual()
			elif _cuerpos.size() > 0:
				_ubicar(0.0)

## Posición métrica inicial sobre la curva (en metros).
@export var avance_inicial: float = 0.0:
	set(v):
		avance_inicial = v
		_avance = avance_inicial
		if is_inside_tree():
			if traza != null and is_instance_valid(traza) and traza.curve != null and traza.curve.point_count >= 2:
				_ajustando_transform = true
				global_position = traza.to_global(traza.curve.sample_baked(_avance))
				_ajustando_transform = false
			if _cuerpos.size() == 0:
				_reconstruir()
			else:
				_ubicar(0.0)

## Pulsá este botón en el Inspector para forzar el ajuste del tren al punto más cercano de la vía.
@export var alinear_a_posicion_actual: bool = false:
	set(v):
		if v:
			alinear_a_posicion_actual = false
			if is_inside_tree():
				alinear_a_via = true
				_snap_a_posicion_actual()

@export var cantidad_coches: int = 7:
	set(v):
		cantidad_coches = maxi(1, v)
		if is_inside_tree():
			_reconstruir()

@export_group("Dirección y Marcha")
## Si está activo, el tren circula en reversa / sentido decreciente (-) de la vía.
@export var invertir_sentido: bool = false:
	set(v):
		invertir_sentido = v
		if is_inside_tree():
			_buscar_proxima_parada(true)

@export var velocidad_max_kmh: float = 90.0
@export var aceleracion: float = 0.8          ## m/s²
@export var desaceleracion: float = 1.0        ## m/s²
@export var tiempo_parada: float = 20.0        ## segundos en estación

@export_group("Detección de Paradas")
## Detecta automáticamente las estaciones en la escena y calcula su progreso métrico en la traza.
@export var autodetectar_estaciones: bool = true:
	set(v):
		autodetectar_estaciones = v
		if is_inside_tree():
			_recalcular_paradas_dinamicas()

## Distancia lateral máxima (en metros) para considerar que una estación pertenece a esta traza.
@export var distancia_maxima_via: float = 45.0:
	set(v):
		distancia_maxima_via = maxf(1.0, v)
		if is_inside_tree():
			_recalcular_paradas_dinamicas()

@export var paradas: PackedFloat32Array = PackedFloat32Array() ## Progresos en metros

@export_group("Modo de Detención")
## Modo de parada en estaciones:
## - Cabina en Poste: La trompa de la cabina delantera activa se alinea exactamente con el Poste de Parada de la estación.
## - Centro de Formación: El punto medio de la formación completa se centra respecto al andén.
@export_enum("Cabina en Poste", "Centro de Formación") var modo_detencion: int = 0

@export_group("Dimensiones Ferroviarias")
@export var paso: float = 26.0:                ## Distancia entre centros de coches (m)
	set(v):
		paso = v
		if is_inside_tree() and _cuerpos.size() > 0:
			_ubicar(0.0)

@export var semi_bogie: float = 8.90:          ## Distancia del centro al bogie (m)
	set(v):
		semi_bogie = v
		if is_inside_tree() and _cuerpos.size() > 0:
			_ubicar(0.0)

@export var radio_rueda: float = 0.43          ## Radio de rueda para rodadura (m)

@export_group("Modelos de Coche")
@export var escena_coche_motriz: PackedScene:
	set(v):
		escena_coche_motriz = v
		if is_inside_tree():
			_reconstruir()

@export var escena_coche_remolcado: PackedScene:
	set(v):
		escena_coche_remolcado = v
		if is_inside_tree():
			_reconstruir()

var _cuerpos: Array[Node3D] = []
var _ruedas: Array[Array] = []

var _avance: float = 0.0
var _vel: float = 0.0
var _idx_parada: int = 0
var _detenido: bool = false
var _espera: float = 0.0
var _datos_paradas: Array[Dictionary] = []
var _debe_invertir_en_salida: bool = false

var _ajustando_transform: bool = false
var _pendiente_snap: bool = false
var _tiempo_ultimo_movimiento: int = 0

var _frenando_estacion: bool = false
var _dispersion_parada: float = 0.0
var _desaceleracion_actual: float = 0.0
var _aceleracion_actual: float = 0.0


func _ready() -> void:
	add_to_group("trenes")
	set_notify_transform(true)
	set_process(true)

	if traza == null:
		_autodetectar_traza()

	if traza != null and is_instance_valid(traza) and traza.curve != null:
		if not traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.connect(_on_curva_cambiada)

	_avance = avance_inicial
	_reconstruir()
	_recalcular_paradas_dinamicas()
	_buscar_proxima_parada()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_POST_ENTER_TREE:
			add_to_group("trenes")
			set_notify_transform(true)
			set_process(true)
			if traza == null:
				_autodetectar_traza()
			if traza != null and is_instance_valid(traza) and traza.curve != null:
				if not traza.curve.changed.is_connected(_on_curva_cambiada):
					traza.curve.changed.connect(_on_curva_cambiada)
			if alinear_a_via and traza != null and is_inside_tree() and traza.curve != null and traza.curve.point_count >= 2:
				if _cuerpos.size() > 0:
					_ubicar(0.0)

		NOTIFICATION_TRANSFORM_CHANGED:
			if _ajustando_transform or animar_en_editor:
				return
			if alinear_a_via and traza != null and is_instance_valid(traza) and traza.curve != null and Engine.is_editor_hint():
				_pendiente_snap = true
				_tiempo_ultimo_movimiento = Time.get_ticks_msec()


func _exit_tree() -> void:
	if is_in_group("trenes"):
		remove_from_group("trenes")
	if traza != null and is_instance_valid(traza) and traza.curve != null:
		if traza.curve.changed.is_connected(_on_curva_cambiada):
			traza.curve.changed.disconnect(_on_curva_cambiada)
	_limpiar()


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


## Proyecta la posición 3D actual del tren sobre la curva de la vía y ajusta avance_inicial.
func _snap_a_posicion_actual() -> void:
	if traza == null:
		_autodetectar_traza()
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	var pos_local: Vector3 = traza.to_local(global_position)
	avance_inicial = snappedf(traza.curve.get_closest_offset(pos_local), 0.1)
	_buscar_proxima_parada()
	notify_property_list_changed()


## Busca y asigna la estación objetivo más próxima según el sentido de circulación actual.
func _buscar_proxima_parada(ignorar_estacion_actual: bool = false) -> void:
	if paradas.size() == 0 or traza == null or not is_instance_valid(traza) or traza.curve == null:
		return
	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return

	var direccion: float = -1.0 if invertir_sentido else 1.0
	var mejor_idx: int = -1
	var menor_dist: float = INF

	for i: int in paradas.size():
		if ignorar_estacion_actual and i == _idx_parada:
			continue
		var dist: float = fposmod((float(paradas[i]) - _avance) * direccion, largo)
		if dist < menor_dist:
			menor_dist = dist
			mejor_idx = i

	if mejor_idx != -1:
		_idx_parada = mejor_idx
	elif paradas.size() > 0:
		_idx_parada = posmod(_idx_parada + int(direccion), paradas.size())


func _recalcular_paradas_dinamicas() -> void:
	if not autodetectar_estaciones:
		return
	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	var lista_estaciones: Array[Node] = []
	if is_inside_tree():
		lista_estaciones = get_tree().get_nodes_in_group("estaciones")

	if lista_estaciones.is_empty() and is_inside_tree():
		var raiz: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		if raiz != null:
			_buscar_estaciones_recursivo(raiz, lista_estaciones)

	var paradas_nuevas: Array[Dictionary] = []
	for e: Node in lista_estaciones:
		if not is_instance_valid(e) or not (e is Node3D) or not e.is_inside_tree():
			continue
		if "activa" in e and not e.activa:
			continue

		# Si la estación está asignada a otra traza distinta, ignorarla
		if "traza" in e and e.traza != null and e.traza != traza:
			continue

		var offset_m: float = 0.0
		if "progreso_en_via" in e and e.progreso_en_via > 0.0 and "alinear_a_via" in e and e.alinear_a_via:
			offset_m = e.progreso_en_via
		else:
			var pos_local_calc: Vector3 = traza.to_local(e.global_position)
			offset_m = traza.curve.get_closest_offset(pos_local_calc)

		var pos_local: Vector3 = traza.to_local(e.global_position)
		var punto_curva: Vector3 = traza.curve.sample_baked(offset_m)

		if pos_local.distance_to(punto_curva) <= distancia_maxima_via:
			var nombre: String = e.nombre_estacion if "nombre_estacion" in e else e.name
			var tiempo: float = float(e.tiempo_espera) if "tiempo_espera" in e else tiempo_parada
			var terminal: bool = bool(e.es_terminal) if "es_terminal" in e else false
			var off_ida: float = offset_m
			var off_vuelta: float = offset_m
			if e.has_method("obtener_offset_parada"):
				off_ida = e.obtener_offset_parada(true)
				off_vuelta = e.obtener_offset_parada(false)
			elif "desfasaje_parada_ida" in e:
				off_ida = offset_m + float(e.desfasaje_parada_ida)
				off_vuelta = offset_m + float(e.desfasaje_parada_vuelta)

			paradas_nuevas.append({
				"offset": snappedf(offset_m, 0.01),
				"offset_ida": snappedf(off_ida, 0.01),
				"offset_vuelta": snappedf(off_vuelta, 0.01),
				"nombre": nombre,
				"tiempo_espera": tiempo,
				"es_terminal": terminal,
			})

	paradas_nuevas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["offset"]) < float(b["offset"]))

	_datos_paradas = paradas_nuevas
	var lista_offsets: Array[float] = []
	for p: Dictionary in paradas_nuevas:
		lista_offsets.append(p["offset"])
	paradas = PackedFloat32Array(lista_offsets)

	if paradas.size() > 0:
		_buscar_proxima_parada()


func _buscar_estaciones_recursivo(nodo: Node, resultado: Array[Node]) -> void:
	if nodo != self and (nodo.is_in_group("estaciones") or nodo.name.begins_with("Estacion")):
		if nodo is Node3D and not resultado.has(nodo):
			resultado.append(nodo)
	for h: Node in nodo.get_children():
		_buscar_estaciones_recursivo(h, resultado)


func _on_curva_cambiada() -> void:
	if is_inside_tree():
		if _cuerpos.size() > 0:
			_ubicar(0.0)
		_recalcular_paradas_dinamicas()


func _limpiar() -> void:
	for c: Node3D in _cuerpos:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	_cuerpos.clear()
	_ruedas.clear()


func _reconstruir() -> void:
	_limpiar()

	if traza == null or not is_instance_valid(traza) or traza.curve == null or traza.curve.point_count < 2:
		return

	if not traza.is_inside_tree():
		return

	if escena_coche_motriz == null and escena_coche_remolcado == null:
		return

	_instanciar_formacion()
	_ubicar(0.0)


func _instanciar_formacion() -> void:
	for i: int in cantidad_coches:
		var es_cabecera: bool = (i == 0 or i == cantidad_coches - 1)
		var escena: PackedScene = escena_coche_motriz if es_cabecera else escena_coche_remolcado
		if escena == null:
			escena = escena_coche_motriz if escena_coche_motriz != null else escena_coche_remolcado

		var cuerpo: Node3D = escena.instantiate()
		cuerpo.name = "Coche_%d" % i
		# No asignamos owner para evitar inflar el .tscn con mallas estáticas
		add_child(cuerpo)
		_cuerpos.append(cuerpo)
		_agregar_selector_clic(cuerpo)

		var ejes: Array[Node3D] = []
		for hijo: Node in cuerpo.get_children():
			if hijo is Node3D and hijo.name.begins_with("Eje_"):
				ejes.append(hijo)
		_ruedas.append(ejes)


## Agrega un volumen invisible "pickeable" a un coche para poder seleccionar
## la formación completa con un clic en el viewport (ver señal `seleccionado`).
## No participa de la física real: solo habilita el picking del mouse.
func _agregar_selector_clic(cuerpo: Node3D) -> void:
	var selector := Area3D.new()
	selector.name = "SelectorClic"
	selector.input_ray_pickable = true
	selector.monitoring = false
	selector.monitorable = false
	selector.input_event.connect(_on_selector_input_event)

	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(3.2, 4.2, paso * 0.9)
	forma.shape = caja
	forma.position = Vector3(0.0, 2.1, 0.0)
	selector.add_child(forma)

	cuerpo.add_child(selector)


func _on_selector_input_event(_camara: Node, evento: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		seleccionado.emit()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if alinear_a_via and _pendiente_snap and not animar_en_editor:
			var clic_izq: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			var tiempo_pasado: int = Time.get_ticks_msec() - _tiempo_ultimo_movimiento
			# Cuando el usuario suelta el mouse tras arrastrar en el editor 3D
			if not clic_izq and tiempo_pasado > 60:
				_pendiente_snap = false
				_snap_a_posicion_actual()
		if not animar_en_editor:
			return

	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return

	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return

	var direccion: float = -1.0 if invertir_sentido else 1.0

	if _detenido:
		_espera -= delta
		if _espera <= 0.0:
			_detenido = false
			marcha_reanudada.emit()
			if _debe_invertir_en_salida:
				_debe_invertir_en_salida = false
				invertir_sentido = not invertir_sentido
			else:
				_buscar_proxima_parada(true)

			_aceleracion_actual = 0.0
		return

	var v_max: float = velocidad_max_kmh / 3.6

	if paradas.size() > 0:
		var info_parada: Dictionary = _datos_paradas[_idx_parada] if _idx_parada < _datos_paradas.size() else {}
		var objetivo_avance: float = _calcular_avance_objetivo(info_parada, direccion)

		# Dispersión natural realista del maquinista (+/- 0.6 m)
		if not _frenando_estacion:
			_dispersion_parada = randf_range(-0.6, 0.6)

		var objetivo_efectivo: float = fposmod(objetivo_avance + _dispersion_parada * direccion, largo)
		# Distancia con signo a lo largo de la traza para evitar desbordes modulares al cruzar la marca
		var diff: float = (objetivo_efectivo - _avance) * direccion
		var dist_con_signo: float = fposmod(diff + largo * 0.5, largo) - largo * 0.5
		var dist_frenado_nominal: float = (_vel * _vel) / (2.0 * maxf(desaceleracion, 0.01))

		var debe_frenar: bool = false
		if _frenando_estacion:
			# Si ya comenzó la aproximación, mantiene el frenado hasta detenerse por completo
			debe_frenar = (dist_con_signo >= -2.0)
		else:
			debe_frenar = (dist_con_signo > 0.0 and dist_con_signo <= dist_frenado_nominal + 3.0)

		if debe_frenar:
			_frenando_estacion = true
			_aceleracion_actual = 0.0
			# Curva de desaceleración continua y progresiva
			var dist_calc: float = maxf(dist_con_signo, 0.1)
			var desac_demandada: float = (_vel * _vel) / (2.0 * dist_calc)
			desac_demandada = clampf(desac_demandada, 0.0, desaceleracion * 1.35)

			# Afloje final anti-sacudida (suavizado al aproximarse a 0 para confort de pasajeros)
			if _vel < 1.4 and dist_con_signo < 1.2:
				desac_demandada = minf(desac_demandada, maxf(0.35, desaceleracion * 0.55))

			# Límite de sacudida (jerk limit): rampa suave sin saltos de aceleración
			_desaceleracion_actual = move_toward(_desaceleracion_actual, desac_demandada, 1.8 * delta)
			_vel = maxf(0.0, _vel - _desaceleracion_actual * delta)

			# Parada total natural: velocidad casi nula o alcance del punto de detención a paso de hombre
			var parada_completada: bool = false
			if _vel <= 0.03:
				parada_completada = true
			elif dist_con_signo <= 0.03 and _vel <= 0.5:
				parada_completada = true
			elif dist_con_signo < -0.3:
				parada_completada = true

			if parada_completada:
				_vel = 0.0
				_detenido = true
				_frenando_estacion = false
				_desaceleracion_actual = 0.0
				_aceleracion_actual = 0.0

				if _datos_paradas.is_empty() or _datos_paradas.size() != paradas.size():
					_recalcular_paradas_dinamicas()
					info_parada = _datos_paradas[_idx_parada] if _idx_parada < _datos_paradas.size() else {}

				var es_term: bool = info_parada.get("es_terminal", false)
				var tiempo_est: float = float(info_parada.get("tiempo_espera", tiempo_parada))

				_espera = maxf(tiempo_est, 1.0)
				_debe_invertir_en_salida = es_term

				parada_alcanzada.emit(_idx_parada)
				_ubicar(0.0)
				return
		else:
			_aplicar_aceleracion(delta, v_max)
	else:
		_aplicar_aceleracion(delta, v_max)

	velocidad_cambiada.emit(velocidad_actual())

	var paso_avance: float = _vel * delta
	_avance = fposmod(_avance + paso_avance * direccion, largo)
	_ubicar(paso_avance)


## Aplica una curva de tracción ferroviaria realista con rampa de esfuerzo (jerk limit),
## potencia constante a media/alta velocidad y suavizado de llegada a velocidad crucero.
func _aplicar_aceleracion(delta: float, v_max: float) -> void:
	_frenando_estacion = false
	_desaceleracion_actual = 0.0

	# 1. Curva de esfuerzo de tracción (la fuerza decae suavemente con la velocidad por encima de 12 m/s)
	var factor_potencia: float = 1.0
	if _vel > 12.0:
		factor_potencia = 12.0 / _vel

	# 2. Suavizado progresivo al aproximarse a la velocidad crucero (gobernador de velocidad)
	var margen_vmax: float = clampf((v_max - _vel) / 3.0, 0.0, 1.0)
	var acel_demandada: float = aceleracion * factor_potencia * margen_vmax

	# 3. Rampa de tracción (Jerk limiter: 0.40 m/s³ para una salida progresiva y realista de andén)
	_aceleracion_actual = move_toward(_aceleracion_actual, acel_demandada, 0.40 * delta)
	_vel = clampf(_vel + _aceleracion_actual * delta, 0.0, v_max)


## Calcula el valor objetivo de `_avance` necesario para que la formación se detenga
## exactamente en la posición requerida según el sentido de circulación y modo de detención.
func _calcular_avance_objetivo(info_parada: Dictionary, direccion: float) -> float:
	var largo: float = traza.curve.get_baked_length() if traza and traza.curve else 1.0
	var offset_estacion: float = float(info_parada.get("offset", 0.0))
	var offset_poste: float = float(info_parada.get("offset_ida" if direccion > 0.0 else "offset_vuelta", offset_estacion))

	if modo_detencion == 1:
		# Modo: Centro de la formación en el centro de la estación
		var mitad_tren: float = float(cantidad_coches - 1) * paso * 0.5
		return fposmod(offset_estacion + mitad_tren, largo)

	# Modo 0 (por defecto): La nariz de la cabina delantera activa se clava en el Poste de Parada
	const MITAD_COCHE: float = 12.1 # Distancia del centro del coche motriz a su trompa
	if direccion > 0.0:
		# Sentido directo: La cabina delantera es Coche 0 (ubicada en _avance)
		# Trompa = _avance + MITAD_COCHE = offset_poste  ==>  _avance = offset_poste - MITAD_COCHE
		return fposmod(offset_poste - MITAD_COCHE, largo)
	else:
		# Sentido inverso: La cabina delantera es el último coche (Coche N-1)
		# Centro Coche N-1 = _avance - (N-1)*paso
		# Trompa Coche N-1 hacia atras = _avance - (N-1)*paso - MITAD_COCHE = offset_poste
		# ==> _avance = offset_poste + (N-1)*paso + MITAD_COCHE
		var distancia_cola: float = float(cantidad_coches - 1) * paso
		return fposmod(offset_poste + distancia_cola + MITAD_COCHE, largo)


func _ubicar(recorrido: float) -> void:
	if traza == null or not is_instance_valid(traza) or traza.curve == null:
		return

	var largo: float = traza.curve.get_baked_length()
	if largo <= 0.0:
		return

	for i: int in _cuerpos.size():
		var centro: float = _avance - paso * float(i)
		var offset_del: float = fposmod(centro + semi_bogie, largo)
		var offset_tra: float = fposmod(centro - semi_bogie, largo)

		var pos_del_local: Vector3 = traza.curve.sample_baked(offset_del)
		var pos_tra_local: Vector3 = traza.curve.sample_baked(offset_tra)

		var a: Vector3 = traza.to_global(pos_del_local)
		var b: Vector3 = traza.to_global(pos_tra_local)
		if a.distance_squared_to(b) < 0.001:
			continue

		var cuerpo: Node3D = _cuerpos[i]
		cuerpo.global_position = (a + b) * 0.5

		# El último coche va de cola: mira para el otro lado.
		var es_cola: bool = (i == _cuerpos.size() - 1)
		var objetivo: Vector3 = b if es_cola else a
		cuerpo.look_at(objetivo, Vector3.UP)

		if recorrido != 0.0:
			var sentido_coche: float = -1.0 if es_cola else 1.0
			var angulo: float = sentido_coche * recorrido / radio_rueda
			if i < _ruedas.size():
				for r: Node3D in _ruedas[i]:
					r.rotate_x(angulo)


## Velocidad instantánea en km/h
func velocidad_actual() -> float:
	return _vel * 3.6


## True si el tren está detenido en una estación (o frenando para hacerlo).
func esta_detenido() -> bool:
	return _detenido or _frenando_estacion
