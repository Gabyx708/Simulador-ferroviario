extends SceneTree
## Sonda puntual: por qué la unión X no se clasifica como tijera (TIPO_E).
## Uso: godot --headless --path . -s res://tools/probe_tijera.gd

const ESCENA: String = "res://levels/ramal_roca_switches/ramal_roca_switches.tscn"
var _centro: int = 2621609179


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scn: PackedScene = load(ESCENA)
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(1.2).timeout
	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_centro = int(args[0])
	print("\n=== SONDA UNION %d (ramas %d) ===" % [_centro, (net.junctions.get(str(_centro), {}) as Dictionary).get("segments", []).size()])
	var sw_c: BaseTurnout = net.aparatos_de_via.get(_centro) as BaseTurnout
	if sw_c != null:
		print("aparato en la escena: %s (%s)" % [sw_c.name, sw_c.get_tipo_aparato()])

	var j: Dictionary = net.junctions.get(str(_centro), {}) as Dictionary
	for c_raw: Variant in (j.get("segments", []) as Array):
		var c: Dictionary = c_raw as Dictionary
		var sid: String = str(c.get("segment_id", ""))
		var seg: Dictionary = net.segments_data.get(sid, {}) as Dictionary
		var n_s: int = int(seg.get("node_start", 0))
		var n_e: int = int(seg.get("node_end", 0))
		var other: int = n_e if n_s == _centro else n_s
		var j_oth: Dictionary = net.junctions.get(str(other), {}) as Dictionary
		var largo: float = 0.0
		var p: Path3D = net.paths.get(sid) as Path3D
		if p != null and p.curve != null:
			largo = p.curve.get_baked_length()
		print("\n rama %s -> nodo %d | ramas vecinas %d | largo %.1f m | end=%s" % [
			sid, other, (j_oth.get("segments", []) as Array).size(), largo, str(c.get("end", "?"))
		])
		print("   estricta: '%s' == '%s' ? %s" % [
			net._detectar_segmento_desviado_union(other), sid,
			str(net._detectar_segmento_desviado_union(other) == sid)
		])
		print("   tolerante(%d, %s): %s" % [other, sid, str(net._es_rama_desviada_tolerante(other, sid))])
		# Direcciones de las ramas de la unión vecina
		for c2_raw: Variant in (j_oth.get("segments", []) as Array):
			var c2: Dictionary = c2_raw as Dictionary
			var sid2: String = str(c2.get("segment_id", ""))
			var v: Vector2 = net._obtener_vector_salida_segmento(sid2, str(c2.get("end", "start")))
			print("      vecina rama %s dir(%.2f, %.2f)" % [sid2, v.x, v.y])
	quit(0)
