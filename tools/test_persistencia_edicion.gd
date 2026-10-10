extends SceneTree
## Test de persistencia de la edición manual de la red ferroviaria.
##
## Cubre los tres escenarios pedidos y la regresión que borraba la red entera:
##   1. Eliminar un Path3D  -> la baja queda en el journal y no se regenera.
##   2. Mover un switch     -> la nueva pose queda en el journal y se re-ancla.
##   3. Eliminar un switch  -> la baja queda en el journal y no se regenera.
##   4. Descargar la escena -> NO se marca ningún tramo como eliminado.
##
## Uso: godot --headless --path . -s res://tools/test_persistencia_edicion.gd

const RUTA_EDITS_TEST: String = "res://tools/_test_persistencia_temporal.json"
const ESCENA: String = "res://levels/ramal_roca_main/ramal_roca_main.tscn"

var _fallos: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("  OK   %s" % mensaje)
	else:
		_fallos += 1
		print("  FALLA %s" % mensaje)


func _leer_journal() -> Dictionary:
	if not FileAccess.file_exists(RUTA_EDITS_TEST):
		return {}
	var f: FileAccess = FileAccess.open(RUTA_EDITS_TEST, FileAccess.READ)
	if f == null:
		return {}
	var texto: String = f.get_as_text()
	f.close()
	var j: JSON = JSON.new()
	if j.parse(texto) != OK or not (j.data is Dictionary):
		return {}
	return (j.data as Dictionary).get("segments", {}) as Dictionary


