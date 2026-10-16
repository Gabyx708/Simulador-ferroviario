extends SceneTree
## Godot --headless --path . -s res://tools/test_gestor_eventos.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	var reloj: RelojSimulacion = nivel.get_node("RelojSimulacion")
	var red: TrackNetwork = nivel.find_child("TrackNetwork", true, false) as TrackNetwork
	controlador.establecer_velocidad_simulacion(1.0)

	# Avería manual/F3: el tren conserva las reservas, no reanuda y el plazo
	# se mide en tiempo simulado. La pausa congela el reloj y el retiro.
	var id_manual: int = _primer_tren_disponible(controlador)
	assert(id_manual > 0, "Debe haber un tren activo para la avería manual")
	var tren_manual: Tren = gestor._trenes_conectados[id_manual] as Tren
	assert(gestor.disparar_desperfecto_mecanico(id_manual, "Prueba de avería"))
	assert(int(controlador.obtener_tren(id_manual)["estado"]) == Tren.EstadoOperacion.DETENIDO_POR_EVENTO)
	assert(red._reservas_por_tren.has(tren_manual.get_instance_id()), "Debe conservar reservas durante la avería")
	assert(not gestor.disparar_desperfecto_mecanico(id_manual, "Duplicada"), "La avería debe iniciarse una sola vez")
	var evento_manual: Dictionary = _evento_averia(gestor, id_manual)
	var plazo: float = float(evento_manual.get("plazo_retiro_s", 0.0))
	assert(plazo >= 900.0 and plazo <= 1800.0, "El plazo debe ser aleatorio entre 15 y 30 minutos simulados")

	controlador.pausar_simulacion()
	var tiempo_pausado: float = reloj.tiempo_simulado_s()
	await process_frame
	assert(is_equal_approx(reloj.tiempo_simulado_s(), tiempo_pausado), "El reloj debe congelarse al pausar")
	gestor._resolver_averias_vencidas(tiempo_pausado)
	assert(not controlador.obtener_tren(id_manual).is_empty(), "No debe retirarse durante la pausa")
	controlador.reanudar_simulacion()
	gestor._resolver_averias_vencidas(float(evento_manual["fin_s"]))
	assert(controlador.obtener_tren(id_manual).is_empty(), "Al vencer el plazo debe retirarse el tren")
	assert(not red._reservas_por_tren.has(tren_manual.get_instance_id()), "El retiro debe liberar las reservas")
	var historial_manual: Dictionary = _evento_averia(gestor, id_manual)
	assert(not bool(historial_manual.get("activo", true)), "El historial debe marcar la avería como finalizada")
	assert(is_equal_approx(float(historial_manual.get("duracion_s", 0.0)), plazo), "Debe conservar la duración real de la avería")
	print("OK: avería manual conserva reservas, respeta pausa, registra duración y retira al vencer")

	# Detección automática: el umbral sigue siendo 15 minutos simulados y
	# sólo genera un evento para el tren inmóvil.
	var id_auto: int = _primer_tren_disponible(controlador)
	assert(id_auto > 0, "Debe quedar un tren en marcha para probar la detección automática")
	var tren_auto: Tren = gestor._trenes_conectados[id_auto] as Tren
	# Preparar el estado operativo directamente deja la prueba independiente
	# del tiempo de despacho, que no forma parte de la lógica bajo prueba.
	tren_auto._estado_operacion = Tren.EstadoOperacion.EN_MARCHA
	var inicio: float = 100.0
	gestor._seguimiento_movimiento[id_auto] = {"posicion": tren_auto.posicion_cabecera_global(), "desde_s": inicio}
	gestor._revisar_trenes_sin_movimiento(inicio + 899.0)
	assert(not gestor._averias_por_tren.has(id_auto), "No debe detectar antes de 15 minutos")
	gestor._revisar_trenes_sin_movimiento(inicio + 900.0)
	assert(gestor._averias_por_tren.has(id_auto), "Debe detectar al cumplir 15 minutos simulados")
	assert(_evento_averia(gestor, id_auto).get("activo", false), "La detección automática debe registrar una avería activa")
	print("OK: detección automática inicia una sola avería a los 15 minutos simulados")

	nivel.queue_free()
	await process_frame
	quit()


func _primer_tren_en_marcha(controlador: SimulacionController) -> int:
	for datos: Dictionary in controlador.obtener_trenes():
		if int(datos.get("estado", -1)) == Tren.EstadoOperacion.EN_MARCHA:
			return int(datos.get("id", -1))
	return -1


func _primer_tren_disponible(controlador: SimulacionController) -> int:
	for datos: Dictionary in controlador.obtener_trenes():
		if int(datos.get("estado", -1)) not in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA, Tren.EstadoOperacion.INCOMPLETO]:
			return int(datos.get("id", -1))
	return -1


func _evento_averia(gestor: GestorEventos, id_tren: int) -> Dictionary:
	for evento: Dictionary in gestor.obtener_historial():
		if int(evento.get("id_tren", -1)) == id_tren and int(evento.get("tipo", -1)) == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			return evento
	return {}
