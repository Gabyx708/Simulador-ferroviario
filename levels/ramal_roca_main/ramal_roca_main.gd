extends BaseLevel
class_name RamalRocaMainLevel
## Nivel principal del Ramal General Roca (Constitución - Bosques)
## que utiliza la red ferroviaria topológica real (TrackNetwork)
## adaptada a los nuevos cambios de vía procedurales (Tipos A, B, C, D, E)
## con extremos flexibles adaptativos y curvatura continua C1.

@export_group("Componentes del Nivel")
@export var red_ferroviaria: TrackNetwork
@export_range(4, 32, 1) var trenes_iniciales: int = 4
@export_range(0.0, 60.0, 0.5) var intervalo_salida_inicial: float = 6.0

const ESCENA_TREN: PackedScene = preload("res://scenes/train/tren_csr.tscn")
signal tren_agregado(tren: Tren)

var _tren_inicializado: bool = false
var _flotilla_inicializada: bool = false
var _estacion_origen: Estacion
var _servicio: ServicioFerroviario
var _vias_salida: Array[Dictionary] = []
var _vagones_en_cola: int = 0


func _ready() -> void:
	super._ready()

	if red_ferroviaria == null:
		red_ferroviaria = find_child("TrackNetwork", true, false) as TrackNetwork
	if red_ferroviaria == null:
		red_ferroviaria = find_child("RedFerroviaria", true, false) as TrackNetwork

	if red_ferroviaria != null:
		if not red_ferroviaria.red_cargada.is_connected(_on_red_cargada):
			red_ferroviaria.red_cargada.connect(_on_red_cargada)
		if not red_ferroviaria.paths.is_empty():
			_inicializar_traza_y_tren()
			call_deferred("_inicializar_flotilla")


func _process(_delta: float) -> void:
	if _vagones_en_cola <= 0 or not _flotilla_inicializada:
		return
	var libre: Dictionary = _primera_via_libre()
	if libre.is_empty():
		return
	_vagones_en_cola -= 1
	var tren: Tren = _crear_tren_en_via(libre.get("traza") as Path3D, bool(libre.get("invertido", true)), get_tree().get_nodes_in_group("trenes").size())
	if tren != null and _vagones_en_cola > 0:
		tren.configurar_tiempos_servicio(tren.demora_salida_inicial + float(_vagones_en_cola) * intervalo_salida_inicial, tren.tiempo_parada_servicio)


func _on_red_cargada(_total_segmentos: int, _total_uniones: int) -> void:
	_inicializar_traza_y_tren()
	_inicializar_flotilla()


func _inicializar_flotilla() -> void:
	if _flotilla_inicializada or red_ferroviaria == null:
		return
	_estacion_origen = find_child("EstacionPlazaConstitucion", true, false) as Estacion
	_servicio = find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	var formaciones: Node = find_child("Formaciones", true, false)
	if _estacion_origen == null or _servicio == null or formaciones == null or _servicio.cantidad_paradas() < 2:
		return
	_vias_salida = _resolver_vias_salida()
	if _vias_salida.is_empty():
		push_error("RamalRocaMainLevel: no hay vías de Constitución con ruta válida a Yrigoyen.")
		return
	# Las formaciones iniciales viven en la escena para que se puedan ubicar y
	# ajustar desde el editor. Sólo las altas del HUD se instancian en runtime.
	var formaciones_iniciales: Array[Tren] = []
	for hijo: Node in formaciones.get_children():
		if hijo is Tren:
			formaciones_iniciales.append(hijo as Tren)
	if formaciones_iniciales.is_empty():
		push_error("RamalRocaMainLevel: no hay formaciones iniciales en la escena.")
		return
	# Estas vías, y en este orden, son los puestos de salida disponibles para
	# el HUD. Se obtienen de los trenes que el usuario dejó dibujados en la
	# escena: así el quinto tren queda en cola cuando las cuatro están ocupadas.
	_vias_salida = _vias_salida_de_formaciones(formaciones_iniciales)
	for indice: int in formaciones_iniciales.size():
		var tren_inicial: Tren = formaciones_iniciales[indice]
		if tren_inicial.servicio == null:
			tren_inicial.servicio = _servicio
		var via_inicial: Dictionary = _buscar_via_por_traza(tren_inicial.traza)
		if not via_inicial.is_empty():
			# La orientación del Path3D es local: este valor sólo indica si el
			# offset aumenta o disminuye al salir hacia Yrigoyen.
			tren_inicial.sentido_local_inicio_invertido = bool(via_inicial.get("invertido", true))
		tren_inicial.set_meta("via_salida_constitucion", tren_inicial.traza.name if tren_inicial.traza != null else "")
		_vincular_tren(tren_inicial)
	_flotilla_inicializada = true
	if formaciones_iniciales.size() < trenes_iniciales:
		push_warning("Hay %d formaciones iniciales en escena; se esperaban %d." % [formaciones_iniciales.size(), trenes_iniciales])


