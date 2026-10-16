extends SceneTree
## Verifica que el panel de Métricas refleje el ciclo y duración de avería.
## Godot --headless --path . -s res://tools/test_panel_metricas.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	var panel: PanelMetricas = (load("res://ui/screens/panel_metricas.tscn") as PackedScene).instantiate()
	nivel.add_child(panel)
	await process_frame
	assert(panel._controlador == controlador and panel._gestor == gestor,
		"El panel debe resolver sus dependencias desde el nivel")

	var id_tren: int = int(controlador.obtener_trenes()[0].get("id", -1))
	assert(gestor.disparar_desperfecto_mecanico(id_tren, "Prueba de métrica"), "Debe iniciar la avería")
	panel._actualizar()
	var columnas: int = PanelMetricas.COLUMNAS_EVENTOS.size()
	var fila_activa: String = _buscar_fila_evento(panel._tabla_eventos, columnas, "Avería")
	assert(fila_activa.contains("Avería activa") and fila_activa.contains("Tren %d" % id_tren),
		"La tabla debe indicar que la avería sigue activa: '%s'" % fila_activa)
	var evento: Dictionary = gestor.obtener_historial()[0]
	var plazo: float = float(evento.get("plazo_retiro_s", 0.0))
	assert(plazo >= 900.0 and plazo <= 1800.0, "El plazo de retiro debe estar entre 15 y 30 minutos simulados")

	gestor._resolver_averias_vencidas(float(evento["fin_s"]))
	panel._actualizar()
	assert(controlador.obtener_tren(id_tren).is_empty(), "El tren debe retirarse al vencer el plazo")
	var fila_cerrada: String = _buscar_fila_evento(panel._tabla_eventos, columnas, "Avería")
	assert(fila_cerrada.contains("Tren retirado") and fila_cerrada.contains("min"),
		"La duración real debe quedar visible tras retirar el tren: '%s'" % fila_cerrada)
	assert(float(gestor.obtener_historial()[0].get("duracion_s", 0.0)) >= 900.0,
		"El historial debe conservar la duración de la avería después del retiro")
	print("OK: la tabla de eventos conserva la duración de avería después de retirar el tren")

	nivel.queue_free()
	await process_frame
	quit()


func _buscar_fila_evento(tabla: GridContainer, columnas: int, fragmento: String) -> String:
	var celdas: Array[Node] = tabla.get_children()
	for inicio: int in range(columnas, celdas.size(), columnas):
		var textos: Array[String] = []
		for columna: int in range(columnas):
			var celda: Node = celdas[inicio + columna]
			textos.append(str((celda as Label).text) if celda is Label else "")
		var fila: String = " · ".join(textos)
		if fila.contains(fragmento):
			return fila
	return ""
