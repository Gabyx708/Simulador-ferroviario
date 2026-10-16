extends BaseLevel
class_name RamalRocaMainLevel
## Nivel principal del Ramal General Roca (Constitución - Bosques)
## que utiliza la red ferroviaria topológica real (TrackNetwork)
## adaptada a los nuevos cambios de vía procedurales (Tipos A, B, C, D, E)
## con extremos flexibles adaptativos y curvatura continua C1.

@export_group("Componentes del Nivel")
@export var red_ferroviaria: TrackNetwork
@export_range(4, 32, 1) var trenes_iniciales: int = 4

const ESCENA_TREN: PackedScene = preload("res://scenes/train/tren_csr.tscn")
const MARCADORES_CONSTITUCION_NO_DISPONIBLES: Array[String] = [
	"MarkerTrenIda1",
	"MarkerTrenVuelta1",
	"MarkerTrenIda2",
	"MarkerTrenVuelta2",
]
signal tren_agregado(tren: Tren)

var _tren_inicializado: bool = false
var _flotilla_inicializada: bool = false
var _estacion_origen: Estacion
var _servicio: ServicioFerroviario
var _vias_salida: Array[Dictionary] = []
## Puestos de despacho definidos visualmente mediante Marker3D. Cada uno se
## proyecta sobre su propia vía, por lo que el nivel no está limitado a cuatro
## formaciones iniciales.
var _puestos_instancia: Array[Dictionary] = []
var _puesto_salida_bosques: Dictionary = {}
var _vagones_en_cola: int = 0
var _vagones_bosques_en_cola: int = 0
var _ultimo_tren_despachado: Tren
var _ultimo_tren_despachado_bosques: Tren


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
	if Engine.time_scale == 0.0:
		return
	if not _flotilla_inicializada:
		return
	if _vagones_en_cola > 0:
		var libre: Dictionary = _primer_puesto_libre()
		if not libre.is_empty():
			_vagones_en_cola -= 1
			_crear_tren_en_puesto(libre, get_tree().get_nodes_in_group("trenes").size())
	if _vagones_bosques_en_cola > 0:
		var libre_bosques: Dictionary = _primer_puesto_libre_bosques()
		if not libre_bosques.is_empty():
			_vagones_bosques_en_cola -= 1
			_crear_tren_en_puesto(libre_bosques, get_tree().get_nodes_in_group("trenes").size(), _servicio.cantidad_paradas() - 1)


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
	_puestos_instancia = _resolver_puestos_instancia()
	if _puestos_instancia.is_empty():
		push_error("RamalRocaMainLevel: no hay puestos de instancia con ruta válida a Yrigoyen.")
		return
	_puesto_salida_bosques = _resolver_puesto_salida_bosques()
	if _puesto_salida_bosques.is_empty():
		push_warning("RamalRocaMainLevel: no se encontró una ruta válida desde MarkerTrenVuelta1 de Bosques hacia Constitución.")
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
		tren_inicial.configurar_tiempos_servicio(0.0, tren_inicial.tiempo_parada_servicio)
		tren_inicial.establecer_salida_inicial_habilitada(indice == 0)
		tren_inicial.set_meta("via_salida_constitucion", tren_inicial.traza.name if tren_inicial.traza != null else "")
		_vincular_tren(tren_inicial)
		if _ultimo_tren_despachado != null:
			_vincular_separacion_estacion(_ultimo_tren_despachado, tren_inicial)
		_ultimo_tren_despachado = tren_inicial
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
		# Las cuatro formaciones de escena son el plano de salida autoritativo:
		# su sentido local fue ajustado junto con su posición en el editor. No se
		# reemplaza por un camino topológicamente más corto que pueda volver por
		# la terminal antes de salir hacia Yrigoyen.
		resultado.append({"traza": tren.traza, "invertido": tren.sentido_local_inicio_invertido})
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