func _vias_salida_de_formaciones(formaciones_iniciales: Array[Tren]) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for tren: Tren in formaciones_iniciales:
		if tren.traza == null or not is_instance_valid(tren.traza):
			continue
		var duplicada: bool = false
		for via: Dictionary in resultado:
			if via.get("traza") == tren.traza:
				duplicada = true
				break
		if duplicada:
			push_warning("Dos trenes iniciales comparten %s; el segundo no será una salida de despacho." % tren.traza.name)
			continue
		var via_calculada: Dictionary = _buscar_via_por_traza(tren.traza)
		if via_calculada.is_empty():
			via_calculada = {"traza": tren.traza, "invertido": tren.sentido_local_inicio_invertido}
		resultado.append(via_calculada)
	return resultado


func _resolver_vias_salida() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	var candidatos: Array[Dictionary] = _estacion_origen.obtener_puntos_parada_multivia(red_ferroviaria, true)
	var destino: Node = _servicio.obtener_parada(1)
	if destino == null:
		return resultado
	var destinos: Array[Dictionary] = []
	if destino.has_method("obtener_puntos_parada_multivia"):
		destinos = destino.call("obtener_puntos_parada_multivia", red_ferroviaria, true) as Array[Dictionary]
	var grupos: Array[Dictionary] = []
	for candidato: Dictionary in candidatos:
		var path: Path3D = candidato.get("traza") as Path3D
		if path == null:
			continue
		var mejor_ruta: Dictionary = {}
		var sentido_mejor: bool = false
		for sentido: bool in [true, false]:
			for parada_destino: Dictionary in destinos:
				var destino_traza: Path3D = parada_destino.get("traza") as Path3D
				if destino_traza == null:
					continue
				var ruta: Dictionary = red_ferroviaria.planificar_ruta(path.name, float(candidato.get("offset", 0.0)), sentido, destino_traza.name, float(parada_destino.get("offset", 0.0)))
				if bool(ruta.get("ok", false)) and (mejor_ruta.is_empty() or float(ruta.get("distancia_m", INF)) < float(mejor_ruta.get("distancia_m", INF))):
					mejor_ruta = ruta
					sentido_mejor = sentido
		if mejor_ruta.is_empty():
			continue
		# En el marco de Estacion, X es longitudinal (largo del andén) y Z
		# transversal (separación entre vías). Agrupar por X colapsaba las cuatro
		# vías de Constitución en apenas dos salidas.
		var lateral: float = _estacion_origen.to_local(candidato.get("punto_global", _estacion_origen.global_position) as Vector3).z
		var elegido: Dictionary = {"traza": path, "offset": float(candidato.get("offset", 0.0)), "lateral": lateral, "invertido": sentido_mejor, "ruta": mejor_ruta}
		var grupo_existente: int = -1
		for indice: int in grupos.size():
			if absf(float(grupos[indice].get("lateral", 0.0)) - lateral) < 3.0:
				grupo_existente = indice
				break
		if grupo_existente < 0:
			grupos.append(elegido)
		elif float(mejor_ruta.get("distancia_m", INF)) < float((grupos[grupo_existente].get("ruta", {}) as Dictionary).get("distancia_m", INF)):
			grupos[grupo_existente] = elegido
	grupos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("lateral", 0.0)) < float(b.get("lateral", 0.0)))
	for grupo: Dictionary in grupos:
		resultado.append(grupo)
	return resultado


