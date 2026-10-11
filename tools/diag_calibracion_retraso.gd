extends SceneTree
## Herramienta de calibración, no un test de aceptación -- usarla de nuevo si
## cambia velocidad_nominal_kmh, la geometría de los tramos, o para recalcular
## factor_calibracion_tiempo en EstadisticasRetraso tras cualquier cambio así.
## Godot --headless --path . -s res://tools/diag_calibracion_retraso.gd
## Mide llegada->llegada (no salida->llegada): así una demora de ANDÉN
## (el tren ya parado cuando lo frena un evento) también queda capturada,
## no sólo la demora de viaje.
## Usa un Dictionary para el estado compartido con los lambdas: en GDScript
## una variable local float/int capturada por una lambda NO se comparte por
## referencia con el resto de la función (cada lambda ve su propia copia).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var reloj: RelojSimulacion = nivel.get_node("RelojSimulacion")
	controlador.establecer_velocidad_simulacion(40.0)

	var tren: Tren = nivel.find_child("TrenCSR", true, false) as Tren
	var estado: Dictionary = {"pico": 0.0, "t_ultima_llegada": -1.0}
	var legs: Array = []

	tren.llego_a_estacion.connect(func(_dt: Dictionary, datos_est: Dictionary) -> void:
		var t_ahora: float = reloj.tiempo_simulado_s()
		if float(estado["t_ultima_llegada"]) >= 0.0 and float(estado["pico"]) > 0.0:
			var t_real: float = t_ahora - float(estado["t_ultima_llegada"])
			var t_esp: float = float(estado["pico"]) / (50.0 / 3.6)
			legs.append({"estacion": str(datos_est.get("nombre","?")), "pico_dist": estado["pico"], "t_real": t_real, "t_esp": t_esp, "ratio": t_real / t_esp})
		estado["t_ultima_llegada"] = t_ahora
		estado["pico"] = 0.0
	)

	for i in range(2400):
		await process_frame
		if tren != null and is_instance_valid(tren):
			var d: float = tren.distancia_a_proxima_estacion()
			if d > float(estado["pico"]):
				estado["pico"] = d
		if i % 400 == 0:
			print("progreso frame=%d legs=%d pico_actual=%.1f" % [i, legs.size(), float(estado["pico"])])
		if legs.size() >= 6:
			break

	print("--- %d tramos (llegada->llegada) ---" % legs.size())
	var suma: float = 0.0
	for leg: Dictionary in legs:
		print("%-24s pico_dist=%8.1fm  real=%7.1fs  esperado50=%7.1fs  ratio=%.3f" % [leg["estacion"], leg["pico_dist"], leg["t_real"], leg["t_esp"], leg["ratio"]])
		suma += float(leg["ratio"])
	if legs.size() > 0:
		print("ratio promedio sugerido (factor_calibracion_tiempo) = %.3f" % (suma / legs.size()))

	nivel.queue_free()
	await process_frame
	quit()