## Convierte cada Marker3D de MarcadoresDeInstancia en un puesto real. El
## sentido se elige por una ruta válida a la segunda estación del servicio.
func _resolver_puestos_instancia() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	if red_ferroviaria == null or _servicio == null:
		return resultado
	var contenedor: Node = find_child("MarcadoresDeInstancia", true, false)
	var destino: Node = _servicio.obtener_parada(1)
	if contenedor == null or destino == null or not destino.has_method("obtener_puntos_parada_multivia"):
		return resultado
	var destinos: Array[Dictionary] = destino.call("obtener_puntos_parada_multivia", red_ferroviaria, true) as Array[Dictionary]
	var marcadores: Array[Marker3D] = []
	var contenedor_constitucion: Node = contenedor.find_child("Constitucion", true, false)
	var nodo_marcadores: Node = contenedor_constitucion if contenedor_constitucion != null else contenedor
	for hijo: Node in nodo_marcadores.get_children():
		if hijo is Marker3D:
			marcadores.append(hijo as Marker3D)
	marcadores.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	for marcador: Marker3D in marcadores:
		if marcador.name in MARCADORES_CONSTITUCION_NO_DISPONIBLES:
			continue
		var segmento: String = str(red_ferroviaria.call("get_closest_segment", marcador.global_position))
		var path: Path3D = red_ferroviaria.call("get_segment_path", segmento) as Path3D
		if path == null or path.curve == null or path.curve.point_count < 2:
			push_warning("%s no está sobre una vía válida." % marcador.name)
			continue
		# Los andenes de vuelta reciben las llegadas: un tren nuevo sale de ida y
		# sólo puede ocupar un andén que admita ese sentido.
		if not red_ferroviaria.segmento_permite_sentido(segmento, true):
			continue
		var avance: float = path.curve.get_closest_offset(path.to_local(marcador.global_position))
		var mejor: Dictionary = {}
		var invertido: bool = false
		var sin_override: Array[String] = []
		for sentido: bool in [false, true]:
			for parada_destino: Dictionary in destinos:
				var destino_traza: Path3D = parada_destino.get("traza") as Path3D
				if destino_traza == null:
					continue
				var ruta: Dictionary = red_ferroviaria.planificar_ruta(path.name, avance, sentido, destino_traza.name, float(parada_destino.get("offset", 0.0)), sin_override, {}, true)
				if bool(ruta.get("ok", false)) and (mejor.is_empty() or float(ruta.get("distancia_m", INF)) < float(mejor.get("distancia_m", INF))):
					mejor = ruta
					invertido = sentido
		if mejor.is_empty():
			push_warning("%s no tiene ruta desde %s hacia Yrigoyen." % [marcador.name, path.name])
			continue
		resultado.append({"marcador": marcador, "traza": path, "avance": avance, "invertido": invertido})
	return resultado


func _buscar_via_por_traza(path: Path3D) -> Dictionary:
	for via: Dictionary in _vias_salida:
		if via.get("traza") == path:
			return via
	return {}


func _resolver_puesto_salida_bosques() -> Dictionary:
	var resultado: Dictionary = {}
	if red_ferroviaria == null or _servicio == null or _servicio.cantidad_paradas() < 2:
		return resultado
	var contenedor: Node = find_child("MarcadoresDeInstancia", true, false)
	var marcador: Marker3D = contenedor.get_node_or_null("Bosques/MarkerTrenVuelta1") as Marker3D if contenedor != null else null
	if marcador == null:
		return resultado
	var segmento: String = str(red_ferroviaria.call("get_closest_segment", marcador.global_position))
	var path: Path3D = red_ferroviaria.call("get_segment_path", segmento) as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2 or not red_ferroviaria.segmento_permite_sentido(segmento, false):
		return resultado
	var avance: float = path.curve.get_closest_offset(path.to_local(marcador.global_position))
	var destino: Node = _servicio.obtener_parada(_servicio.cantidad_paradas() - 2)
	if destino == null or not destino.has_method("obtener_puntos_parada_multivia"):
		return resultado
	var destinos: Array[Dictionary] = destino.call("obtener_puntos_parada_multivia", red_ferroviaria, false) as Array[Dictionary]
	var mejor: Dictionary = {}
	var sentido_mejor: bool = false
	var sin_override: Array[String] = []
	for sentido_local: bool in [false, true]:
		for parada_destino: Dictionary in destinos:
			var destino_traza: Path3D = parada_destino.get("traza") as Path3D
			if destino_traza == null:
				continue
			var ruta: Dictionary = red_ferroviaria.planificar_ruta(path.name, avance, sentido_local, destino_traza.name, float(parada_destino.get("offset", 0.0)), sin_override, {}, false)
			if bool(ruta.get("ok", false)) and (mejor.is_empty() or float(ruta.get("distancia_m", INF)) < float(mejor.get("distancia_m", INF))):
				mejor = ruta
				sentido_mejor = sentido_local
	if mejor.is_empty():
		return resultado
	return {"marcador": marcador, "traza": path, "avance": avance, "invertido": sentido_mejor, "ruta": mejor}


func _crear_tren_en_puesto(puesto: Dictionary, indice: int, indice_origen: int = 0) -> Tren:
	var formaciones: Node = find_child("Formaciones", true, false)
	var path: Path3D = puesto.get("traza") as Path3D
	if formaciones == null or path == null:
		return null
	var tren: Tren = ESCENA_TREN.instantiate() as Tren
	if tren == null:
		return null
	tren.name = "TrenCSR_%02d" % (indice + 1)
	tren.traza = path
	tren.servicio = _servicio
	tren.indice_parada_inicial_servicio = indice_origen
	tren.sentido_local_inicio_invertido = bool(puesto.get("invertido", false))
	var avance_marcador: float = float(puesto.get("avance", 0.0))
	tren.avance_inicial = tren.avance_inicial_ajustado_a_formacion(avance_marcador, tren.sentido_local_inicio_invertido)
	tren.configurar_tiempos_servicio(0.0, 30.0)
	var salida_bosques: bool = indice_origen == _servicio.cantidad_paradas() - 1
	tren.set_meta("via_salida_bosques" if salida_bosques else "via_salida_constitucion", path.name)
	tren.set_meta("puesto_instancia", str((puesto.get("marcador") as Node).name))
	var predecesor: Tren = _ultimo_tren_despachado_bosques if salida_bosques else _ultimo_tren_despachado
	tren.establecer_salida_inicial_habilitada(predecesor == null)
	formaciones.add_child(tren)
	_vincular_tren(tren)
	if predecesor != null:
		_vincular_separacion_estacion(predecesor, tren)
	if salida_bosques:
		_ultimo_tren_despachado_bosques = tren
	else:
		_ultimo_tren_despachado = tren
	tren_agregado.emit(tren)
	return tren


