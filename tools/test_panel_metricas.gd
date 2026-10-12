extends SceneTree
## Verifica PanelMetricas: KPIs (incluyendo el caso de un tren ESPERANDO
## bloqueado por un evento, con retraso_s todavía en 0 -- punto 6 del pedido
## de mejora), comparación de eventos, tabla por tren (badges) y tabla por
## evento, todo de sólo lectura.
## Godot --headless --path . -s res://tools/test_panel_metricas.gd

const MAX_FRAMES: int = 3000

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_calcular_kpis_puro()

	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout

	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")

	var panel: PanelMetricas = (load("res://ui/screens/panel_metricas.tscn") as PackedScene).instantiate()
	nivel.add_child(panel)
	await process_frame

	assert(panel._controlador != null and panel._reloj != null and panel._estadisticas != null and panel._gestor != null,
		"El panel debe resolver SimulacionController/RelojSimulacion/EstadisticasRetraso/GestorEventos subiendo por sus ancestros")

	# --- Tabla por tren: una fila de datos por tren, con badge de estado ---
	var columnas_tren: int = PanelMetricas.COLUMNAS_TRENES.size()
	var cantidad_trenes: int = controlador.obtener_trenes().size()
	assert(cantidad_trenes > 0, "Debe haber al menos un tren para que el test sea significativo")
	assert(panel._tabla_trenes.get_child_count() == columnas_tren * (1 + cantidad_trenes),
		"La tabla de trenes debe tener %d columnas de encabezado + %d por cada tren (%d trenes)" % [columnas_tren, columnas_tren, cantidad_trenes])
	var badge_inicial: Control = panel._tabla_trenes.get_child(columnas_tren + 1) as Control
	assert(badge_inicial is PanelContainer, "El estado debe mostrarse como badge (PanelContainer con color), no como texto crudo del enum")
	print("OK: la tabla por tren tiene una fila por cada tren, con estado como badge")

	# --- KPIs arrancan en 0 ---
	assert((panel._tarjetas_kpi["pasajeros"] as Label).text.contains("0 de"), "Sin eventos, 0 pasajeros afectados")
	assert((panel._tarjetas_kpi["eventos"] as Label).text.begins_with("0 "), "Sin eventos, el contador debe arrancar en 0")
	print("OK: los KPIs arrancan en 0 eventos / 0 pasajeros afectados")

	# --- Disparar una avería real y verificar que KPIs y tablas lo reflejen ---
	var rango_tren: int = 0
	var id_tren: int = int(controlador.obtener_trenes()[rango_tren].get("id", -1))
	assert(gestor.disparar_desperfecto_mecanico(id_tren), "La avería debe aplicarse")
	panel._actualizar()

	assert((panel._tarjetas_kpi["flota"] as Label).text.contains("1 incompletos"), "El KPI de flota debe reflejar 1 incompleto")
	assert((panel._tarjetas_kpi["eventos"] as Label).text.begins_with("1 "), "El KPI de eventos debe reflejar la avería recién disparada")
	var fila_tren: String = _fila_por_indice(panel._tabla_trenes, columnas_tren, rango_tren)
	assert(fila_tren.contains("Incompleto"), "La fila del tren averiado (rango %d) debe mostrar el badge 'Incompleto': '%s'" % [rango_tren, fila_tren])
	var fila_evento: String = _buscar_fila_tabla(panel._tabla_eventos, PanelMetricas.COLUMNAS_EVENTOS.size(), "Avería")
	assert(fila_evento != "" and fila_evento.contains("Tren %d" % id_tren) and fila_evento.contains("Definitivo"),
		"La tabla de eventos debe mostrar la avería como definitiva: '%s'" % fila_evento)
	print("OK: una avería real se refleja en los KPIs y en ambas tablas")

	# --- Falla eléctrica + piquete: esperar impacto real y verificar la
	# comparación de eventos (gráfico de barras) contra el historial crudo ---
	var r_falla: Dictionary = gestor.disparar_falla_electrica("Plaza Constitución", 120.0)
	assert(bool(r_falla.get("ok", false)), "La falla eléctrica debe aceptarse: %s" % str(r_falla))
	# Duración amplia: la falla eléctrica recién disparada puede congelar un
	# tren ~120s completos antes de que arranque, y todavía le toma ~220s
	# simulados más llegar a Yrigoyen (medido en la Etapa 2) -- 280s no
	# alcanza, se usan 500s de margen.
	var r_piquete: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 500.0)
	assert(bool(r_piquete.get("ok", false)), "El piquete debe aceptarse: %s" % str(r_piquete))
	controlador.establecer_velocidad_simulacion(40.0)

	var llegado: Dictionary = {}
	controlador.tren_llego_estacion.connect(func(id: int, datos_est: Dictionary) -> void:
		if str(datos_est.get("nombre", "")) == "Hipólito Yrigoyen" and llegado.is_empty():
			llegado["id"] = id
	)
	if not await _esperar_hasta(func() -> bool: return not llegado.is_empty(), "algún tren llega a Hipólito Yrigoyen con el piquete activo"):
		quit(1); return
	var id_tren_afectado: int = int(llegado["id"])
	if not await _esperar_hasta(func() -> bool:
		return gestor.obtener_historial().filter(func(e: Dictionary) -> bool:
			return str(e.get("clave", "")) == "Hipólito Yrigoyen" and (e.get("trenes_afectados", {}) as Dictionary).has(id_tren_afectado)
		).size() > 0, "GestorEventos registra el tren afectado por el piquete"):
		quit(1); return

	# Quedar registrado como afectado pasa apenas el tren llega (frena); el
	# retraso recién se MIDE cuando ese mismo tren completa el tramo
	# siguiente (EstadisticasRetraso mide llegada a llegada). Sin esta
	# segunda espera, retraso_total_s todavía está en 0 en este punto.
	if not await _esperar_hasta(func() -> bool:
		for e: Dictionary in gestor.obtener_historial():
			if str(e.get("clave", "")) == "Hipólito Yrigoyen" and float(e.get("retraso_total_s", 0.0)) > 0.0:
				return true
		return false, "el retraso del piquete se mide (el tren completa el tramo siguiente)"):
		quit(1); return

	panel._actualizar()
	var retraso_piquete_historial: float = 0.0
	var trenes_piquete_historial: Dictionary = {}
	for e: Dictionary in gestor.obtener_historial():
		if int(e.get("tipo", -1)) == GestorEventos.TipoEvento.PIQUETE:
			retraso_piquete_historial += float(e.get("retraso_total_s", 0.0))
			for id_t: int in (e.get("trenes_afectados", {}) as Dictionary):
				trenes_piquete_historial[id_t] = true

	var datos_barra_piquete: Dictionary = {}
	for d: Dictionary in panel._grafico_barras.datos:
		if str(d.get("label", "")) == GestorEventos.nombre_tipo(GestorEventos.TipoEvento.PIQUETE):
			datos_barra_piquete = d
			break
	assert(not datos_barra_piquete.is_empty(), "El gráfico de barras debe tener una entrada para Piquete")
	assert(is_equal_approx(float(datos_barra_piquete.get("valor", -1.0)), retraso_piquete_historial),
		"El retraso de la barra de Piquete (%.2f) debe coincidir con la suma del historial (%.2f)" % [float(datos_barra_piquete.get("valor", -1.0)), retraso_piquete_historial])
	assert(int(datos_barra_piquete.get("trenes", -1)) == trenes_piquete_historial.size(),
		"La cantidad de trenes de la barra de Piquete debe coincidir con el historial")
	assert(retraso_piquete_historial > 0.0, "Un piquete de 500s debe generar retraso medible")
	print("OK: el gráfico de comparación de eventos coincide exactamente con el historial de GestorEventos")

	assert(panel._muestras_evolucion.size() > 0, "El gráfico de evolución debe tener muestras acumuladas")
	assert(panel._marcas_eventos.size() >= 2, "Debe haber una marca por cada evento de zona disparado (falla eléctrica + piquete)")
	print("OK: el gráfico de evolución acumula muestras y marcas de eventos")

	nivel.queue_free()
	await process_frame
	print("OK: test_panel_metricas completo")
	quit()


