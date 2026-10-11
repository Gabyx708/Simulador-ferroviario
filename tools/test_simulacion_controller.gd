extends SceneTree
## Comprueba que la fachada pública no depende de detalles de ruteo y sigue
## trenes iniciales, altas y bajas del nivel.
## Uso: godot --headless --path . -s res://tools/test_simulacion_controller.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2).timeout
	var controlador: SimulacionController = raiz.get_node_or_null("SimulacionController") as SimulacionController
	assert(controlador != null, "El nivel debe incluir SimulacionController")

	var trenes: Array[Dictionary] = controlador.obtener_trenes()
	assert(trenes.size() == 4, "El controlador debe registrar los cuatro trenes iniciales")
	var ids: Dictionary = {}
	for tren: Dictionary in trenes:
		var id: int = int(tren.get("id", 0))
		assert(id > 0 and not ids.has(id), "Cada tren debe tener un id operativo único")
		assert(not tren.has("traza") and not tren.has("ruta"), "El resumen público no debe filtrar detalles de ruteo")
		ids[id] = true

	var estaciones: Array[Dictionary] = controlador.obtener_estaciones()
	assert(estaciones.size() == 16, "El controlador debe registrar las 16 estaciones")
	assert(not controlador.obtener_estacion(str(estaciones[0].get("id", ""))).is_empty(), "Una estación debe poder consultarse por id")

	var resumen: Dictionary = controlador.obtener_resumen_global()
	assert(int(resumen.get("trenes_activos", 0)) == 4, "El resumen debe contabilizar la flota activa")
	assert(is_zero_approx(float(resumen.get("demora_promedio_s", -1.0))), "La demora debe ser neutra hasta el módulo de estadísticas")

	var alta: Dictionary = controlador.agregar_tren()
	assert(bool(alta.get("ok", false)), "La API debe resolver una alta o su cola de despacho")
	if not bool(alta.get("en_cola", false)):
		var datos_alta: Dictionary = alta.get("tren", {}) as Dictionary
		var id_alta: int = int(datos_alta.get("id", 0))
		assert(id_alta > 0 and not controlador.obtener_tren(id_alta).is_empty(), "El tren agregado debe registrarse inmediatamente")
		assert(controlador.eliminar_tren(id_alta), "La API debe eliminar un tren registrado")
		assert(controlador.obtener_tren(id_alta).is_empty(), "La baja debe liberar el registro público")

	print("OK: SimulacionController registra, consulta y administra la flota")
	quit()