## Retiene el siguiente tren hasta que el anterior llegue a la primera estación
## del recorrido. Las demoras por averías o eventos prolongan la espera.
func _vincular_separacion_estacion(predecesor: Tren, siguiente: Tren) -> void:
	if siguiente == null or not is_instance_valid(siguiente):
		return
	if predecesor == null or not is_instance_valid(predecesor) or predecesor.esta_eliminado():
		siguiente.establecer_salida_inicial_habilitada(true)
		return
	if predecesor.cumplio_distancia_seguridad_estacion():
		siguiente.establecer_salida_inicial_habilitada(true)
		return
	siguiente.establecer_salida_inicial_habilitada(false)
	var llegada: Callable = Callable(self, "_on_predecesor_llego_a_estacion").bind(predecesor, siguiente)
	if not predecesor.llego_a_estacion.is_connected(llegada):
		predecesor.llego_a_estacion.connect(llegada)
	var eliminacion: Callable = Callable(self, "_on_predecesor_eliminado").bind(predecesor, siguiente)
	if not predecesor.eliminado.is_connected(eliminacion):
		predecesor.eliminado.connect(eliminacion)


func _on_predecesor_llego_a_estacion(_datos_tren: Dictionary, _datos_estacion: Dictionary, predecesor: Tren, siguiente: Tren) -> void:
	if predecesor == null or not is_instance_valid(predecesor) or not predecesor.cumplio_distancia_seguridad_estacion():
		return
	_liberar_salida_precedida_por(predecesor, siguiente)


func _on_predecesor_eliminado(predecesor: Tren, siguiente: Tren) -> void:
	_liberar_salida_precedida_por(predecesor, siguiente)


func _liberar_salida_precedida_por(predecesor: Tren, siguiente: Tren) -> void:
	if siguiente == null or not is_instance_valid(siguiente):
		return
	if predecesor != null and is_instance_valid(predecesor):
		var llegada: Callable = Callable(self, "_on_predecesor_llego_a_estacion").bind(predecesor, siguiente)
		if predecesor.llego_a_estacion.is_connected(llegada):
			predecesor.llego_a_estacion.disconnect(llegada)
		var eliminacion: Callable = Callable(self, "_on_predecesor_eliminado").bind(predecesor, siguiente)
		if predecesor.eliminado.is_connected(eliminacion):
			predecesor.eliminado.disconnect(eliminacion)
	siguiente.establecer_salida_inicial_habilitada(true)


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
	var mejor: Dictionary = _primer_puesto_libre()
	if mejor.is_empty():
		_vagones_en_cola += 1
		push_warning("Tren agregado a la cola de despacho de Constitución (%d pendientes)." % _vagones_en_cola)
		return null
	var tren_nuevo: Tren = _crear_tren_en_puesto(mejor, get_tree().get_nodes_in_group("trenes").size())
	return tren_nuevo


func agregar_tren_en_bosques() -> Tren:
	if not _flotilla_inicializada:
		_inicializar_flotilla()
	if _puesto_salida_bosques.is_empty():
		return null
	var libre: Dictionary = _primer_puesto_libre_bosques()
	if libre.is_empty():
		_vagones_bosques_en_cola += 1
		push_warning("Tren agregado a la cola de despacho de Bosques (%d pendientes)." % _vagones_bosques_en_cola)
		return null
	return _crear_tren_en_puesto(libre, get_tree().get_nodes_in_group("trenes").size(), _servicio.cantidad_paradas() - 1)


func _primer_puesto_libre() -> Dictionary:
	for puesto: Dictionary in _puestos_instancia:
		var path: Path3D = puesto.get("traza") as Path3D
		if path == null:
			continue
		var en_uso: bool = false
		for nodo: Node in get_tree().get_nodes_in_group("trenes"):
			if nodo is Tren and not (nodo as Tren).esta_eliminado() and (nodo as Tren).ocupa_puesto_instancia(path, float(puesto.get("avance", 0.0))):
				en_uso = true
				break
		if not en_uso and not red_ferroviaria.segmento_reservado(path.name):
			return puesto
	return {}


func _primer_puesto_libre_bosques() -> Dictionary:
	var puesto: Dictionary = _puesto_salida_bosques
	var path: Path3D = puesto.get("traza") as Path3D
	if path == null:
		return {}
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren and not (nodo as Tren).esta_eliminado() and (nodo as Tren).ocupa_puesto_instancia(path, float(puesto.get("avance", 0.0))):
			return {}
	if red_ferroviaria.segmento_reservado(path.name):
		return {}
	return puesto


func trenes_en_cola() -> int:
	return _vagones_en_cola


func trenes_bosques_en_cola() -> int:
	return _vagones_bosques_en_cola


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

