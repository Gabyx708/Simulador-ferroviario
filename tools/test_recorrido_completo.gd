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
var _reanudaciones: int = 0
var _llegadas_publicas: Array[String] = []
var _salidas_publicas: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	var raiz := (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2, true, false, true).timeout
	var tren := raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	var red := raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	assert(red != null, "No existe TrackNetwork")
	# Esta prueba valida una formación completa. Las otras tres se congelan,
	# se apartan de la detección y liberan sus reservas para aislar el recorrido.
	for otro_raw: Node in get_nodes_in_group("trenes"):
		var otro := otro_raw as Tren
		if otro != null and otro != tren:
			red.liberar_reservas_tren(otro.get_instance_id())
			otro._apartado_de_via = true
			otro._desplazamiento_lateral_actual = 4.8
			otro.set_process(false)
	tren.velocidad_max_kmh = 240.0
	tren.aceleracion = 24.0
	tren.desaceleracion = 32.0
	tren.tiempo_parada_servicio = 0.1
	tren.tiempo_parada = 0.1
	tren.capacidad_pasajeros = 80
	tren.pasajeros_actuales = 40
	tren.cantidad_pasajeros_por_tanda = 80
	tren.intervalo_pasajeros = 0.02
	for estacion_raw: Node in get_nodes_in_group("estaciones"):
		if estacion_raw is Estacion:
			(estacion_raw as Estacion).tiempo_espera = 0.1
	tren.parada_alcanzada.connect(_al_detenerse.bind(tren))
	tren.marcha_reanudada.connect(func() -> void: _reanudaciones += 1)
	tren.llego_a_estacion.connect(func(_datos_tren: Dictionary, datos_estacion: Dictionary) -> void: _llegadas_publicas.append(str(datos_estacion.get("nombre", ""))))
	tren.salio_de_estacion.connect(func(_datos_tren: Dictionary, datos_estacion: Dictionary) -> void: _salidas_publicas.append(str(datos_estacion.get("nombre", ""))))

	var limite := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < limite and (_detenciones.size() < ESPERADAS.size() - 1 or tren.pasajeros_actuales > 0):
		await process_frame

	Engine.time_scale = 1.0
	var esperadas_durante_marcha: Array = ESPERADAS.slice(1)
	var salidas_esperadas: Array = ESPERADAS.slice(0, ESPERADAS.size() - 1)
	print("DIAG detenciones: %s" % str(_detenciones))
	print("DIAG destino=%s detenido=%s finalizado=%s" % [tren.proxima_estacion_nombre(), tren.esta_detenido(), tren.servicio_finalizado()])
	assert(_detenciones == esperadas_durante_marcha, "Detenciones inesperadas: %s" % str(_detenciones))
	assert(_llegadas_publicas == esperadas_durante_marcha, "Las llegadas públicas deben seguir las detenciones: %s" % str(_llegadas_publicas))
	assert(_salidas_publicas == salidas_esperadas, "Las salidas públicas no deben incluir Bosques: %s" % str(_salidas_publicas))
	assert(tren.esta_detenido(), "El tren debe quedar detenido en Bosques")
	assert(tren.proxima_estacion_nombre() == "Bosques", "El último destino debe ser Bosques")
	assert(not tren.servicio_finalizado(), "Bosques debe permitir el regreso")
	assert(tren.pasajeros_actuales == 0, "En Bosques deben descender todos los pasajeros")
	assert(tren.visible, "La formación debe permanecer visible para el regreso")
	assert(is_zero_approx(tren.velocidad_actual()), "La formación debe detenerse en Bosques")
	print("OK: ida completa hasta Bosques (%d estaciones); regreso habilitado" % _detenciones.size())
	quit()


func _al_detenerse(_indice: int, tren: Tren) -> void:
	_detenciones.append(tren.proxima_estacion_nombre())
