extends SceneTree
## Verifica que el retraso_total_s atribuido a un evento por GestorEventos
## coincide con el retraso real que EstadisticasRetraso le midió al tren
## afectado en el tramo que generó esa demora.
## Godot --headless --path . -s res://tools/test_atribucion_eventos.gd

const MAX_FRAMES: int = 3000

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	var estadisticas: EstadisticasRetraso = nivel.get_node("EstadisticasRetraso")
	controlador.establecer_velocidad_simulacion(40.0)

	# Verdad de referencia: capturo yo mismo cada aporte_s por tramo, para
	# TODOS los trenes, sin pasar por GestorEventos.
	var aportes_reales: Dictionary = {}  # id_tren -> Array[float], en orden
	estadisticas.retraso_tramo_sumado.connect(func(id_tren: int, aporte_s: float) -> void:
		var lista: Array = aportes_reales.get(id_tren, [])
		lista.append(aporte_s)
		aportes_reales[id_tren] = lista
	)

	# Piquete en Hipólito Yrigoyen (la primera parada real, a la que los 4
	# trenes llegan rápido y de forma confiable). Se evita a propósito la
	# zona Lanús-Escalada-Banfield: con los 4 trenes iniciales convergiendo
	# ahí, el sistema de reservas de switches puede trabarlos sin que
	# ninguno llegue nunca -- es una fragilidad conocida de esa zona
	# (ver docs/integracion_switches_vias.md), no relacionada a este test.
	var r: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 280.0)
	assert(bool(r["ok"]), "Piquete debe aceptarse: %s" % str(r))
	var id_evento_piquete: int = -1
	for e: Dictionary in gestor.obtener_historial():
		if str(e.get("clave", "")) == "Hipólito Yrigoyen":
			id_evento_piquete = int(e["id"])
			break
	assert(id_evento_piquete > 0, "El evento recién disparado debe aparecer en el historial")

	var llegado: Dictionary = {}
	controlador.tren_llego_estacion.connect(func(id_tren: int, datos_est: Dictionary) -> void:
		if str(datos_est.get("nombre", "")) == "Hipólito Yrigoyen" and llegado.is_empty():
			llegado["id"] = id_tren
	)
	if not await _esperar_hasta(func() -> bool: return not llegado.is_empty(), "algún tren llega a Hipólito Yrigoyen"):
		quit(1); return
	var id: int = int(llegado["id"])

	# Esperar a que ESE mismo tren complete su próximo tramo (el que arrancó
	# parado por el piquete) para que EstadisticasRetraso mida el aporte.
	var muestras_antes: int = (aportes_reales.get(id, []) as Array).size()
	if not await _esperar_hasta(func() -> bool: return (aportes_reales.get(id, []) as Array).size() > muestras_antes, "el tren afectado completa el tramo siguiente"):
		quit(1); return

	var lista_aportes: Array = aportes_reales.get(id, [])
	var aporte_real_tramo_piquete: float = float(lista_aportes[lista_aportes.size() - 1])

	var evento_final: Dictionary = {}
	for e: Dictionary in gestor.obtener_historial():
		if int(e.get("id", -1)) == id_evento_piquete:
			evento_final = e
			break
	assert(not evento_final.is_empty(), "El evento debe seguir en el historial")
	var retraso_atribuido: float = float(evento_final.get("retraso_total_s", -1.0))
	var trenes_afectados: Dictionary = evento_final.get("trenes_afectados", {})

	assert(trenes_afectados.has(id), "El tren debe figurar como afectado por el evento")
	assert(absf(retraso_atribuido - aporte_real_tramo_piquete) < 0.01,
		"El retraso atribuido al evento (%.3f) debe coincidir con el que EstadisticasRetraso midió para ese tramo (%.3f)" % [retraso_atribuido, aporte_real_tramo_piquete])
	assert(retraso_atribuido > 0.0, "Un piquete de 280s debe generar retraso medible en el tramo afectado")

	print("OK: retraso atribuido al evento (%.1fs) coincide con el retraso real medido (%.1fs)" % [retraso_atribuido, aporte_real_tramo_piquete])

	nivel.queue_free()
	await process_frame
	print("OK: test_atribucion_eventos completo")
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
