extends SceneTree
## Gate del refactor: convergencia del recorte, presupuesto de edición y ruteo sano.
##
## Uso: godot --headless --path . -s res://tools/test_refactor_budget.gd

const ESCENA: String = "res://levels/ramal_roca_main/ramal_roca_main.tscn"
const PRESUPUESTO_EDICION_MS: int = 160
const PRESUPUESTO_BAJA_MS: int = 260

var _fallos: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  OK   %s" % msg)
	else:
		_fallos += 1
		print("  FALLA %s" % msg)


func _run() -> void:
	print("=== GATE DEL REFACTOR (convergencia + presupuesto + ruteo) ===")
	var scn: PackedScene = load(ESCENA)
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(2.0).timeout
	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	var geo: TrackGeometry = net.get_node_or_null("GeometriaVias") as TrackGeometry
	if net == null or geo == null:
		print("FAIL: sin TrackNetwork / GeometriaVias")
		quit(1)
		return

	print("\n[1] Convergencia del recorte")
	var antes: Dictionary = {}
	for id: String in net.paths.keys():
		antes[id] = net.obtener_recorte_tramo(id)
	net._reconstruir_conexiones_adaptativas()
	net._reconstruir_conexiones_adaptativas()
	var cambiados: int = 0
	for id2: String in net.paths.keys():
		if antes.has(id2) and antes[id2] != net.obtener_recorte_tramo(id2):
			cambiados += 1
	_check(cambiados == 0, "dos pasadas extra no cambian ningún recorte (cambiados=%d)" % cambiados)

	print("\n[2] Presupuesto de edición")
	var seg_id: String = str(net.paths.keys()[0])
	var seg: EditableTrackSegment = net.paths[seg_id] as EditableTrackSegment
	seg.offset_inicio = seg.offset_inicio + Vector3(0.4, 0.0, 0.0)
	var t: int = Time.get_ticks_msec()
	net._on_segmento_geometria_modificada(seg_id)
	geo.actualizar_geometria_tramo(seg_id)
	var ms_edicion: int = Time.get_ticks_msec() - t
	_check(ms_edicion <= PRESUPUESTO_EDICION_MS, "edición de curva en %d ms (tope %d)" % [ms_edicion, PRESUPUESTO_EDICION_MS])

	var otro: String = ""
	for k: String in net.paths.keys():
		if k != seg_id:
			otro = k
			break
	t = Time.get_ticks_msec()
	net.eliminar_segmento(otro)
	geo.construir_geometria()
	var ms_baja: int = Time.get_ticks_msec() - t
	_check(ms_baja <= PRESUPUESTO_BAJA_MS, "eliminar tramo en %d ms (tope %d)" % [ms_baja, PRESUPUESTO_BAJA_MS])

	print("\n[3] Ruteo")
	var con_metadata: int = 0
	var cruces: int = 0
	for nid: int in net.aparatos_de_via.keys():
		var sw: BaseTurnout = net.aparatos_de_via[nid] as BaseTurnout
		if sw == null:
			continue
		var j: Dictionary = net.junctions.get(str(nid), {}) as Dictionary
		if (j.get("segments", []) as Array).size() >= 4:
			cruces += 1
			if sw.has_meta("linea_a_segs") and sw.has_meta("linea_b_segs"):
				con_metadata += 1
	_check(cruces == 0 or con_metadata > 0, "cruces con metadata de líneas: %d/%d" % [con_metadata, cruces])

	var inexistentes: int = 0
	var consultas: int = 0
	for id3: String in net.paths.keys():
		for extremo: String in ["start", "end"]:
			var ops: Array = net.get_opciones_siguientes(id3, extremo)
			consultas += 1
			for op: Dictionary in ops:
				if not net.paths.has(str(op.get("segment_id", ""))):
					inexistentes += 1
	_check(inexistentes == 0, "opciones de ruta con segmentos inexistentes: %d (de %d consultas)" % [inexistentes, consultas])

	print("\n=== GATE: %s ===" % ("TODO OK" if _fallos == 0 else "%d FALLOS" % _fallos))
	quit(1 if _fallos > 0 else 0)
