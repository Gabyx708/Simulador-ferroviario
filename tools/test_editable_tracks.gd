extends SceneTree

const EditableTrackSegment = preload("res://scenes/tracks/editable_track_segment.gd")

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=== INICIANDO TEST DE VÍAS EDITABLES Y PERSISTENCIA ===")
	var scn: PackedScene = load("res://levels/ramal_roca_main/ramal_roca_main.tscn")
	if scn == null:
		print("FAIL: No se pudo cargar ramal_roca_main.tscn")
		quit(1)
		return

	var root_node: Node = scn.instantiate()
	root.add_child(root_node)

	# Esperar inicialización
	await create_timer(1.0).timeout

	var net: TrackNetwork = root_node.find_child("TrackNetwork", true, false) as TrackNetwork
	if net == null:
		print("FAIL: TrackNetwork no encontrado")
		quit(1)
		return

	# El test escribe en un journal temporal para no tocar el archivo real de
	# ediciones del proyecto (antes lo borraba al finalizar).
	const RUTA_EDITS_TEST: String = "res://tools/_test_edits_temporal.json"
	if FileAccess.file_exists(RUTA_EDITS_TEST):
		DirAccess.remove_absolute(RUTA_EDITS_TEST)
	net.ruta_archivo_ediciones = RUTA_EDITS_TEST

	var geo: TrackGeometry = net.find_child("GeometriaVias", true, false) as TrackGeometry
	if geo == null:
		print("FAIL: GeometriaVias no encontrado")
		quit(1)
		return

	print("1. Comprobando instanciación de tramos...")
	print("   Total tramos en red: %d" % net.paths.size())
	if net.paths.is_empty():
		print("FAIL: net.paths está vacío")
		quit(1)
		return

	var primer_id: String = net.paths.keys()[0]
	var seg_node: Node = net.paths[primer_id]
	if not (seg_node is EditableTrackSegment):
		print("FAIL: seg_node no es EditableTrackSegment")
		quit(1)
		return

	var track: EditableTrackSegment = seg_node as EditableTrackSegment
	print("   Tramo de prueba: '%s' (Clase: %s, Largo: %.2fm)" % [track.name, track.get_class(), track.longitud_metros])
	print("   Curva original presente: %s (Puntos: %d)" % [track.curva_original != null, track.curva_original.point_count if track.curva_original != null else 0])
	print("   Estado inicial: %s (Modificada: %s)" % [track.estado_edicion, track.esta_modificada])

	assert(track.curva_original != null, "La curva original debe estar guardada")
	assert(track.esta_modificada == false, "El tramo inicial no debe estar modificado")

	var largo_orig: float = track.longitud_metros
	var pos0_orig: Vector3 = track.curva_original.get_point_position(0)

	print("\n2. Probando modificación interactiva (offset_inicio)...")
	track.offset_inicio = Vector3(2.5, 0.5, -1.0)
	assert(track.esta_modificada == true, "Debe marcarse como modificada al cambiar offset")
	assert(track.estado_edicion == "Modificado", "El estado debe ser 'Modificado'")
	var pos0_nueva: Vector3 = track.curve.get_point_position(0)
	print("   Posición original p0: %s" % str(pos0_orig))
	print("   Nueva posición p0:     %s" % str(pos0_nueva))
	assert(pos0_nueva.distance_to(pos0_orig + Vector3(2.5, 0.5, -1.0)) < 1e-4, "La nueva posición debe incluir el offset")

	print("\n3. Probando guardado persistente...")
	track.guardar_edicion()
	assert(track.estado_edicion == "Modificado (Guardado)", "Estado debe ser Guardado")
	var ruta_edits: String = net.obtener_ruta_ediciones_json()
	print("   Archivo ediciones: %s" % ruta_edits)
	assert(FileAccess.file_exists(ruta_edits), "El archivo de ediciones debe existir en disco")

	var edits_leidas: Dictionary = net.cargar_ediciones_guardadas()
	assert(edits_leidas.has(track.segment_id), "El segmento debe figurar en el archivo de ediciones")
	print("   Verificada persistencia en JSON para '%s'." % track.segment_id)

	print("\n4. Probando recarga de red con ediciones existentes...")
	net.cargar_red()
	var track_recargado: EditableTrackSegment = net.paths[primer_id] as EditableTrackSegment
	assert(track_recargado.esta_modificada == true, "Tras recargar debe conservar la edición guardada")
	assert(track_recargado.offset_inicio.distance_to(Vector3(2.5, 0.5, -1.0)) < 1e-4, "Offset debe conservarse tras recargar")
	print("   Recarga exitosa: edición conservada.")

	print("\n5. Probando reseteo a forma original base...")
	track_recargado.resetear_a_original()
	assert(track_recargado.esta_modificada == false, "Tras resetear no debe estar modificada")
	assert(track_recargado.estado_edicion == "Original", "Estado debe volver a Original")
	var pos0_reseteada: Vector3 = track_recargado.curve.get_point_position(0)
	assert(pos0_reseteada.distance_to(pos0_orig) < 1e-4, "La posición p0 debe haber vuelto a la original")
	print("   Posición reseteada p0: %s (coincide con original)" % str(pos0_reseteada))

	var edits_post_reset: Dictionary = net.cargar_ediciones_guardadas()
	assert(not edits_post_reset.has(track_recargado.segment_id), "El segmento no debe estar en ediciones tras resetear")
	print("   Eliminado correctamente del archivo de ediciones.")

	print("\n6. Probando botón encajar_con_vecino...")
	# Buscar un tramo que conecte a un switch
	var tramo_con_switch: EditableTrackSegment = null
	for s_id in net.paths.keys():
		var s_data: Dictionary = net.segments_data.get(s_id, {}) as Dictionary
		var n_start: int = int(s_data.get("node_start", 0))
		var n_end: int = int(s_data.get("node_end", 0))
		if net.aparatos_de_via.has(n_start) or net.aparatos_de_via.has(n_end):
			tramo_con_switch = net.paths[s_id] as EditableTrackSegment
			break

	if tramo_con_switch != null:
		print("   Tramo conectado a switch encontrado: %s" % tramo_con_switch.name)
		tramo_con_switch.encajar_con_vecino("start")
		print("   Encajado 'start' ejecutado exitosamente.")
		tramo_con_switch.resetear_a_original()

	# Limpiar archivo de prueba de ediciones si quedó
	if FileAccess.file_exists(ruta_edits):
		DirAccess.remove_absolute(ruta_edits)

	print("\n=== TODOS LOS TESTS PASARON EXITOSAMENTE (OK) ===")
	quit(0)
