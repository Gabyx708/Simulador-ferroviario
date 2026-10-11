extends SceneTree
## Comprueba que los multiplicadores del HUD no replanifican ni alteran la
## distancia ferroviaria publicada al próximo poste.

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz := (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await process_frame
	await process_frame
	var tren := raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	# Esperar la salida de Plaza: así se mide la distancia real hacia Yrigoyen,
	# no el cero legítimo de la parada inicial.
	await create_timer(3.5).timeout
	assert(tren.proxima_estacion_nombre() == "Hipólito Yrigoyen", "La métrica debe medirse durante la primera aproximación")
	var distancia_base: float = tren.distancia_a_proxima_estacion()
	assert(distancia_base >= 0.0, "El tren no tiene distancia ferroviaria inicial")
	tren.establecer_factores_prueba(3.0, 10.0, 10.0)
	assert(is_equal_approx(tren.distancia_a_proxima_estacion(), distancia_base), "Los multiplicadores alteraron la distancia de ruta")
	assert(is_equal_approx(tren.velocidad_max_kmh, 90.0), "El control de prueba modificó la velocidad base")
	assert(is_equal_approx(tren.aceleracion_efectiva(), tren.aceleracion * 10.0), "La aceleración de prueba debe alcanzar ×10")
	assert(is_equal_approx(tren.desaceleracion_efectiva(), tren.desaceleracion * 10.0), "El frenado de prueba debe alcanzar ×10")
	tren.establecer_factores_prueba(1.0, 1.0, 1.0)
	assert(is_equal_approx(tren.distancia_a_proxima_estacion(), distancia_base), "Restablecer multiplicadores alteró la distancia")
	# También cubre el fallo original: editar los valores base desde Inspector
	# durante runtime no puede alterar la métrica ferroviaria ya planificada.
	tren.velocidad_max_kmh *= 3.0
	tren.aceleracion *= 3.0
	tren.desaceleracion *= 3.0
	assert(is_equal_approx(tren.distancia_a_proxima_estacion(), distancia_base), "Cambiar velocidad/aceleración base alteró la distancia ferroviaria")
	print("OK: distancia ferroviaria invariante ante multiplicadores de prueba (%.2f m)" % distancia_base)
	quit()
