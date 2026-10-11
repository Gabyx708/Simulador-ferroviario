extends SceneTree
## Godot --headless --path . -s res://tools/test_comandos_simulacion.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var escala_original: float = Engine.time_scale
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.2, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var tren: Tren = nivel.find_child("TrenCSR", true, false) as Tren
	var red: TrackNetwork = nivel.find_child("TrackNetwork", true, false) as TrackNetwork
	var id: int = tren.obtener_id_operativo()
	var factores: Dictionary = tren.factores_prueba()
	var cambios: Array[float] = []
	var reanudaciones: Array[int] = []
	var resultados: Array[String] = []
	controlador.velocidad_simulacion_cambiada.connect(func(factor: float) -> void: cambios.append(factor))
	controlador.tren_reanudo.connect(func(id_tren: int) -> void: reanudaciones.append(id_tren))
	tren.recorrido_incompleto.connect(func(_datos: Dictionary, motivo: String) -> void: resultados.append(motivo))
	assert(not controlador.establecer_velocidad_simulacion(-1.0))
	assert(not controlador.establecer_velocidad_simulacion(INF))
	assert(not controlador.establecer_velocidad_simulacion(NAN))
	assert(cambios.is_empty())
	assert(controlador.establecer_velocidad_simulacion(2.0))
	tren.set("_frenando_estacion", true)
	assert(controlador.detener_tren_temporalmente(id, "Prueba", 0.5))
	assert(not bool(tren.get("_frenando_estacion")), "Reanudar desde velocidad cero debe volver a evaluar el frenado")
	assert(not controlador.detener_tren_temporalmente(id, "Duplicado", 1.0))
	var avance: float = float(tren.get("_avance"))
	var espera: float = float(tren.get("_espera"))
	var ruta: Array = (tren.get("_ruta_segmentos") as Array).duplicate()
	var reservado: bool = red.segmento_reservado(tren.traza.name)
	controlador.pausar_simulacion()
	controlador.pausar_simulacion()
	var restante: float = float(controlador.obtener_tren(id)["tiempo_evento_restante_s"])
	await create_timer(0.15, true, false, true).timeout
	assert(controlador.esta_pausada() and controlador.obtener_velocidad_simulacion() == 0.0)
	assert(float(controlador.obtener_tren(id)["tiempo_evento_restante_s"]) == restante)
	assert(float(tren.get("_avance")) == avance and float(tren.get("_espera")) == espera)
	assert(tren.get("_ruta_segmentos") == ruta and red.segmento_reservado(tren.traza.name) == reservado)
	controlador.reanudar_simulacion()
	assert(controlador.obtener_velocidad_simulacion() == 2.0)
	await create_timer(0.4, true, false, true).timeout
	assert(tren.obtener_estado_operacion() != Tren.EstadoOperacion.DETENIDO_POR_EVENTO)
	assert(reanudaciones.count(id) == 1)
	assert(controlador.detener_tren_temporalmente(id, "Manual", 10.0))
	assert(controlador.reanudar_tren(id))
	assert(not controlador.reanudar_tren(id))
	assert(reanudaciones.count(id) == 2)
	assert(not controlador.detener_tren_temporalmente(-1, "Error", 1.0))
	assert(not controlador.detener_tren_temporalmente(id, "", 1.0))
	assert(not controlador.detener_tren_temporalmente(id, "Error", 0.0))
	assert(controlador.finalizar_tren_incompleto(id, "Desperfecto"))
	assert(not controlador.finalizar_tren_incompleto(id, "Duplicado"))
	assert(not controlador.reanudar_tren(id))
	assert(not controlador.detener_tren_temporalmente(id, "Error", 1.0))
	assert(resultados == ["Desperfecto"])
	assert(tren.obtener_estado_operacion() == Tren.EstadoOperacion.INCOMPLETO)
	assert(not red.segmento_reservado(tren.traza.name))
	assert(tren.factores_prueba() == factores)
	assert(cambios == [2.0, 0.0, 2.0])
	nivel.queue_free()
	await process_frame
	assert(Engine.time_scale == escala_original)
	print("OK: pausa, factor, evento automático/manual e incompleto liberan reservas")
	quit()
