extends SceneTree
## Godot --headless --path . -s res://tools/test_velocidad_operativa.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 30.0
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await process_frame
	await process_frame
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	var controlador: Node = raiz.get_node_or_null("SimulacionController")
	assert(tren != null and red != null and controlador != null, "La escena debe incluir tren, red y controlador")
	assert(is_equal_approx(tren.velocidad_max_kmh, 50.0), "La formación CSR debe iniciar con 50 km/h")
	assert(is_zero_approx(float(tren.obtener_resumen_operativo().get("velocidad_media_marcha_kmh", -1.0))), "La media debe iniciar en cero")
	for nodo: Node in get_nodes_in_group("trenes"):
		var otro: Tren = nodo as Tren
		if otro != null and otro != tren:
			red.liberar_reservas_tren(otro.get_instance_id())
			otro.set_process(false)

	var limite_salida: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < limite_salida and tren.obtener_estado_operacion() != Tren.EstadoOperacion.EN_MARCHA:
		await process_frame
	assert(tren.obtener_estado_operacion() == Tren.EstadoOperacion.EN_MARCHA, "El tren debe salir de Constitución")
	while float(tren.obtener_resumen_operativo().get("velocidad_media_marcha_kmh", 0.0)) <= 0.0:
		await process_frame
	var media_antes_evento: float = float(tren.obtener_resumen_operativo().get("velocidad_media_marcha_kmh", 0.0))
	assert(bool(controlador.call("detener_tren_temporalmente", tren.obtener_id_operativo(), "Prueba de métrica", 30.0)), "El evento temporal debe aceptarse")
	await create_timer(0.2, true, false, true).timeout
	assert(is_equal_approx(float(tren.obtener_resumen_operativo().get("velocidad_media_marcha_kmh", 0.0)), media_antes_evento), "El evento no debe modificar la media de marcha")
	controlador.call("establecer_velocidad_simulacion", 0.0)
	await create_timer(0.1, true, false, true).timeout
	assert(is_equal_approx(float(tren.obtener_resumen_operativo().get("velocidad_media_marcha_kmh", 0.0)), media_antes_evento), "La pausa global no debe modificar la media")
	controlador.call("establecer_velocidad_simulacion", 30.0)

	# Recorrido suficiente con dinámica nominal: la llegada completa a Bosques
	# se verifica en test_recorrido_completo, que está optimizado para ello.
	var limite_marcha: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < limite_marcha:
		await process_frame
	var resumen: Dictionary = tren.obtener_resumen_operativo()
	var media_final: float = float(resumen.get("velocidad_media_marcha_kmh", 0.0))
	assert(tren.obtener_estado_operacion() != Tren.EstadoOperacion.INCOMPLETO, "La marcha base no debe invalidar el itinerario")
	assert(media_final >= 35.0 and media_final <= 55.0, "La media base debe quedar entre 35 y 55 km/h, fue %.2f" % media_final)
	print("OK: velocidad base editable y media operativa %.2f km/h" % media_final)
	controlador.call("establecer_velocidad_simulacion", 1.0)
	quit()
