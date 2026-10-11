extends SceneTree
## Verifica PanelMetricas: tabla por tren, tabla por evento y la fila de
## totales (demora promedio, incompletos), todo de sólo lectura.
## Godot --headless --path . -s res://tools/test_panel_metricas.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout

	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")

	var panel: PanelMetricas = (load("res://ui/screens/panel_metricas.tscn") as PackedScene).instantiate()
	nivel.add_child(panel)
	await process_frame

	assert(panel._controlador != null and panel._estadisticas != null and panel._gestor != null,
		"El panel debe resolver SimulacionController/EstadisticasRetraso/GestorEventos subiendo por sus ancestros")

	# --- Tabla por tren: una fila de datos por tren activo ---
	var columnas_tren: int = PanelMetricas.COLUMNAS_TRENES.size()
	var cantidad_trenes: int = controlador.obtener_trenes().size()
	assert(cantidad_trenes > 0, "Debe haber al menos un tren para que el test sea significativo")
	assert(panel._tabla_trenes.get_child_count() == columnas_tren * (1 + cantidad_trenes),
		"La tabla de trenes debe tener %d columnas de encabezado + %d por cada tren (%d trenes)" % [columnas_tren, columnas_tren, cantidad_trenes])
	print("OK: la tabla por tren tiene una fila por cada tren de la flota")

	# --- Totales: arrancan en 0 incompletos ---
	assert(panel._etiqueta_totales.text.contains("Demora promedio"), "Debe mostrar la demora promedio")
	assert(panel._etiqueta_totales.text.contains("Pasajeros con demora"), "Debe mostrar pasajeros con demora")
	assert(panel._etiqueta_totales.text.contains("Incompletos: 0"), "Todavía no hay averías: 0 incompletos")
	print("OK: la fila de totales muestra demora promedio, pasajeros con demora e incompletos en vivo")

	# --- Disparar una avería real y verificar que ambas tablas y los totales lo reflejen ---
	# Se busca la fila por posición (rango del id entre obtener_trenes(), que
	# ya viene ordenado por id) en vez de por nombre: varios trenes de la
	# flota inicial comparten el mismo nombre genérico, así que una búsqueda
	# por texto podría matchear la fila de otro tren.
	var rango_tren: int = 0
	var id_tren: int = int(controlador.obtener_trenes()[rango_tren].get("id", -1))
	assert(gestor.disparar_desperfecto_mecanico(id_tren), "La avería debe aplicarse")
	panel._actualizar()

	assert(panel._etiqueta_totales.text.contains("Incompletos: 1"), "Tras la avería debe haber 1 incompleto")
	var fila_tren: String = _fila_por_indice(panel._tabla_trenes, columnas_tren, rango_tren)
	assert(fila_tren.contains("INCOMPLETO"), "La fila del tren averiado (rango %d) debe mostrar su nuevo estado: '%s'" % [rango_tren, fila_tren])

	var fila_evento: String = _buscar_fila_tabla(panel._tabla_eventos, 4, "Avería")
	assert(fila_evento != "" and fila_evento.contains("Tren %d" % id_tren) and fila_evento.contains("· 1 ·"),
		"La tabla de eventos debe mostrar la avería con 1 tren afectado: '%s'" % fila_evento)
	print("OK: una avería real se refleja en ambas tablas y en los totales")

	# --- Disparar un piquete y verificar que aparece en la tabla de eventos ---
	var r: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 120.0)
	assert(bool(r.get("ok", false)), "El piquete debe aceptarse: %s" % str(r))
	panel._actualizar()
	var fila_piquete: String = _buscar_fila_tabla(panel._tabla_eventos, 4, "Piquete")
	assert(fila_piquete != "" and fila_piquete.contains("Hipólito Yrigoyen"),
		"La tabla de eventos debe mostrar el piquete recién disparado: '%s'" % fila_piquete)
	print("OK: la tabla por evento se actualiza con eventos nuevos")

	nivel.queue_free()
	await process_frame
	print("OK: test_panel_metricas completo")
	quit()


## Concatena las celdas de la fila de datos en la posición `rango` (0 =
## primera fila después del encabezado de `columnas` celdas).
func _fila_por_indice(tabla: GridContainer, columnas: int, rango: int) -> String:
	var celdas: Array[Node] = tabla.get_children()
	var textos: Array[String] = []
	for col: int in range(columnas):
		textos.append(str((celdas[columnas * (rango + 1) + col] as Label).text))
	return " · ".join(textos)


## Concatena el texto de todas las celdas de la fila de datos (saltando el
## encabezado de `columnas` celdas) que contenga `fragmento` en alguna celda,
## para poder revisar el resto de esa misma fila con un solo string.
func _buscar_fila_tabla(tabla: GridContainer, columnas: int, fragmento: String) -> String:
	var celdas: Array[Node] = tabla.get_children()
	var filas: int = (celdas.size() / columnas) - 1
	for fila: int in range(filas):
		var indices: Array = []
		for col: int in range(columnas):
			indices.append(columnas * (fila + 1) + col)
		var coincide: bool = false
		for i: int in indices:
			if str((celdas[i] as Label).text).contains(fragmento):
				coincide = true
				break
		if coincide:
			var textos: Array[String] = []
			for i: int in indices:
				textos.append(str((celdas[i] as Label).text))
			return " · ".join(textos)
	return ""