## Punto 6: un tren ESPERANDO_RESERVA (bloqueado por la reserva de otro tren,
## p.ej. uno detenido más adelante por un evento) o DETENIDO_POR_EVENTO debe
## contar como "pasajeros afectados" aunque su retraso_s siga en 0 --
## EstadisticasRetraso recién mide al llegar (llegada a llegada), así que el
## impacto en curso no se refleja ahí todavía, pero sí en estos KPIs.
## Función pura: no hace falta simulación real, con snapshots a mano alcanza.
func _test_calcular_kpis_puro() -> void:
	var trenes: Array[Dictionary] = [
		{"id": 1, "estado": Tren.EstadoOperacion.EN_MARCHA, "retraso_s": 0.0, "pasajeros": 100},
		{"id": 2, "estado": Tren.EstadoOperacion.EN_MARCHA, "retraso_s": 45.0, "pasajeros": 80},
		{"id": 3, "estado": Tren.EstadoOperacion.ESPERANDO_RESERVA, "retraso_s": 0.0, "pasajeros": 50},
		{"id": 4, "estado": Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "retraso_s": 0.0, "pasajeros": 30},
		{"id": 5, "estado": Tren.EstadoOperacion.INCOMPLETO, "retraso_s": 0.0, "pasajeros": 0},
		{"id": 6, "estado": Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, "retraso_s": 0.0, "pasajeros": 0},
	]
	var kpis: Dictionary = PanelMetricas._calcular_kpis(trenes)
	assert(int(kpis["activos"]) == 4, "4 trenes activos (no incompleto ni finalizado): %d" % int(kpis["activos"]))
	assert(int(kpis["a_tiempo"]) == 1, "Sólo el tren 1 está a tiempo: %d" % int(kpis["a_tiempo"]))
	assert(int(kpis["retrasados"]) == 1, "Sólo el tren 2 tiene retraso medido > 0: %d" % int(kpis["retrasados"]))
	assert(int(kpis["detenidos"]) == 2, "Trenes 3 (esperando) y 4 (detenido por evento): %d" % int(kpis["detenidos"]))
	assert(int(kpis["incompletos"]) == 1, "Tren 5: %d" % int(kpis["incompletos"]))
	assert(is_equal_approx(float(kpis["demora_promedio_s"]), 45.0 / 4.0),
		"Demora promedio sobre los 4 activos: %.2f" % float(kpis["demora_promedio_s"]))
	# Pasajeros afectados: tren 2 (retrasado, 80) + tren 3 (esperando, 50) +
	# tren 4 (detenido por evento, 30) = 160, aunque 3 y 4 tengan retraso_s=0.
	assert(int(kpis["pasajeros_afectados"]) == 160,
		"Pasajeros afectados debe incluir a los trenes ESPERANDO/DETENIDO aunque retraso_s sea 0: %d (esperado 160)" % int(kpis["pasajeros_afectados"]))
	assert(int(kpis["pasajeros_totales"]) == 260, "100+80+50+30 = 260: %d" % int(kpis["pasajeros_totales"]))
	assert(is_equal_approx(float(kpis["pct_pasajeros_afectados"]), 160.0 / 260.0 * 100.0),
		"Porcentaje de pasajeros afectados: %.1f%%" % float(kpis["pct_pasajeros_afectados"]))
	print("OK: _calcular_kpis cuenta como afectados a los pasajeros de trenes ESPERANDO/DETENIDO aunque retraso_s sea 0 (punto 6)")


