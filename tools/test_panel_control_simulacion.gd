extends SceneTree
## Verifica PanelControlSimulacion: datos en vivo de reloj/flota/demora
## promedio, pausa/velocidad, y que los 3 tipos de evento se puedan disparar
## desde el formulario y aparezcan en el feedback con su impacto (incluyendo
## un evento inválido que debe mostrar el motivo de rechazo).
## Godot --headless --path . -s res://tools/test_panel_control_simulacion.gd

const MAX_FRAMES: int = 3000

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout

	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")

	var panel: PanelControlSimulacion = (load("res://ui/screens/panel_control_simulacion.tscn") as PackedScene).instantiate()
	nivel.add_child(panel)
	await process_frame

	assert(panel._controlador != null and panel._reloj != null and panel._gestor != null,
		"El panel debe resolver SimulacionController/RelojSimulacion/GestorEventos subiendo por sus ancestros")

	# --- Reloj / flota / demora promedio en vivo ---
	assert(panel._etiqueta_fecha.text != "—" and panel._etiqueta_fecha.text != "",
		"La fecha/hora debe mostrar un valor real, no el placeholder de 'sin reloj'")
	assert(panel._etiqueta_flota.text.contains("Activos:"), "El resumen de flota debe mostrar los contadores")
	assert(panel._etiqueta_demora_promedio.text.contains("Demora promedio"), "Debe mostrar la demora promedio de la flota")
	print("OK: reloj, flota y demora promedio muestran datos en vivo")

	# --- Pausa ---
	assert(not controlador.esta_pausada(), "La simulación debe arrancar corriendo")
	panel._on_pausa_pressed()
	assert(controlador.esta_pausada(), "Apretar pausa debe pausar la simulación")
	assert(panel._etiqueta_velocidad.text == "Pausada", "La etiqueta debe reflejar la pausa")
	panel._on_pausa_pressed()
	assert(not controlador.esta_pausada(), "Apretar pausa de nuevo debe reanudar")
	print("OK: el botón de pausa pausa y reanuda la simulación")

	# --- Velocidad ---
	panel._on_velocidad_cambiada(5.0)
	assert(is_equal_approx(controlador.obtener_velocidad_simulacion(), 5.0), "Cambiar el slider debe cambiar la velocidad real")
	assert(panel._etiqueta_velocidad.text == "×5.0", "La etiqueta de velocidad debe reflejar el nuevo factor")
	controlador.establecer_velocidad_simulacion(40.0)
	panel._actualizar_velocidad()
	print("OK: cambiar la velocidad desde el panel cambia la simulación real")

	# --- Disparar avería (tipo = tren) ---
	panel._opcion_tipo.select(2)
	panel._actualizar_objetivos()
	assert(panel._opcion_objetivo.item_count > 0, "Debe haber al menos un tren activo para elegir como objetivo de avería")
	panel._opcion_objetivo.select(0)
	var id_tren_averiado: int = panel._opcion_objetivo.get_item_id(0)
	panel._on_disparar_pressed()
	assert(panel._etiqueta_mensaje.text == "Avería aplicada.", "El mensaje debe confirmar la avería")
	assert(panel._etiqueta_mensaje.get_theme_color("font_color") == panel.COLOR_OK, "El mensaje de éxito debe ir en verde")
	var fila_averia: String = _buscar_fila_con(panel, "Tren %d" % id_tren_averiado)
	assert(fila_averia != "", "La avería debe aparecer en el feedback")
	assert(fila_averia.contains("1 tren") and fila_averia.contains("avería activa"),
		"La fila debe mostrar 1 tren afectado y la avería activa: '%s'" % fila_averia)
	print("OK: la avería se dispara desde el formulario y aparece activa en el feedback")

	# --- Disparar falla eléctrica (tipo = tramo) ---
	panel._opcion_tipo.select(0)
	panel._actualizar_objetivos()
	var indice_constitucion: int = _buscar_indice_objetivo(panel, "Plaza Constitución")
	assert(indice_constitucion >= 0, "Plaza Constitución debe estar en el combo de objetivos para falla eléctrica")
	panel._opcion_objetivo.select(indice_constitucion)
	panel._on_disparar_pressed()
	assert(panel._etiqueta_mensaje.text == "Evento disparado.", "La falla eléctrica debe aceptarse")
	assert(_buscar_fila_con(panel, "Falla eléctrica · Plaza Constitución") != "", "La falla eléctrica debe aparecer en el feedback")
	print("OK: la falla eléctrica se dispara desde el formulario y aparece en el feedback")

	# --- Disparar piquete (tipo = estación) + evento inválido (duplicado) ---
	# Duración amplia (500s): la falla eléctrica recién disparada en
	# Constitución congela a los trenes restantes casi 120s completos antes
	# de que arranquen, y todavía les toma ~220s simulados más llegar a
	# Yrigoyen (medido con instrumentación temporal) -- 280s no alcanzaba.
	panel._opcion_tipo.select(1)
	panel._actualizar_objetivos()
	panel._spin_duracion.value = 500.0
	var indice_yrigoyen: int = _buscar_indice_objetivo(panel, "Hipólito Yrigoyen")
	assert(indice_yrigoyen >= 0, "Hipólito Yrigoyen debe estar en el combo de objetivos para piquete")
	panel._opcion_objetivo.select(indice_yrigoyen)
	panel._on_disparar_pressed()
	assert(panel._etiqueta_mensaje.text == "Evento disparado.", "El piquete debe aceptarse")
	print("OK: el piquete se dispara desde el formulario")

	# Mismo objetivo de nuevo: debe rechazarse por "no apilar", con motivo visible.
	panel._actualizar_objetivos()
	var indice_yrigoyen_2: int = _buscar_indice_objetivo(panel, "Hipólito Yrigoyen")
	assert(indice_yrigoyen_2 >= 0, "Hipólito Yrigoyen debe seguir en el combo (la zona sigue activa)")
	panel._opcion_objetivo.select(indice_yrigoyen_2)
	panel._on_disparar_pressed()
	assert(panel._etiqueta_mensaje.text.contains("Ya hay un evento activo"), "Debe mostrar el motivo del rechazo: '%s'" % panel._etiqueta_mensaje.text)
	assert(panel._etiqueta_mensaje.get_theme_color("font_color") == panel.COLOR_ERROR, "El mensaje de rechazo debe ir en rojo")
	print("OK: un evento inválido (estación repetida) muestra el motivo de rechazo")

	# --- Esperar impacto real del piquete y verificar que el feedback lo refleje ---
	var llegado: Dictionary = {}
	controlador.tren_llego_estacion.connect(func(id_tren: int, datos_est: Dictionary) -> void:
		if str(datos_est.get("nombre", "")) == "Hipólito Yrigoyen" and llegado.is_empty():
			llegado["id"] = id_tren
	)
	if not await _esperar_hasta(func() -> bool: return not llegado.is_empty(), "algún tren llega a Hipólito Yrigoyen con el piquete activo"):
		quit(1); return

	var id_tren_afectado: int = int(llegado["id"])
	if not await _esperar_hasta(func() -> bool:
		return gestor.obtener_historial().filter(func(e: Dictionary) -> bool:
			return str(e.get("clave", "")) == "Hipólito Yrigoyen" and (e.get("trenes_afectados", {}) as Dictionary).has(id_tren_afectado)
		).size() > 0, "GestorEventos registra el tren afectado por el piquete"):
		quit(1); return

	panel._actualizar_feedback()
	var fila_piquete: String = _buscar_fila_con(panel, "Piquete · Hipólito Yrigoyen")
	assert(fila_piquete != "", "El piquete debe seguir en el feedback")
	assert(not fila_piquete.contains("0 tren"), "Una vez que un tren se vio afectado, el feedback debe mostrar al menos 1 tren: '%s'" % fila_piquete)
	print("OK: el feedback del piquete refleja el impacto real (trenes afectados) una vez que ocurre")

	nivel.queue_free()
	await process_frame
	print("OK: test_panel_control_simulacion completo")
	quit()


func _buscar_fila_con(panel: PanelControlSimulacion, fragmento: String) -> String:
	for hijo: Node in panel._lista_feedback.get_children():
		for nieto: Node in hijo.get_children():
			if nieto is Label and str((nieto as Label).text).contains(fragmento):
				return str((nieto as Label).text)
	return ""


func _buscar_indice_objetivo(panel: PanelControlSimulacion, nombre: String) -> int:
	for i: int in range(panel._opcion_objetivo.item_count):
		if panel._opcion_objetivo.get_item_text(i) == nombre:
			return i
	return -1


func _esperar_hasta(condicion: Callable, descripcion: String) -> bool:
	for i in range(MAX_FRAMES):
		if bool(condicion.call()):
			return true
		if i % 500 == 0:
			print("... esperando: %s (frame %d/%d)" % [descripcion, i, MAX_FRAMES])
		await process_frame
	printerr("FAIL: se agotó el tope de frames esperando '%s'" % descripcion)
	return false
