extends SceneTree
## Godot --headless --path . -s res://tools/test_navegacion_paneles.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout

	var nav: NavegacionPaneles = nivel.find_child("NavegacionPaneles", true, false) as NavegacionPaneles
	assert(nav != null, "NavegacionPaneles debe existir en el HUD del nivel")
	assert(nav.panel_abierto() == "", "Ningún panel debe estar abierto al arrancar")

	var boton_control: Button = nav.find_child("BotonControl", true, false) as Button
	var boton_metricas: Button = nav.find_child("BotonMetricas", true, false) as Button
	var boton_reservado: Button = nav.find_child("BotonReservado", true, false) as Button
	assert(boton_control != null and boton_metricas != null and boton_reservado != null, "Los 3 botones deben existir")

	boton_control.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "control", "Apretar el botón de control debe abrir ese panel")

	boton_metricas.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "metricas", "Apretar métricas debe cambiar al panel de métricas (no quedarse en control)")

	boton_metricas.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "", "Apretar el mismo botón de nuevo debe cerrar el panel")

	boton_reservado.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "reservado", "El botón reservado debe abrir su placeholder")

	print("OK: navegación abre/cierra correctamente entre los 3 paneles")

	nivel.queue_free()
	await process_frame
	print("OK: test_navegacion_paneles completo")
	quit()
