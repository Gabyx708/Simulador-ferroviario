extends SceneTree
## Diagnóstico puntual de puertos de aparatos de vía.
## Imprime el estado del tramo flexible de cada puerto del switch indicado.
##
## Uso: godot --headless --path . -s res://tools/diag_puertos_switch.gd

const NOMBRE_FILTRO_DEFECTO: String = "Desvio_A_1526687713"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nombre_filtro: String = NOMBRE_FILTRO_DEFECTO
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		nombre_filtro = args[0]

	var scn: PackedScene = load("res://levels/ramal_roca_main/ramal_roca_main.tscn")
	var root_node: Node = scn.instantiate()
	root.add_child(root_node)
	await create_timer(1.5).timeout

	var net: TrackNetwork = root_node.find_child("TrackNetwork", true, false) as TrackNetwork
	if net == null:
		print("FAIL: sin TrackNetwork")
		quit(1)
		return

	for nid: int in net.aparatos_de_via.keys():
		var sw: BaseTurnout = net.aparatos_de_via[nid] as BaseTurnout
		if sw == null or String(sw.name) != nombre_filtro:
			continue
		print("\n=== SWITCH %s (node_id %d, tipo %s) ===" % [sw.name, nid, sw.get_tipo_aparato()])
		print("  origen: %s" % str(sw.global_transform.origin))
		print("  z_local: %s" % str((sw.global_transform.basis * Vector3.FORWARD).normalized()))
		print("  via_comun=%s directa=%s desviada=%s" % [sw.via_comun_id, sw.via_directa_id, sw.via_desviada_id])
		var jd: Dictionary = net.junctions.get(str(nid), {}) as Dictionary
		for c_raw: Variant in (jd.get("segments", []) as Array):
			var c: Dictionary = c_raw as Dictionary
			print("  junction-> seg %s (end %s) existe=%s" % [c.get("segment_id", ""), c.get("end", ""), net.paths.has(str(c.get("segment_id", "")))])
		var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
		if g_ext != null:
			for h: Node in g_ext.get_children():
				if not (h is FlexibleTrackLead):
					continue
				var lead: FlexibleTrackLead = h as FlexibleTrackLead
				var largo_curva: float = lead.curve.get_baked_length() if lead.curve != null else -1.0
				print("  [%s] punto_inicio=%s dir_inicio=%s manual=%s manual_fin=%s ext_long=%s | curva=%.2fm (%d pts)" % [
					lead.name, str(lead.punto_inicio), str(lead.direccion_inicio),
					str(lead.usar_extremo_manual), str(lead.punto_fin_manual),
					str(lead.longitud_extension), largo_curva,
					lead.curve.point_count if lead.curve != null else 0
				])
				if lead.curve != null and lead.curve.point_count >= 2:
					var i_fin: int = lead.curve.point_count - 1
					var p_fin_w: Vector3 = lead.global_transform * lead.curve.get_point_position(i_fin)
					print("        extremo exterior mundo=%s" % str(p_fin_w))
		quit(0)
		return

	print("No se encontró el switch '%s'." % nombre_filtro)
	quit(1)
