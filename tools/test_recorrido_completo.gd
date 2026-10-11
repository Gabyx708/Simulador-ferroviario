extends SceneTree
## Ejecuta el servicio en modo acelerado y comprueba sus detenciones reales.
## Uso: godot --headless --path . -s res://tools/test_recorrido_completo.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"
const ESPERADAS := [
	"Plaza Constitución", "Hipólito Yrigoyen", "Darío Santillán y Maximiliano Kosteki",
	"Gerli", "Lanús", "Remedios de Escalada", "Banfield", "Lomas de Zamora",
	"Temperley", "José Mármol", "Rafael Calzada", "Claypole", "Ing. Dante Ardigó",
	"Florencio Varela", "Estanislao S. Zeballos", "Bosques",
]

var _detenciones: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 8.0
	var raiz := (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(1.0, true, false, true).timeout
	var tren := raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	tren.velocidad_max_kmh = 1000.0
	tren.aceleracion = 24.0
	tren.desaceleracion = 32.0
	tren.tiempo_parada = 0.1
	tren.parada_alcanzada.connect(_al_detenerse.bind(tren))

	var limite := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < limite and _detenciones.size() < ESPERADAS.size():
		await process_frame

	Engine.time_scale = 1.0
	print("DIAG detenciones: %s" % str(_detenciones))
	print("DIAG destino=%s detenido=%s" % [tren.proxima_estacion_nombre(), tren.esta_detenido()])
	assert(_detenciones == ESPERADAS, "Detenciones inesperadas: %s" % str(_detenciones))
	assert(tren.esta_detenido(), "El tren debe quedar detenido en Bosques")
	assert(tren.proxima_estacion_nombre() == "Bosques", "El último destino debe ser Bosques")
	print("OK: recorrido completo detenido en Bosques (%d estaciones)" % _detenciones.size())
	quit()


func _al_detenerse(_indice: int, tren: Tren) -> void:
	_detenciones.append(tren.proxima_estacion_nombre())
