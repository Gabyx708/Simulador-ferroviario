extends SceneTree
## Auditoría de integración aparatos de vía <-> vías reales.
##
## Mide, para cada puerto flexible de cada switch:
##   • "gap": distancia entre el extremo exterior del tramo flexible y la vía real.
##   • "angulo": desalineación en grados entre la tangente del flexible y la de
##     la vía real en el punto de contacto.
##   • Cuántos tramos quedan visibles/cortados/absorbidos por los aparatos.
##
## Uso: godot --headless --path . -s res://tools/audit_integracion_switches.gd

const UMBRAL_GAP_M: float = 0.25
const UMBRAL_ANGULO_DEG: float = 3.0


func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var scn: PackedScene = load("res://levels/ramal_roca_main/ramal_roca_main.tscn")
	if scn == null:
		print("FAIL: no se pudo cargar ramal_roca_main.tscn")
		quit(1)
		return

	var root_node: Node = scn.instantiate()
	root.add_child(root_node)
	await create_timer(1.5).timeout

	var net: TrackNetwork = root_node.find_child("TrackNetwork", true, false) as TrackNetwork
	if net == null:
		print("FAIL: TrackNetwork no encontrado")
		quit(1)
		return

	print("\n=== AUDITORÍA DE INTEGRACIÓN SWITCH <-> VÍAS ===")
	print("Tramos en red: %d | Aparatos: %d" % [net.paths.size(), net.aparatos_de_via.size()])

	# --- Estado de recortes por tramo ---
	var visibles: int = 0
	var cortados: int = 0
	var absorbidos: int = 0
	for seg_id: String in net.paths.keys():
		var p: Path3D = net.paths[seg_id] as Path3D
		if p == null or p.curve == null:
			continue
		var largo: float = p.curve.get_baked_length()
		var rangos: Array[Vector2] = net.obtener_rangos_utiles_tramo(seg_id)
		if rangos.is_empty():
			absorbidos += 1
		else:
			var rango: Vector2 = rangos[0]
			if rango.x > 0.5 or rango.y < largo - 0.5:
				cortados += 1
			else:
				visibles += 1
	print("Tramos completos: %d | Cortados: %d | Absorbidos: %d" % [visibles, cortados, absorbidos])

	# --- Medición autoritativa: la registra el propio TrackNetwork al conectar ---
	var gaps: PackedFloat32Array = PackedFloat32Array()
	var kinks: PackedFloat32Array = PackedFloat32Array()
	var malos_gap: int = 0
	var malos_kink: int = 0
	var degenerados: int = 0
	var degenerados_naturales: int = 0
	var huecos_reales: int = 0
	var peores: Array[Dictionary] = []
	for clave: Variant in net._conexiones_switch_segmento.keys():
		if str(clave) == "_en_proceso":
			continue
		var d: Dictionary = net._conexiones_switch_segmento[clave] as Dictionary
		var g: float = float(d.get("gap", -1.0))
		var k: float = float(d.get("kink_deg", -1.0))
		if g < 0.0:
			degenerados += 1
			# Sin curva puede ser NATURAL (el riel del aparato termina justo sobre la
			# vía real ⇒ no hace falta transición) o un HUECO real.
			var sep: float = _distancia_borne_a_via(net, d)
			var natural: bool = sep <= 0.5
			if natural:
				degenerados_naturales += 1
			else:
				huecos_reales += 1
				peores.append({
					"switch": str(d.get("switch_name", "?")), "lead": str(d.get("lead_name", "?")),
					"seg": str(d.get("segment_id", "?")), "gap": 999.0, "angulo": 0.0,
					"ext": float(d.get("lead_ext", 0.0)),
					"p0": d.get("p0_local", Vector3.ZERO), "p1": d.get("p1_local", Vector3.ZERO),
					"d0": d.get("d0_local", Vector3.FORWARD), "df": d.get("dir_fin_local", Vector3.FORWARD)
				})
			continue
		gaps.append(g)
		kinks.append(k)
		if g > UMBRAL_GAP_M:
			malos_gap += 1
		if k > UMBRAL_ANGULO_DEG:
			malos_kink += 1
		peores.append({
			"switch": str(d.get("switch_name", "?")), "lead": str(d.get("lead_name", "?")),
			"seg": str(d.get("segment_id", "?")), "gap": g, "angulo": k
		})

	print("\nConexiones registradas: %d | sin curva: %d (naturales: %d | HUECOS reales: %d)" % [
		gaps.size(), degenerados, degenerados_naturales, huecos_reales
	])
	print("Gap  -> máx %.3f m | promedio %.3f m | conexiones > %.2f m: %d" % [
		_max_de(gaps), _media_de(gaps), UMBRAL_GAP_M, malos_gap
	])
	print("Quiebre -> máx %.2f° | promedio %.2f° | conexiones > %.1f°: %d" % [
		_max_de(kinks), _media_de(kinks), UMBRAL_ANGULO_DEG, malos_kink
	])

	peores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["angulo"]) > float(b["angulo"]))
	# --- Naturalidad geométrica de los extremos flexibles (curvatura/deriva) ---
	var malos_radio: int = 0
	var peores_curva: Array[Dictionary] = []
	for nid2: int in net.aparatos_de_via.keys():
		var sw2: BaseTurnout = net.aparatos_de_via[nid2] as BaseTurnout
		if sw2 == null:
			continue
		var ge: Node = sw2.get_node_or_null("ExtremosFlexibles")
		if ge == null:
			continue
		for h2: Node in ge.get_children():
			if not (h2 is FlexibleTrackLead):
				continue
			var lead2: FlexibleTrackLead = h2 as FlexibleTrackLead
			if lead2.curve == null or lead2.curve.point_count < 2:
				continue
			var largo: float = lead2.curve.get_baked_length()
			if largo < 0.3:
				continue
			var pasos: int = maxi(4, int(ceil(largo / 1.0)))
			var ds: float = largo / float(pasos)
			var radio_min: float = INF
			var tang_prev: Vector3 = Vector3.ZERO
			var p0c: Vector3 = lead2.curve.sample_baked(0.0)
			var p1c: Vector3 = lead2.curve.sample_baked(largo)
			var eje: Vector3 = (p1c - p0c).normalized()
			var deriva: float = 0.0
			for s2: int in range(pasos + 1):
				var d2: float = minf(float(s2) * ds, largo)
				var pt2: Vector3 = lead2.curve.sample_baked(d2)
				deriva = maxf(deriva, (pt2 - p0c).cross(eje).length() if eje.length_squared() > 1e-6 else 0.0)
				var t2: Vector3 = (lead2.curve.sample_baked(minf(largo, d2 + 0.25)) - lead2.curve.sample_baked(maxf(0.0, d2 - 0.25)))
				if t2.length_squared() > 1e-8:
					t2 = t2.normalized()
					if tang_prev.length_squared() > 1e-8:
						var giro: float = acos(clampf(t2.dot(tang_prev), -1.0, 1.0))
						if giro > 1e-5 and ds > 1e-5:
							radio_min = minf(radio_min, ds / giro)
					tang_prev = t2
			var radio_txt: String
			if is_inf(radio_min):
				radio_txt = "recta"
			else:
				radio_txt = "%.0f m" % radio_min
			peores_curva.append({
				"switch": String(sw2.name), "lead": String(lead2.name),
				"largo": largo, "deriva": deriva, "radio": radio_min, "radio_txt": radio_txt,
				"ratio": _ratio_proyeccion(lead2)
			})
			if (not is_inf(radio_min) and radio_min < 80.0) or deriva > 1.0:
				malos_radio += 1

	print("\nExtremos flexibles con geometría forzada (radio < 80 m o deriva > 1 m): %d" % malos_radio)
	var b85: int = 0
	var b60: int = 0
	var b40: int = 0
	var peor_ratio: float = 1.0
	for c: Dictionary in peores_curva:
		var r: float = float(c["ratio"])
		peor_ratio = minf(peor_ratio, r)
		if r < 0.85:
			b85 += 1
		if r < 0.60:
			b60 += 1
		if r < 0.40:
			b40 += 1
	print("Desvío relativo del extremo (proyección/largo): peor %.2f | <0.85: %d | <0.60: %d | <0.40: %d" % [
		peor_ratio, b85, b60, b40
	])
	peores_curva.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["radio"]) < float(b["radio"]))
	print("Top 12 extremos menos naturales:")
	for i: int in mini(12, peores_curva.size()):
		var d3: Dictionary = peores_curva[i]
		print("  %-32s %-24s largo %6.2f m  deriva %6.2f m  ratio %.2f  radio %s" % [
			d3["switch"], d3["lead"], float(d3["largo"]), float(d3["deriva"]),
			float(d3["ratio"]), d3["radio_txt"]
		])

	print("\nTop 15 conexiones con mayor quiebre tangencial:")
	for i: int in mini(15, peores.size()):
		var d: Dictionary = peores[i]
		print("  %-30s %-24s %-9s gap %7.3f  ang %6.2f°" % [
			d["switch"], d["lead"], d["seg"], float(d["gap"]), float(d["angulo"])
		])

	peores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["gap"]) > float(b["gap"]))
	print("\nDetalle de las primeras 12 conexiones SIN geometría (hueco):")
	var mostrados: int = 0
	for d: Dictionary in peores:
		if float(d["gap"]) < 900.0:
			continue
		print("  %-30s %-24s %-9s ext=%.1f p0=%s d0=%s p1=%s df=%s" % [
			d["switch"], d["lead"], d["seg"], float(d.get("ext", 0.0)),
			str(d.get("p0", Vector3.ZERO)), str(d.get("d0", Vector3.ZERO)),
			str(d.get("p1", Vector3.ZERO)), str(d.get("df", Vector3.ZERO))
		])
		mostrados += 1
		if mostrados >= 12:
			break

	print("\n=== FIN AUDITORÍA ===")
	quit(0)


