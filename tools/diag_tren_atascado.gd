extends SceneTree
## Diagnóstico: encontrar la causa raíz de que un tren precargado se quede
## parado "sin destino" poco después de iniciar, SIN eventos disparados.
## Godot --headless --path . -s res://tools/diag_tren_atascado.gd

const DURACION_SIMULADA_OBJETIVO_S: float = 1800.0  ## 30 minutos simulados
const INTERVALO_MUESTRA_S: float = 15.0

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout

	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var reloj: RelojSimulacion = nivel.get_node("RelojSimulacion")
	controlador.establecer_velocidad_simulacion(40.0)

	# Desconectar cualquier disparo aleatorio -- queremos ver el comportamiento
	# SIN eventos, tal como lo reporta el usuario.
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	gestor.aleatorio_activo = false

	var ultima_muestra_s: float = -INTERVALO_MUESTRA_S
	var historial_por_tren: Dictionary = {}  # id -> Array[Dictionary] de muestras

	while reloj.tiempo_simulado_s() < DURACION_SIMULADA_OBJETIVO_S:
		var ahora: float = reloj.tiempo_simulado_s()
		if ahora - ultima_muestra_s >= INTERVALO_MUESTRA_S:
			ultima_muestra_s = ahora
			for tren: Dictionary in controlador.obtener_trenes():
				var id: int = int(tren.get("id", -1))
				var lista: Array = historial_por_tren.get(id, [])
				lista.append({
					"t": ahora, "estado": str(tren.get("estado_nombre", "")),
					"estacion_proxima": str(tren.get("estacion_proxima", "")),
					"distancia_m": float(tren.get("distancia_m", -1.0)),
					"velocidad_kmh": float(tren.get("velocidad_kmh", -1.0)),
					"motivo_evento": str(tren.get("motivo_evento", "")),
					"resultado": str(tren.get("resultado", "")),
					"motivo_resultado": str(tren.get("motivo_resultado", "")),
				})
				historial_por_tren[id] = lista
		await process_frame

	print("=== Historial final por tren (cada %ds simulados) ===" % int(INTERVALO_MUESTRA_S))
	for id: int in historial_por_tren:
		print("--- Tren %d ---" % id)
		var lista: Array = historial_por_tren[id]
		for m: Dictionary in lista:
			print("  t=%6.0fs estado=%-20s prox=%-45s dist=%7.1fm vel=%5.1fkm/h resultado=%-12s motivo='%s'" % [
				m["t"], m["estado"], m["estacion_proxima"], m["distancia_m"], m["velocidad_kmh"], m["resultado"], m["motivo_resultado"],
			])

	# Detección automática: un tren "atascado" es uno cuya estacion_proxima Y
	# distancia_m no cambiaron en NINGUNA muestra durante al menos 5 minutos
	# simulados seguidos, mientras seguía "activo" (no finalizado/incompleto).
	print("\n=== Diagnóstico automático ===")
	var alguno_atascado: bool = false
	for id: int in historial_por_tren:
		var lista: Array = historial_por_tren[id]
		if lista.size() < 2:
			continue
		var inicio_estatico: Dictionary = {}
		for i: int in range(1, lista.size()):
			var anterior: Dictionary = lista[i - 1]
			var actual: Dictionary = lista[i]
			var estatico: bool = anterior["estacion_proxima"] == actual["estacion_proxima"] \
				and absf(float(anterior["distancia_m"]) - float(actual["distancia_m"])) < 0.5 \
				and actual["estado"] not in ["FINALIZADO_EN_BOSQUES", "INCOMPLETO"]
			if estatico:
				if inicio_estatico.is_empty():
					inicio_estatico = anterior
				var duracion: float = float(actual["t"]) - float(inicio_estatico["t"])
				if duracion >= 300.0:
					alguno_atascado = true
					print("ATASCADO: Tren %d sin avanzar desde t=%.0fs hasta al menos t=%.0fs (estado=%s, prox=%s, dist=%.1fm)" % [
						id, float(inicio_estatico["t"]), float(actual["t"]), actual["estado"], actual["estacion_proxima"], float(actual["distancia_m"]),
					])
					break
			else:
				inicio_estatico = {}
	if not alguno_atascado:
		print("Ningún tren quedó atascado >=5 min durante %.0fs simulados a 40x." % DURACION_SIMULADA_OBJETIVO_S)

	nivel.queue_free()
	await process_frame
	quit()
