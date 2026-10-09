extends SceneTree
## Diagnóstico de la clasificación de aparatos: por qué un centro de tijera (Tipo E)
## no se detecta y termina armado con otros tipos (A/B/C/D superpuestos).
##
## Uso: godot --headless --path . -s res://tools/diag_tipos_aparatos.gd

const ESCENA: String = "res://levels/ramal_roca_switches/ramal_roca_switches.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scn: PackedScene = load(ESCENA)
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(1.5).timeout
	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	net.debug_tiempos = false

	print("\n=== CLASIFICACIÓN DE APARATOS EN LA ESCENA ===")
	var por_tipo: Dictionary = {}
	for nid: int in net.aparatos_de_via.keys():
		var sw: BaseTurnout = net.aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var t: String = sw.get_tipo_aparato()
		por_tipo[t] = int(por_tipo.get(t, 0)) + 1
	for t: String in por_tipo.keys():
		print("  %s: %d" % [t, por_tipo[t]])

	print("\n=== UNIONES CON >= 4 RAMAS (candidatas a TIPO C / TIPO E) ===")
	var con_4: int = 0
	var candidatas_e: int = 0
	for j_key: Variant in net.junctions.keys():
		var j_id: int = int(j_key)
		var j_dict: Dictionary = net.junctions[j_key] as Dictionary
		var conns: Array = j_dict.get("segments", []) as Array
		if conns.size() < 4:
			continue
		con_4 += 1
		var corners: Array[int] = []
		var detalle: Array[String] = []
		for c_raw: Variant in conns:
			var c: Dictionary = c_raw as Dictionary
			var sid: String = str(c.get("segment_id", ""))
			var seg: Dictionary = net.segments_data.get(sid, {}) as Dictionary
			var n_s: int = int(seg.get("node_start", 0))
			var n_e: int = int(seg.get("node_end", 0))
			var other: int = n_e if n_s == j_id else n_s
			var desviado: String = net._detectar_segmento_desviado_union(other)
			var ok: bool = desviado == sid
			if ok:
				corners.append(other)
			var j_oth: Dictionary = net.junctions.get(str(other), {}) as Dictionary
			detalle.append("%s->nodo %d (ramas %d) desviado=%s %s" % [
				sid, other, (j_oth.get("segments", []) as Array).size(), desviado, "OK" if ok else ""
			])
		var tipo_real: String = "?"
		var sw_x: BaseTurnout = net.aparatos_de_via.get(j_id) as BaseTurnout
		if sw_x != null:
			tipo_real = sw_x.get_tipo_aparato()
		if corners.size() == 4:
			candidatas_e += 1
		print("\nUnión %d | ramas %d | esquinas válidas %d | tipo generado: %s" % [
			j_id, conns.size(), corners.size(), tipo_real
		])
		for d: String in detalle:
			print("    %s" % d)

	print("\nUniones con >=4 ramas: %d | de las cuales cumplen el test de tijera: %d" % [con_4, candidatas_e])

	print("\n=== REGENERANDO APARATOS CON EL DETECTOR ACTUAL ===")
	net.generar_switches_desde_paths_existentes()
	await create_timer(0.5).timeout
	var por_tipo2: Dictionary = {}
	for nid2: int in net.aparatos_de_via.keys():
		var sw2: BaseTurnout = net.aparatos_de_via[nid2] as BaseTurnout
		if sw2 == null:
			continue
		var t2: String = sw2.get_tipo_aparato()
		por_tipo2[t2] = int(por_tipo2.get(t2, 0)) + 1
	print("Tipos luego de regenerar:")
	for t: String in por_tipo2.keys():
		print("  %s: %d" % [t, por_tipo2[t]])
	print("Aparatos TIPO_E (centro de tijera) detectados:")
	var vistos: Dictionary = {}
	for nid3: int in net.aparatos_de_via.keys():
		var sw3: BaseTurnout = net.aparatos_de_via[nid3] as BaseTurnout
		if sw3 == null:
			continue
		var iid: int = sw3.get_instance_id()
		if vistos.has(iid):
			continue
		vistos[iid] = true
		if sw3.get_tipo_aparato() == "TIPO_E":
			print("  %s | nodo %d | pos %s" % [sw3.name, nid3, str(sw3.global_transform.origin)])
	print("Instancias únicas por tipo (luego de regenerar):")
	var unicos: Dictionary = {}
	for nid4: int in net.aparatos_de_via.keys():
		var sw4: BaseTurnout = net.aparatos_de_via[nid4] as BaseTurnout
		if sw4 == null:
			continue
		unicos[sw4.get_instance_id()] = sw4.get_tipo_aparato()
	var conteo_u: Dictionary = {}
	for k5: int in unicos.keys():
		var t5: String = str(unicos[k5])
		conteo_u[t5] = int(conteo_u.get(t5, 0)) + 1
	for t6: String in conteo_u.keys():
		print("  %s: %d instancias" % [t6, conteo_u[t6]])
	print("=== FIN ===\n")
	quit(0)
