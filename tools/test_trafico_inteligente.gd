extends SceneTree
## Ensayo breve con las cuatro formaciones reales circulando a la vez.

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2, true, false, true).timeout
	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	assert(red != null)
	var trenes: Array[Tren] = []
	for nodo: Node in get_nodes_in_group("trenes"):
		if nodo is Tren:
			trenes.append(nodo as Tren)
	assert(trenes.size() == 4, "El escenario debe tener cuatro trenes")
	var max_odometros: Dictionary = {}
	for tren: Tren in trenes:
		tren.demora_salida_inicial = 0.0
		tren.tiempo_parada_servicio = 0.1
		tren.tiempo_parada = 0.1
		tren.velocidad_max_kmh = 240.0
		tren.aceleracion = 24.0
		tren.desaceleracion = 32.0
		max_odometros[tren.get_instance_id()] = 0.0
	var apartados: Dictionary = {}
	var limite: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < limite:
		await process_frame
		for tren: Tren in trenes:
			if tren._ruta_invalida:
				push_error("Un tren quedó sin ruta: %s, %s, segmento=%s, avance=%.2f, invertido=%s, parada=%d" % [tren.name, tren._motivo_resultado, tren.traza.name if tren.traza != null else "", tren._avance, tren.invertir_sentido, tren._indice_servicio])
				Engine.time_scale = 1.0
				quit(1)
				return
			max_odometros[tren.get_instance_id()] = maxf(float(max_odometros[tren.get_instance_id()]), tren._odometro_ferroviario)
			if tren._apartado_de_via:
				apartados[tren.get_instance_id()] = true
			if not tren._en_maniobra_terminal and not tren._detenido and not tren._apartado_de_via and tren.traza != null:
				if not red.segmento_permite_sentido(tren.traza.name, tren.es_sentido_ida()):
					push_error("Tren en vía prohibida: %s %s" % [tren.name, tren.traza.name])
					Engine.time_scale = 1.0
					quit(1)
					return
		for i: int in trenes.size():
			for j: int in range(i + 1, trenes.size()):
				var a: Tren = trenes[i]
				var b: Tren = trenes[j]
				if a.traza == b.traza and not a._apartado_de_via and not b._apartado_de_via:
					if absf(a._avance - b._avance) < 10.0:
						push_error("Dos cabeceras se superpusieron en %s" % a.traza.name)
						Engine.time_scale = 1.0
						quit(1)
						return
	Engine.time_scale = 1.0
	print("OK tráfico: odómetros=%s trenes apartados=%d" % [str(max_odometros.values()), apartados.size()])
	quit(0)
