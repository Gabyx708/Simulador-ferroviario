extends SceneTree
## Godot --headless --path . -s res://tools/test_estadisticas_retraso.gd

const MAX_FRAMES_POR_ESPERA: int = 3000  ## ~75s reales a 40x; nunca cuelga sin aviso.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var estadisticas: EstadisticasRetraso = nivel.get_node("EstadisticasRetraso")
	controlador.establecer_velocidad_simulacion(40.0)

	var tren: Tren = nivel.find_child("TrenCSR", true, false) as Tren
	var id: int = tren.obtener_id_operativo()

	var llegadas: Array[String] = []
	tren.llego_a_estacion.connect(func(_dt: Dictionary, datos_est: Dictionary) -> void:
		llegadas.append(str(datos_est.get("nombre", "?")))
	)

	# 1) Corrida limpia: sin eventos, el retraso acumulado tiene que quedarse
	#    en 0 durante varios tramos reales (valida que el factor de
	#    calibración no genere falsos positivos).
	if not await _esperar_hasta(func() -> bool: return llegadas.size() >= 3, "llegadas>=3 (corrida limpia)"):
		quit(1)
		return
	assert(estadisticas.obtener_retraso(id) == 0.0, "Corrida limpia: no debe acumular retraso falso (retraso=%f tras %s)" % [estadisticas.obtener_retraso(id), str(llegadas)])
	assert(float(tren.get("retraso_externo_s")) == 0.0)
	print("OK parcial: corrida limpia sin retraso falso tras %d tramos (%s)" % [llegadas.size(), str(llegadas)])

	# 2) Demora inducida: detener el tren 90s simulados -- a propósito en
	#    CUALQUIER momento (puede agarrarlo ya parado en andén o viajando),
	#    para probar que llegada->llegada la captura en los dos casos.
	var retraso_antes: float = estadisticas.obtener_retraso(id)
	assert(controlador.detener_tren_temporalmente(id, "Prueba de calibración", 90.0))
	var llegadas_antes: int = llegadas.size()
	if not await _esperar_hasta(func() -> bool: return llegadas.size() >= llegadas_antes + 1, "llegada tras evento de 90s"):
		quit(1)
		return
	var retraso_despues: float = estadisticas.obtener_retraso(id)
	assert(retraso_despues > retraso_antes, "Una demora de 90s debe reflejarse en retraso_s (antes=%f despues=%f)" % [retraso_antes, retraso_despues])
	assert(float(tren.get("retraso_externo_s")) == retraso_despues, "retraso_externo_s en Tren debe coincidir con lo que calcula EstadisticasRetraso")
	print("OK parcial: demora de 90s detectada (antes=%.1f despues=%.1f)" % [retraso_antes, retraso_despues])

	# 3) El retraso es acumulado: un tramo limpio después no lo resetea a 0.
	var llegadas_antes_2: int = llegadas.size()
	if not await _esperar_hasta(func() -> bool: return llegadas.size() >= llegadas_antes_2 + 1, "llegada tras tramo limpio posterior"):
		quit(1)
		return
	assert(estadisticas.obtener_retraso(id) >= retraso_despues, "El retraso no debe bajar entre tramos limpios (acumulado)")
	print("OK: demora inducida de 90s se refleja en retraso_s y se acumula (antes=%.1f despues=%.1f final=%.1f)" % [retraso_antes, retraso_despues, estadisticas.obtener_retraso(id)])

	nivel.queue_free()
	await process_frame
	print("OK: test_estadisticas_retraso completo")
	quit()


## Espera hasta que `condicion` sea true, con un tope de frames para nunca
## colgarse en silencio. Imprime progreso cada 500 frames. Devuelve false
## (y deja un mensaje claro) si se agota el tope sin cumplirse.
func _esperar_hasta(condicion: Callable, descripcion: String) -> bool:
	for i in range(MAX_FRAMES_POR_ESPERA):
		if bool(condicion.call()):
			return true
		if i % 500 == 0:
			print("... esperando: %s (frame %d/%d)" % [descripcion, i, MAX_FRAMES_POR_ESPERA])
		await process_frame
	printerr("FAIL: se agotó el tope de frames esperando '%s'" % descripcion)
	return false
