extends SceneTree
## Diagnóstico puntual para convertir una posición geográfica de estación en
## el Path3D y progreso métrico reales de la red cargada.

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"
const LAT0 := -34.6252
const LON0 := -58.3822
const RADIO := 6371000.0

const ESTACIONES := [
	["Plaza Constitución", -34.6290177, -58.3806061],
	["Hipólito Yrigoyen", -34.653642, -58.378887],
	["Darío Santillán y Maximiliano Kosteki", -34.6617505, -58.3766166],
	["Gerli", -34.685728, -58.382637],
	["Lanús", -34.7095604, -58.3912051],
	["Remedios de Escalada", -34.727092, -58.393661],
	["Banfield", -34.7435531, -58.3952955],
	["Lomas de Zamora", -34.7611607, -58.3972105],
	["Temperley", -34.7761329, -58.3959348],
	["José Mármol", -34.7919952, -58.3808474],
	["Rafael Calzada", -34.7966978, -58.3590671],
	["Claypole", -34.8011974, -58.3381252],
	["Ing. Dante Ardigó", -34.809255, -58.300812],
	["Florencio Varela", -34.8111223, -58.2740562],
	["Estanislao S. Zeballos", -34.8109910, -58.2566751],
	["Bosques", -34.8195548, -58.2301509],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz := (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(1.0).timeout
	var red := raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	for dato: Array in ESTACIONES:
		var punto := _a_mundo(float(dato[1]), float(dato[2]))
		var id := red.get_closest_segment(punto)
		var path := red.get_segment_path(id)
		var offset := path.curve.get_closest_offset(path.to_local(punto))
		var cercano := path.to_global(path.curve.sample_baked(offset, true))
		print("%s|%s|%.1f|%.1f|%s" % [dato[0], id, offset, cercano.distance_to(punto), path.get_path()])
	quit()


func _a_mundo(latitud: float, longitud: float) -> Vector3:
	var x := deg_to_rad(longitud - LON0) * RADIO * cos(deg_to_rad(LAT0))
	var z := -deg_to_rad(latitud - LAT0) * RADIO
	return Vector3(x, 0.0, z)