func _run() -> void:
	print("=== TEST DE PERSISTENCIA DE EDICIÓN MANUAL ===")
	if FileAccess.file_exists(RUTA_EDITS_TEST):
		DirAccess.remove_absolute(RUTA_EDITS_TEST)

	var scn: PackedScene = load(ESCENA)
	if scn == null:
		print("FAIL: no se pudo cargar la escena")
		quit(1)
		return
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(1.2).timeout

	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	if net == null:
		print("FAIL: sin TrackNetwork")
		quit(1)
		return

	print("\n[0] Cambiar la ruta del journal NO debe regenerar la red")
	var sid_ref: String = str(net.paths.keys()[0])
	var nodo_ref: Path3D = net.paths[sid_ref] as Path3D
	var id_inst_antes: int = nodo_ref.get_instance_id()
	var cant_antes: int = net.paths.size()
	net.ruta_archivo_ediciones = RUTA_EDITS_TEST
	await create_timer(0.2).timeout
	_check(net.paths.size() == cant_antes, "la cantidad de tramos no cambió (%d)" % net.paths.size())
	if net.paths.has(sid_ref):
		var nodo_desp: Path3D = net.paths[sid_ref] as Path3D
		_check(nodo_desp.get_instance_id() == id_inst_antes,
			"el nodo '%s' sigue siendo el de la escena (no se regeneró desde el JSON)" % sid_ref)
	else:
		_check(false, "'%s' desapareció al cambiar la ruta del journal" % sid_ref)

	net.cargar_red()
	await create_timer(0.4).timeout

	print("\n[1] Estado inicial")
	_check(net.paths.size() > 500, "la red se carga con %d tramos" % net.paths.size())
	_check(net.aparatos_de_via.size() > 100, "se instancian %d aparatos de vía" % net.aparatos_de_via.size())
	var journal: Dictionary = _leer_journal()
	var eliminados_iniciales: Array = journal.get("_eliminados", []) as Array

	print("\n[2] Eliminar un Path3D (baja manual persistente)")
	var ids: Array = net.paths.keys()
	var seg_borrado: String = str(ids[ids.size() - 1])
	net.eliminar_segmento(seg_borrado)
	await create_timer(0.3).timeout
	var j2: Dictionary = _leer_journal()
	_check((j2.get("_eliminados", []) as Array).has(seg_borrado), "la baja de '%s' quedó en el journal" % seg_borrado)
	_check(not net.paths.has(seg_borrado), "el tramo ya no está en net.paths")

	print("\n[3] Eliminar un Path3D removiéndolo del árbol (como en el editor)")
	var seg_arbol: String = ""
	for s_id: String in net.paths.keys():
		if s_id != seg_borrado:
			seg_arbol = s_id
			break
	var nodo: Path3D = net.paths[seg_arbol] as Path3D
	nodo.get_parent().remove_child(nodo)
	nodo.queue_free()
	await create_timer(0.7).timeout
	var j3: Dictionary = _leer_journal()
	_check((j3.get("_eliminados", []) as Array).has(seg_arbol), "la baja de '%s' (vía árbol) quedó registrada" % seg_arbol)

	print("\n[4] Mover un switch (persistencia de pose + re-anclaje)")
	var nid_sw: int = 0
	for k: int in net.aparatos_de_via.keys():
		nid_sw = k
		break
	var sw: BaseTurnout = net.aparatos_de_via[nid_sw] as BaseTurnout
	var origen_previo: Vector3 = sw.global_transform.origin
	sw.global_transform.origin = origen_previo + Vector3(12.0, 0.0, 7.0)
	net.reintegrar_switches_editados()
	await create_timer(0.3).timeout
	var j4: Dictionary = _leer_journal()
	var sw_dict: Dictionary = j4.get("_switches", {}) as Dictionary
	_check(sw_dict.has(str(nid_sw)), "el switch %d figura en el journal" % nid_sw)
	if sw_dict.has(str(nid_sw)):
		var tr: Array = (sw_dict[str(nid_sw)] as Dictionary).get("transform", []) as Array
		var nueva_pos: Vector3 = Vector3(float(tr[9]), float(tr[10]), float(tr[11])) if tr.size() >= 12 else Vector3.ZERO
		_check(nueva_pos.distance_to(sw.global_transform.origin) < 0.01, "la pose guardada coincide con la nueva (%s)" % str(nueva_pos))

	print("\n[5] Eliminar un switch (baja persistente)")
	net.eliminar_switch(nid_sw)
	await create_timer(0.3).timeout
	var j5: Dictionary = _leer_journal()
	_check((j5.get("_switches_eliminados", []) as Array).has(str(nid_sw)), "la baja del switch %d quedó registrada" % nid_sw)
	_check(not net.aparatos_de_via.has(nid_sw), "el switch ya no está en aparatos_de_via")

	print("\n[5b] Edición manual de un extremo de switch (persistencia)")
	var nid_ext: int = 0
	var lead_ext: FlexibleTrackLead = null
	for k2: int in net.aparatos_de_via.keys():
		var sw2: BaseTurnout = net.aparatos_de_via[k2] as BaseTurnout
		if sw2 == null:
			continue
		var ge: Node = sw2.get_node_or_null("ExtremosFlexibles")
		if ge == null:
			continue
		for h2: Node in ge.get_children():
			if h2 is FlexibleTrackLead:
				lead_ext = h2 as FlexibleTrackLead
				nid_ext = k2
				break
		if lead_ext != null:
			break
	_check(lead_ext != null, "se encontró un extremo flexible para editar")
	if lead_ext != null:
		lead_ext.boton_fijar_extremo = true
		lead_ext.punto_fin_manual = lead_ext.punto_fin_manual + Vector3(1.5, 0.0, 0.0)
		lead_ext.reconstruir_tramo()
		var nombre_lead: String = String(lead_ext.name)
		var pose_guardada: Vector3 = lead_ext.punto_fin_manual
		net.guardar_todas_las_ediciones()
		await create_timer(0.3).timeout
		var j5b: Dictionary = _leer_journal()
		var swd: Dictionary = (j5b.get("_switches", {}) as Dictionary).get(str(nid_ext), {}) as Dictionary
		var exts: Dictionary = swd.get("extremos", {}) as Dictionary
		_check(exts.has(nombre_lead), "el extremo '%s' quedó en el journal" % nombre_lead)

		net.cargar_red()
		await create_timer(0.8).timeout
		var sw_rec: BaseTurnout = net.aparatos_de_via.get(nid_ext) as BaseTurnout
		_check(sw_rec != null, "el switch %d se regeneró" % nid_ext)
		var lead_rec: FlexibleTrackLead = null
		if sw_rec != null:
			var ge2: Node = sw_rec.get_node_or_null("ExtremosFlexibles")
			if ge2 != null:
				lead_rec = ge2.get_node_or_null(nombre_lead) as FlexibleTrackLead
		_check(lead_rec != null, "el extremo '%s' existe tras regenerar" % nombre_lead)
		if lead_rec != null:
			_check(lead_rec.respetar_edicion_manual, "el extremo quedó bloqueado (edición manual respetada)")
			_check(lead_rec.punto_fin_manual.distance_to(pose_guardada) < 0.01,
				"la pose manual se conservó (%s)" % str(lead_rec.punto_fin_manual))

	print("\n[6] Regenerar la red desde el JSON base respeta las bajas")
	net.cargar_red()
	await create_timer(0.6).timeout
	_check(not net.paths.has(seg_borrado), "'%s' no se regeneró" % seg_borrado)
	_check(not net.paths.has(seg_arbol), "'%s' no se regeneró" % seg_arbol)
	_check(not net.aparatos_de_via.has(nid_sw), "el switch %d no se regeneró" % nid_sw)

	print("\n[6b] Restaurar los tramos dados de baja")
	var restaurados: int = net.restaurar_tramos_eliminados()
	await create_timer(0.6).timeout
	_check(restaurados >= 2, "se restauraron %d tramos" % restaurados)
	_check(net.paths.has(seg_borrado), "'%s' volvió a la red" % seg_borrado)
	_check(net.paths.has(seg_arbol), "'%s' volvió a la red" % seg_arbol)
	var j6: Dictionary = _leer_journal()
	_check(not (j6.get("_eliminados", []) as Array).has(seg_borrado), "el journal ya no lista '%s'" % seg_borrado)

	print("\n[7] REGRESIÓN: descargar la escena NO debe marcar bajas")
	var j_antes: Dictionary = _leer_journal()
	var elim_antes: int = (j_antes.get("_eliminados", []) as Array).size()
	root.remove_child(raiz)
	raiz.free()
	await create_timer(0.4).timeout
	var j_despues: Dictionary = _leer_journal()
	var elim_despues: int = (j_despues.get("_eliminados", []) as Array).size()
	_check(elim_despues == elim_antes,
		"el desmontaje no agregó bajas (%d -> %d; antes el bug agregaba 569)" % [elim_antes, elim_despues])

	if FileAccess.file_exists(RUTA_EDITS_TEST):
		DirAccess.remove_absolute(RUTA_EDITS_TEST)

	if _fallos == 0:
		print("\n=== PERSISTENCIA: TODOS LOS CHECKS OK ===")
		quit(0)
	else:
		print("\n=== PERSISTENCIA: %d FALLOS ===" % _fallos)
		quit(1)