func _buscar_via_por_traza(path: Path3D) -> Dictionary:
	for via: Dictionary in _vias_salida:
		if via.get("traza") == path:
			return via
	return {}


func _crear_tren_en_via(path: Path3D, invertido: bool, indice: int) -> Tren:
	var formaciones: Node = find_child("Formaciones", true, false)
	if formaciones == null or path == null:
		return null
	var tren: Tren = ESCENA_TREN.instantiate() as Tren
	if tren == null:
		return null
	tren.name = "TrenCSR_%02d" % (indice + 1)
	tren.traza = path
	tren.servicio = _servicio
	tren.sentido_local_inicio_invertido = invertido
	tren.configurar_tiempos_servicio(float(indice) * intervalo_salida_inicial, 3.0 + float(indice % 4) * 1.0)
	tren.set_meta("via_salida_constitucion", path.name)
	formaciones.add_child(tren)
	_vincular_tren(tren)
	tren_agregado.emit(tren)
	return tren


func _vincular_tren(tren: Tren) -> void:
	if tren == null:
		return
	if not tren.seleccionado.is_connected(_on_tren_seleccionado.bind(tren)):
		tren.seleccionado.connect(_on_tren_seleccionado.bind(tren))
	if not tren.eliminado.is_connected(_on_tren_eliminado.bind(tren)):
		tren.eliminado.connect(_on_tren_eliminado.bind(tren))


func agregar_tren() -> Tren:
	if not _flotilla_inicializada:
		_inicializar_flotilla()
	if _vias_salida.is_empty():
		return null
	var mejor: Dictionary = _primera_via_libre()
	if mejor.is_empty():
		_vagones_en_cola += 1
		push_warning("Tren agregado a la cola de despacho de Constitución (%d pendientes)." % _vagones_en_cola)
		return null
	var path_elegido: Path3D = mejor.get("traza") as Path3D
	var tren_nuevo: Tren = _crear_tren_en_via(path_elegido, bool(mejor.get("invertido", true)), get_tree().get_nodes_in_group("trenes").size())
	return tren_nuevo


func _primera_via_libre() -> Dictionary:
	for via: Dictionary in _vias_salida:
		var path: Path3D = via.get("traza") as Path3D
		if path == null:
			continue
		var en_uso: bool = false
		for nodo: Node in get_tree().get_nodes_in_group("trenes"):
			if nodo is Tren and not (nodo as Tren).esta_eliminado() and (nodo as Tren).traza == path:
				en_uso = true
				break
		if not en_uso and not red_ferroviaria.segmento_reservado(path.name):
			return via
	return {}


func trenes_en_cola() -> int:
	return _vagones_en_cola


func _inicializar_traza_y_tren() -> void:
	if red_ferroviaria == null or _tren_inicializado:
		return

	# La escena puede traer una traza y posición de inicio elegidas en el
	# Inspector. No se deben sobrescribir cuando la red se vuelve a cargar.
	if formacion_principal != null and "traza" in formacion_principal:
		var traza_configurada: Path3D = formacion_principal.get("traza") as Path3D
		if traza_configurada != null and is_instance_valid(traza_configurada) and traza_configurada.curve != null:
			traza = traza_configurada
			_tren_inicializado = true
			return

	# Buscar segmento troncal para posicionar la formación (ej. seg_470 o seg_471 en Constitución)
	var tramo_candidato: Path3D = null
	for id_candidato in ["seg_470", "seg_471", "seg_1", "seg_179"]:
		if red_ferroviaria.paths.has(id_candidato):
			tramo_candidato = red_ferroviaria.paths[id_candidato] as Path3D
			break

	if tramo_candidato == null and not red_ferroviaria.paths.is_empty():
		tramo_candidato = red_ferroviaria.paths.values()[0] as Path3D

	if tramo_candidato != null:
		traza = tramo_candidato
		if formacion_principal != null:
			if formacion_principal.has_method("set_traza"):
				formacion_principal.call("set_traza", traza)
			elif "traza" in formacion_principal:
				formacion_principal.set("traza", traza)
			formacion_principal.set("avance_inicial", 10.0)
			if formacion_principal.has_method("_ubicar"):
				formacion_principal.call("_ubicar", 0.0)
		_tren_inicializado = true

