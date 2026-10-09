extends SceneTree
## Perfilado del costo de UNA edición manual (mover/eliminar un Path3D).
##
## Uso: godot --headless --path . -s res://tools/profile_edicion.gd

const ESCENA: String = "res://levels/ramal_roca_switches/ramal_roca_switches.tscn"


func _init() -> void:
	call_deferred("_run")


func _ms(desde: int) -> String:
	return "%.0f ms" % float(Time.get_ticks_msec() - desde)


func _run() -> void:
	var scn: PackedScene = load(ESCENA)
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(1.5).timeout

	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	var geo: TrackGeometry = net.get_node_or_null("GeometriaVias") as TrackGeometry
	if net == null or geo == null:
		print("FAIL: sin TrackNetwork / GeometriaVias")
		quit(1)
		return
	net.debug_tiempos = true

	print("\n=== PERFIL DE EDICIÓN (tramos: %d | aparatos: %d) ===" % [net.paths.size(), net.aparatos_de_via.size()])

	# Calentamiento (una vez, como al abrir la escena).
	var t: int = Time.get_ticks_msec()
	net._reconstruir_conexiones_adaptativas()
	geo.construir_geometria()
	print("0. Calentamiento (1ª pasada, como al abrir)         : %s" % _ms(t))

	# 3 ediciones seguidas del MISMO tramo, como al arrastrar un punto en el editor.
	var seg_id: String = str(net.paths.keys()[0])
	var seg: EditableTrackSegment = net.paths[seg_id] as EditableTrackSegment
	for n: int in 3:
		seg.offset_inicio = seg.offset_inicio + Vector3(0.5, 0.0, 0.0)
		t = Time.get_ticks_msec()
		net._on_segmento_geometria_modificada(seg_id)
		geo.actualizar_geometria_tramo(seg_id)
		print("1.%d Costo de 1 edición de curva (debounce)         : %s" % [n + 1, _ms(t)])

	# Edición en otro tramo (peor caso: 2 aparatos distintos).
	var otro: String = ""
	for k: String in net.paths.keys():
		if k != seg_id:
			otro = k
			break
	var seg2: EditableTrackSegment = net.paths[otro] as EditableTrackSegment
	t = Time.get_ticks_msec()
	seg2.offset_fin = seg2.offset_fin + Vector3(0.5, 0.0, 0.0)
	net._on_segmento_geometria_modificada(otro)
	geo.actualizar_geometria_tramo(otro)
	print("2. Edición de otro tramo                            : %s" % _ms(t))

	# Eliminar un tramo (lo que congelaba el editor).
	t = Time.get_ticks_msec()
	net.eliminar_segmento(otro)
	geo.construir_geometria()
	print("3. Eliminar 1 tramo + re-mallado incremental        : %s" % _ms(t))

	# Mover un switch (reintegrar todo) — peor caso del sistema.
	var nid: int = 0
	for k2: int in net.aparatos_de_via.keys():
		nid = k2
		break
	var sw: BaseTurnout = net.aparatos_de_via[nid] as BaseTurnout
	sw.global_transform.origin = sw.global_transform.origin + Vector3(8.0, 0.0, 4.0)
	t = Time.get_ticks_msec()
	net.reintegrar_switches_editados()
	geo.construir_geometria()
	print("4. Mover 1 switch + reintegrar + geometría          : %s" % _ms(t))

	print("=== FIN PERFIL ===\n")
	quit(0)
