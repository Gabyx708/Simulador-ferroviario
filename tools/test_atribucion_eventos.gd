extends SceneTree
## Verifica que el retraso_total_s atribuido a un evento por GestorEventos
## coincide con la suma real que EstadisticasRetraso midió para todos los
## trenes que afectó ese evento.
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

	# Verdad de referencia: reproduzco acá, de forma independiente, el mismo
	# mecanismo de atribución que usa GestorEventos internamente (marcar
	# "pendiente" al afectar a un tren, cerrarlo con su próximo aporte medido)
	# en vez de asumir que un único tren concreto es el único afectado -- con
	# varios trenes iniciales convergiendo en la misma zona, más de uno puede
	# quedar atrapado por el mismo piquete antes de que el primero complete
	# su próximo tramo, y la suma real debe incluirlos a todos.
	#
	# `estado` es un Dictionary (no variables sueltas) a propósito: los
	# lambdas de GDScript no comparten por referencia una variable local
	# primitiva (float/int/bool) con la función que los declara -- mutarla
	# adentro del lambda no se propaga afuera. Un Dictionary sí es por
	# referencia. Ver también la nota equivalente en otros tools/diag_*.gd
	# de esta misma sesión.
	var estado: Dictionary = {"pendiente": {}, "confirmados": {}, "aporte_real": 0.0}
	gestor.tren_afectado_por_evento.connect(func(id_tren: int, tipo: int) -> void:
		if tipo == GestorEventos.TipoEvento.PIQUETE:
			(estado["pendiente"] as Dictionary)[id_tren] = true
	)
	estadisticas.retraso_tramo_sumado.connect(func(id_tren: int, aporte_s: float) -> void:
		var pendiente: Dictionary = estado["pendiente"]
		if pendiente.has(id_tren):
			pendiente.erase(id_tren)
			estado["aporte_real"] = float(estado["aporte_real"]) + aporte_s
			(estado["confirmados"] as Dictionary)[id_tren] = true
	)
	# Si un tren marcado queda incompleto en vez de completar su tramo
	# siguiente (puede pasar por causas ajenas al piquete -- ver
	# docs/reporte_final.md), su atribución nunca se va a resolver: sin esto,
	# el test colgaría hasta el tope de frames en vez de fallar claro.
	controlador.tren_finalizo.connect(func(id_tren: int, resultado: String) -> void:
		var pendiente: Dictionary = estado["pendiente"]
		if pendiente.has(id_tren) and resultado != "completo":
			pendiente.erase(id_tren)
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

	if not await _esperar_hasta(func() -> bool: return (estado["confirmados"] as Dictionary).size() > 0, "algún tren afectado completa su tramo siguiente"):
		quit(1); return

	# Esperar a que la zona termine Y no quede ningún tren con atribución
	# pendiente: mientras el piquete sigue activo, puede seguir atrapando
	# trenes nuevos, y cada uno recién aporta su medición real al completar
	# SU propio tramo siguiente (no necesariamente en el mismo frame que los
	# demás).
	if not await _esperar_hasta(func() -> bool:
		if not (estado["pendiente"] as Dictionary).is_empty():
			return false
		for e: Dictionary in gestor.obtener_historial():
			if int(e.get("id", -1)) == id_evento_piquete:
				return not bool(e.get("activo", true))
		return false
	, "la zona del piquete finaliza y se resuelven todas las atribuciones pendientes"):
		quit(1); return

	var evento_final: Dictionary = {}
	for e: Dictionary in gestor.obtener_historial():
		if int(e.get("id", -1)) == id_evento_piquete:
			evento_final = e
			break
	assert(not evento_final.is_empty(), "El evento debe seguir en el historial")
	var retraso_atribuido: float = float(evento_final.get("retraso_total_s", -1.0))
	var aporte_acumulado_real: float = float(estado["aporte_real"])
	var confirmados: Dictionary = estado["confirmados"]

	# No se compara trenes_afectados.size() contra confirmados.size(): un tren
	# marcado afectado que termina incompleto (por una causa ajena al
	# piquete) sigue contando como "afectado" en el evento pero nunca aporta
	# una medición real -- ninguno de los dos lados lo suma, así que no rompe
	# la comparación de abajo, que es la que realmente importa.
	assert(absf(retraso_atribuido - aporte_acumulado_real) < 0.01,
		"El retraso atribuido al evento (%.3f) debe coincidir con la suma real medida para sus %d tren(es) afectados (%.3f)" % [retraso_atribuido, confirmados.size(), aporte_acumulado_real])
	assert(retraso_atribuido > 0.0, "Un piquete de 280s debe generar retraso medible")

	print("OK: retraso atribuido al evento (%.1fs, %d trenes) coincide con la suma real medida (%.1fs)" % [retraso_atribuido, confirmados.size(), aporte_acumulado_real])

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
