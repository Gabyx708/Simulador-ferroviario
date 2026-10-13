extends SceneTree
## Recorre una ida y una vuelta para comprobar las inversiones en ambas cabeceras.
## Uso: godot --headless --path . -s res://tools/test_retorno_terminales.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"

var _llegadas: Array[String] = []
var _salidas_terminal: Array[String] = []
var _sentido_antes_bosques: bool = false
var _sentido_antes_constitucion: bool = false
var _vio_bosques: bool = false
var _vio_regreso: bool = false
var _vio_nueva_ida: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2, true, false, true).timeout
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	var servicio: ServicioFerroviario = raiz.find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	assert(tren != null and servicio != null and red != null)
	assert(not servicio.solo_ida and not servicio.finalizar_al_volver)
	assert(servicio.separar_vias_por_sentido)
	assert((servicio.obtener_parada(0) as Estacion).es_terminal)
	assert((servicio.obtener_parada(servicio.cantidad_paradas() - 1) as Estacion).es_terminal)
	for otro_raw: Node in get_nodes_in_group("trenes"):
		var otro: Tren = otro_raw as Tren
		if otro != null and otro != tren:
			red.liberar_reservas_tren(otro.get_instance_id())
			otro._apartado_de_via = true
			otro._desplazamiento_lateral_actual = 4.8
			otro.set_process(false)
	tren.velocidad_max_kmh = 240.0
	tren.aceleracion = 24.0
	tren.desaceleracion = 32.0
	tren.tiempo_parada_servicio = 0.1
	tren.tiempo_parada = 0.1
	tren.capacidad_pasajeros = 80
	tren.cantidad_pasajeros_por_tanda = 80
	tren.intervalo_pasajeros = 0.02
	for estacion_raw: Node in get_nodes_in_group("estaciones"):
		if estacion_raw is Estacion:
			(estacion_raw as Estacion).tiempo_espera = 0.1
	tren.llego_a_estacion.connect(func(_datos: Dictionary, estacion: Dictionary) -> void:
		var nombre: String = str(estacion.get("nombre", ""))
		_llegadas.append(nombre)
		if nombre == "Bosques":
			_vio_bosques = true
			_sentido_antes_bosques = tren.invertir_sentido
		elif nombre == "Plaza Constitución":
			_vio_regreso = true
			_sentido_antes_constitucion = tren.invertir_sentido
		elif nombre == "Hipólito Yrigoyen" and _salidas_terminal.size() == 2:
			_vio_nueva_ida = true
	)
	tren.salio_de_estacion.connect(func(_datos: Dictionary, estacion: Dictionary) -> void:
		var nombre: String = str(estacion.get("nombre", ""))
		if nombre == "Bosques":
			assert(_vio_bosques and red.segmento_permite_sentido(tren.traza.name, false), "Bosques debe salir por una vía de VUELTA o común")
			_salidas_terminal.append(nombre)
		elif nombre == "Plaza Constitución" and _vio_regreso:
			assert(red.segmento_permite_sentido(tren.traza.name, true), "Constitución debe salir por una vía de IDA o común")
			_salidas_terminal.append(nombre)
	)

	var limite: int = Time.get_ticks_msec() + 270000
	while Time.get_ticks_msec() < limite and not _vio_nueva_ida and not tren.servicio_finalizado() and not tren._ruta_invalida:
		await process_frame
	Engine.time_scale = 1.0
	assert(not tren._ruta_invalida, "El servicio perdió la ruta: %s; segmento=%s, parada=%d, maniobra=%s" % [tren._motivo_resultado, tren.traza.name if tren.traza != null else "", tren._indice_servicio, tren._en_maniobra_terminal])
	assert(not tren.servicio_finalizado(), "El servicio debe continuar luego de la vuelta")
	assert(_salidas_terminal == ["Bosques", "Plaza Constitución"], "No se completaron ambas inversiones: %s; llegadas: %s" % [str(_salidas_terminal), str(_llegadas)])
	assert(_vio_nueva_ida, "La nueva ida debe llegar a Yrigoyen")
	print("OK: Bosques y Plaza Constitución invierten y el servicio continúa")
	quit()
