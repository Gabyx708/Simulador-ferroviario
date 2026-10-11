extends SceneTree
## Godot --headless --path . -s res://tools/test_reloj_simulacion.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var escala_original: float = Engine.time_scale
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.1, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var reloj: RelojSimulacion = nivel.get_node("RelojSimulacion")

	# 1) Avanza con el tiempo a factor normal (1.0).
	assert(controlador.establecer_velocidad_simulacion(1.0))
	var t0: float = reloj.tiempo_simulado_s()
	await create_timer(0.3, true, false, true).timeout
	var t1: float = reloj.tiempo_simulado_s()
	assert(t1 > t0, "El reloj debe avanzar a factor 1.0")
	var avance_normal: float = t1 - t0

	# 2) Se congela en pausa (factor 0.0).
	controlador.pausar_simulacion()
	var t2: float = reloj.tiempo_simulado_s()
	await create_timer(0.3, true, false, true).timeout
	var t3: float = reloj.tiempo_simulado_s()
	assert(is_equal_approx(t2, t3) or absf(t3 - t2) < 0.001, "El reloj debe congelarse en pausa (t2=%f t3=%f)" % [t2, t3])

	# 3) Avanza más rápido con un factor alto.
	controlador.establecer_velocidad_simulacion(5.0)
	var t4: float = reloj.tiempo_simulado_s()
	await create_timer(0.3, true, false, true).timeout
	var t5: float = reloj.tiempo_simulado_s()
	var avance_rapido: float = t5 - t4
	assert(avance_rapido > avance_normal * 2.0, "A factor 5.0 el reloj debe avanzar notablemente más rápido que a 1.0 (normal=%f rapido=%f)" % [avance_normal, avance_rapido])

	controlador.establecer_velocidad_simulacion(1.0)
	nivel.queue_free()
	await process_frame
	assert(Engine.time_scale == escala_original)
	print("OK: reloj avanza a factor normal, se congela en pausa y acelera con factor alto")
	quit()
