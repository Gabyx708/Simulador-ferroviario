extends SceneTree
## Godot --headless --path . -s res://tools/test_gestor_eventos.gd

const MAX_FRAMES: int = 3000

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	var red: TrackNetwork = nivel.find_child("TrackNetwork", true, false) as TrackNetwork
	controlador.establecer_velocidad_simulacion(40.0)

	# --- 1) Piquete en una estación puntual: afecta al que llega mientras
	#         está activo, y no se apila. ---
	# La duración tiene que cubrir el viaje real Constitución->Yrigoyen
	# (~226s simulados, medido en tools/diag_calibracion_retraso.gd), no un
	# número arbitrario chico, o el piquete vence antes de que llegue nadie.
	var r1: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 280.0)
	assert(bool(r1["ok"]), "Piquete debe aceptarse: %s" % str(r1))
	var r1b: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 280.0)
	assert(not bool(r1b["ok"]), "No debe apilar un segundo piquete en la misma estación")

	var llegado_yrigoyen: Dictionary = {}
	controlador.tren_llego_estacion.connect(func(id_tren: int, datos_est: Dictionary) -> void:
		if str(datos_est.get("nombre", "")) == "Hipólito Yrigoyen" and llegado_yrigoyen.is_empty():
			llegado_yrigoyen["id"] = id_tren
	)
	if not await _esperar_hasta(func() -> bool: return not llegado_yrigoyen.is_empty(), "primer tren llega a Hipólito Yrigoyen"):
		quit(1); return

	var id_piquete: int = int(llegado_yrigoyen["id"])
	var estado_tras_piquete: int = int(controlador.obtener_tren(id_piquete)["estado"])
	assert(estado_tras_piquete == Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "El tren debe quedar detenido por el piquete (estado=%d)" % estado_tras_piquete)
	assert(gestor.color_evento_activo(id_piquete) == gestor.COLOR_PIQUETE, "Color activo debe ser el de piquete")
	print("OK parcial: piquete detiene al tren que llega, no se apila, color correcto")

	if not await _esperar_hasta(func() -> bool: return int(controlador.obtener_tren(id_piquete).get("estado", -1)) != Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "piquete se vence y el tren reanuda"):
		quit(1); return
	print("OK parcial: el piquete se vence solo y el tren reanuda")

	# --- 2) Falla eléctrica en un tramo: afecta a quien SALE hacia ese
	#         tramo mientras está activo. Se prueba con un tren nuevo para
	#         no depender del timing de los 4 iniciales. ---
	var r2: Dictionary = gestor.disparar_falla_electrica("Plaza Constitución", 60.0)
	assert(bool(r2["ok"]), "Falla eléctrica debe aceptarse: %s" % str(r2))

	var nuevos_ids: Array = []
	controlador.tren_agregado.connect(func(datos_tren: Dictionary) -> void: nuevos_ids.append(int(datos_tren.get("id", -1))))
	var resultado_alta: Dictionary = controlador.agregar_tren()
	assert(bool(resultado_alta.get("ok", false)) or bool(resultado_alta.get("en_cola", false)), "agregar_tren debe aceptarse o encolarse: %s" % str(resultado_alta))

	if not await _esperar_hasta(func() -> bool: return not nuevos_ids.is_empty(), "nuevo tren registrado"):
		quit(1); return
	var id_nuevo: int = int(nuevos_ids[0])

	if not await _esperar_hasta(func() -> bool: return int(controlador.obtener_tren(id_nuevo).get("estado", -1)) == Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "el tren nuevo sale y la falla eléctrica lo detiene"):
		quit(1); return
	assert(gestor.color_evento_activo(id_nuevo) == gestor.COLOR_FALLA_ELECTRICA, "Color activo debe ser el de falla eléctrica")
	print("OK parcial: falla eléctrica detiene al tren que sale hacia el tramo afectado")

	# --- 3) Desperfecto mecánico: definitivo, libera reservas, no reanuda. ---
	var id_desperfecto: int = id_nuevo
	# Esperar a que termine la falla eléctrica ANTES de conectar tren_reanudo:
	# esa reanudación es del evento anterior, no debe contar como "reanudó
	# después del desperfecto".
	if not await _esperar_hasta(func() -> bool: return int(controlador.obtener_tren(id_desperfecto).get("estado", -1)) != Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "falla eléctrica se vence antes del desperfecto"):
		quit(1); return

	var reanudaciones: Array = []
	controlador.tren_reanudo.connect(func(id_tren: int) -> void: reanudaciones.append(id_tren))
	assert(gestor.disparar_desperfecto_mecanico(id_desperfecto, "Prueba de desperfecto"))
	var datos_final: Dictionary = controlador.obtener_tren(id_desperfecto)
	assert(int(datos_final["estado"]) == Tren.EstadoOperacion.INCOMPLETO, "Desperfecto mecánico debe dejar al tren INCOMPLETO")
	assert(gestor.color_evento_activo(id_desperfecto) == gestor.COLOR_DESPERFECTO_MECANICO, "Color activo debe ser el de desperfecto")
	assert(not gestor.disparar_desperfecto_mecanico(id_desperfecto, "Duplicado"), "No debe poder desperfectarse dos veces")
	assert(reanudaciones.count(id_desperfecto) == 0, "Un desperfecto mecánico no debe reanudar nunca")
	print("OK: desperfecto mecánico es definitivo, no reanuda, color correcto")

	var historial: Array[Dictionary] = gestor.obtener_historial()
	assert(historial.size() >= 3, "El historial debe conservar los eventos disparados (tiene %d)" % historial.size())
	print("OK: test_gestor_eventos completo (%d eventos en historial)" % historial.size())

	nivel.queue_free()
	await process_frame
	quit()


func _esperar_hasta(condicion: Callable, descripcion: String) -> bool:
	for i in range(MAX_FRAMES):
		if bool(condicion.call()):
			return true
		if i % 500 == 0:
			print("... esperando: %s (frame %d/%d)" % [descripcion, i, MAX_FRAMES])
		await process_frame
	printerr("FAIL: se agotó el tope de frames esperando '%s'" % descripcion)
	return false