## Distancia entre el borne (riel del aparato en ese puerto) y la vía real más cercana.
## Proyección del extremo exterior sobre el eje de salida dividida por la distancia
## total: 1.0 = empalme recto y natural; << 1 = codo lateral forzado.
func _ratio_proyeccion(lead: FlexibleTrackLead) -> float:
	if lead == null or lead.curve == null or lead.curve.point_count < 2:
		return 1.0
	var i_fin: int = lead.curve.point_count - 1
	var p0: Vector3 = lead.curve.get_point_position(0)
	var p1: Vector3 = lead.curve.get_point_position(i_fin)
	var d0: Vector3 = (lead.curve.get_point_out(0) if lead.curve.get_point_out(0).length_squared() > 1e-8 else (p1 - p0))
	if d0.length_squared() < 1e-8:
		return 1.0
	d0 = d0.normalized()
	var dist: float = p0.distance_to(p1)
	if dist < 1e-4:
		return 1.0
	return clampf((p1 - p0).dot(d0) / dist, 0.0, 1.0)


func _distancia_borne_a_via(net: TrackNetwork, d: Dictionary) -> float:
	var nid: int = int(d.get("switch_node_id", 0))
	var sw: BaseTurnout = net.aparatos_de_via.get(nid) as BaseTurnout
	if sw == null:
		return 999.0
	var g_ext: Node = sw.get_node_or_null("ExtremosFlexibles")
	if g_ext == null:
		return 999.0
	var lead: FlexibleTrackLead = g_ext.get_node_or_null(str(d.get("lead_name", ""))) as FlexibleTrackLead
	if lead == null:
		return 999.0
	var p_borne: Vector3 = lead.global_transform * lead.punto_inicio
	var mejor: float = INF
	for seg_id: String in net.paths.keys():
		var p: Path3D = net.paths[seg_id] as Path3D
		if p == null or p.curve == null or p.curve.point_count < 2:
			continue
		var cercano: Vector3 = p.curve.get_closest_point(p.to_local(p_borne))
		mejor = minf(mejor, p.to_global(cercano).distance_to(p_borne))
	if is_inf(mejor):
		return 999.0
	return mejor


func _max_de(v: PackedFloat32Array) -> float:
	var m: float = 0.0
	for x: float in v:
		m = maxf(m, x)
	return m


func _media_de(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s: float = 0.0
	for x: float in v:
		s += x
	return s / float(v.size())