func _fila_por_indice(tabla: GridContainer, columnas: int, rango: int) -> String:
	var celdas: Array[Node] = tabla.get_children()
	var textos: Array[String] = []
	for col: int in range(columnas):
		var nodo: Node = celdas[columnas * (rango + 1) + col]
		textos.append(_texto_de_celda(nodo))
	return " · ".join(textos)


func _buscar_fila_tabla(tabla: GridContainer, columnas: int, fragmento: String) -> String:
	var celdas: Array[Node] = tabla.get_children()
	var filas: int = (celdas.size() / columnas) - 1
	for fila: int in range(filas):
		var indices: Array = []
		for col: int in range(columnas):
			indices.append(columnas * (fila + 1) + col)
		var coincide: bool = false
		for i: int in indices:
			if _texto_de_celda(celdas[i]).contains(fragmento):
				coincide = true
				break
		if coincide:
			var textos: Array[String] = []
			for i: int in indices:
				textos.append(_texto_de_celda(celdas[i]))
			return " · ".join(textos)
	return ""


## Una celda puede ser un Label directo o un badge (PanelContainer con un
## Label adentro, ver _crear_badge_estado).
func _texto_de_celda(nodo: Node) -> String:
	if nodo is Label:
		return str((nodo as Label).text)
	for hijo: Node in nodo.get_children():
		if hijo is Label:
			return str((hijo as Label).text)
	return ""


func _esperar_hasta(condicion: Callable, descripcion: String) -> bool:
	for i in range(MAX_FRAMES):
		if bool(condicion.call()):
			return true
		if i % 500 == 0:
			print("... esperando: %s (frame %d/%d)" % [descripcion, i, MAX_FRAMES])
		await process_frame
	printerr("FAIL: se agotó el tope de frames esperando '%s'" % descripcion)
	return false
