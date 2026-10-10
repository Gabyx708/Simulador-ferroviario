extends SceneTree

func _init() -> void:
	call_deferred("_run_audit")

func _run_audit() -> void:
	print("--- INICIANDO AUDITORIA DETALLADA DE SWITCHES Y RAMAL ROCA ---")
	var scn: PackedScene = load("res://levels/ramal_roca_main/ramal_roca_main.tscn")
	if scn == null:
		print("ERROR: No se pudo cargar ramal_roca_main.tscn")
		quit(1)
		return

	var root_node: Node = scn.instantiate()
	root.add_child(root_node)

	# Esperar a que la escena se inicialice y cargue la red
	await create_timer(1.0).timeout

	var net: TrackNetwork = root_node.find_child("TrackNetwork", true, false) as TrackNetwork
	if net == null:
		print("ERROR: TrackNetwork no encontrado")
		quit(1)
		return

	var switches_node: Node = net.find_child("Switches", true, false)
	if switches_node == null:
		print("ERROR: Nodo Switches no encontrado")
		quit(1)
		return

	var switches_list: Array[Node] = []
	_recolectar_switches(switches_node, switches_list)

	print("Total switches instanciados en árbol: %d" % switches_list.size())
	var conteo_por_tipo: Dictionary = {}
	var leads_auditados: int = 0
	var leads_con_angulo_duro: int = 0
	var leads_manuales_conectados: int = 0

	for sw in switches_list:
		var tipo: String = "DESCONOCIDO"
		if sw is ProceduralScissorsCrossover:
			tipo = "TIPO_E"
		elif sw is ProceduralCrossover:
			tipo = "TIPO_D"
		elif sw is ProceduralCrossing:
			tipo = "TIPO_C"
		elif sw is ProceduralSymmetricalTurnout:
			tipo = "TIPO_B"
		elif sw is ProceduralTurnout:
			tipo = "TIPO_A"

		conteo_por_tipo[tipo] = conteo_por_tipo.get(tipo, 0) + 1

		# Auditar extremos flexibles
		var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
		if g_ext != null:
			for lead_child in g_ext.get_children():
				if lead_child is FlexibleTrackLead:
					var lead: FlexibleTrackLead = lead_child as FlexibleTrackLead
					leads_auditados += 1
					var p0: Vector3 = lead.punto_inicio
					var d0: Vector3 = lead.direccion_inicio
					var p1: Vector3 = lead.obtener_posicion_extremo_exterior()
					var d1: Vector3 = lead.obtener_direccion_extremo_exterior()

					if lead.usar_extremo_manual:
						leads_manuales_conectados += 1

					var dist: float = p0.distance_to(p1)
					if dist < 0.2 or lead.curve == null or lead.curve.point_count < 2:
						continue

					# Verificar ángulo de deflexión entre d0 y (p1 - p0)
					var cord: Vector3 = (p1 - p0).normalized()
					var dot_in: float = d0.dot(cord)
					var dot_out: float = d1.dot(cord)

					# Si el ángulo es mayor a 60 grados (dot < 0.5), advertir posible quiebre
					if dot_in < 0.3 or dot_out < 0.3:
						leads_con_angulo_duro += 1
						if leads_con_angulo_duro <= 5:
							print("  [AVISO] Angulo agudo en lead: %s / %s (dot_in: %.2f, dot_out: %.2f, dist: %.2fm)" % [sw.name, lead.name, dot_in, dot_out, dist])

	print("\n--- DISTRIBUCIÓN DE APARATOS ---")
	for k in conteo_por_tipo.keys():
		print("  - %s: %d" % [k, conteo_por_tipo[k]])

	print("\n--- AUDITORÍA DE EXTREMOS FLEXIBLES ---")
	print("  - Total leads auditados: %d" % leads_auditados)
	print("  - Leads conectados a vía exterior: %d" % leads_manuales_conectados)
	print("  - Leads con ángulo forzado (>60 deg): %d" % leads_con_angulo_duro)

	# Auditar recortes en segmentos
	var recortes: Dictionary = net._recortes_segmentos
	var tramos_absorbidos: int = 0
	var tramos_recortados: int = 0
	for sid in recortes.keys():
		var r: Vector2 = recortes[sid] as Vector2
		if r == Vector2.ZERO or (r.y - r.x < 1.5):
			tramos_absorbidos += 1
		else:
			tramos_recortados += 1

	print("\n--- AUDITORÍA DE TRAMOS DE VÍA ---")
	print("  - Total tramos en red: %d" % net.paths.size())
	print("  - Tramos absorbidos (100%% eliminados): %d" % tramos_absorbidos)
	print("  - Tramos recortados con gap para switches: %d" % tramos_recortados)
	print("  - Tramos sin recortar (vía plena): %d" % (net.paths.size() - tramos_absorbidos - tramos_recortados))

	print("\n--- AUDITORÍA FINALIZADA CON ÉXITO ---")
	quit(0)

func _recolectar_switches(n: Node, out: Array[Node]) -> void:
	if n is BaseTurnout or n is ProceduralCrossing or n is ProceduralCrossover or n is ProceduralScissorsCrossover:
		out.append(n)
	for c in n.get_children():
		_recolectar_switches(c, out)
