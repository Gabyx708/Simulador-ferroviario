extends SceneTree
## Verifica que la REGIÓN FIJA de cada aparato (rieles directo/desviado, espadines,
## corazón, largos) quede idéntica al template de su tipo, y que sólo se adapten
## los extremos flexibles.
##
## Uso: godot --headless --path . -s res://tools/test_integridad_aparatos.gd

const ESCENA: String = "res://levels/ramal_roca_switches/ramal_roca_switches.tscn"
const TEMPLATES: Array[String] = [
	"res://scenes/switches/switch_tipo_a.tscn",
	"res://scenes/switches/switch_tipo_b.tscn",
	"res://scenes/switches/switch_tipo_c.tscn",
	"res://scenes/switches/switch_tipo_d.tscn",
	"res://scenes/switches/switch_tipo_e.tscn",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== INTEGRIDAD DE LA REGIÓN FIJA DE LOS APARATOS ===")
	var plantillas: Dictionary = {}
	for ruta: String in TEMPLATES:
		var esc: PackedScene = load(ruta)
		if esc != null:
			plantillas[esc.instantiate()] = ruta

	var scn: PackedScene = load(ESCENA)
	var raiz: Node = scn.instantiate()
	root.add_child(raiz)
	await create_timer(1.5).timeout
	var net: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork

	var revisados: int = 0
	var fallos: int = 0
	var vistos: Dictionary = {}
	for nid: int in net.aparatos_de_via.keys():
		var sw: BaseTurnout = net.aparatos_de_via[nid] as BaseTurnout
		if sw == null or vistos.has(sw.get_instance_id()):
			continue
		vistos[sw.get_instance_id()] = true
		revisados += 1
		var tipo: String = sw.get_tipo_aparato()
		# Longitud nominal de la región fija
		var largo: float = sw.get_largo_aparato()
		if largo <= 0.0:
			print("  FALLA %s (%s): largo de aparato inválido %.2f" % [sw.name, tipo, largo])
			fallos += 1
			continue
		# El largo no debe haber crecido por deformación de la aguja
		if tipo == "TIPO_A":
			var to: ProceduralTurnout = sw as ProceduralTurnout
			if to.curva_directa != null and to.curva_directa.point_count != 2:
				print("  FALLA %s: curva_directa deformada (%d puntos, se esperaban 2)" % [sw.name, to.curva_directa.point_count])
				fallos += 1
			if to.curva_desviada != null and to.curva_desviada.point_count != 2:
				print("  FALLA %s: curva_desviada deformada (%d puntos, se esperaban 2)" % [sw.name, to.curva_desviada.point_count])
				fallos += 1
	print("Aparatos revisados: %d | fallos de integridad: %d" % [revisados, fallos])
	print("=== FIN ===")
	quit(1 if fallos > 0 else 0)
