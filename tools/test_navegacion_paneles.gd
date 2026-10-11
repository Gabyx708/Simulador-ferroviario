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

	# set_anchors_preset no resetea los offsets por sí solo (conserva el
	# tamaño "aparente" previo del control) -- si se vuelve a olvidar forzarlos
	# a 0, NavegacionPaneles queda más chico que el viewport real y los
	# botones (anclados "abajo-centro" relativo a ESE rect) aparecen
	# desplazados hacia arriba-izquierda en vez de abajo-centro de verdad.
	var root_size: Vector2 = Vector2(root.size)
	assert(nav.get_global_rect().size.is_equal_approx(root_size),
		"NavegacionPaneles debe ocupar el viewport completo (%s), no %s" % [str(root_size), str(nav.get_global_rect().size)])

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

	# Métricas abre como modal grande (3/4 de pantalla), no como el bottom
	# sheet chico que usa "control" -- se verifica con el tamaño real, no
	# adivinando constantes.
	var tamaño_modal: Vector2 = nav._panel_actual.get_global_rect().size
	var tamaño_viewport: Vector2 = Vector2(root.size)
	assert(tamaño_modal.x > tamaño_viewport.x * 0.7 and tamaño_modal.y > tamaño_viewport.y * 0.7,
		"El modal de métricas debe ocupar la mayor parte de la pantalla (%s de %s)" % [str(tamaño_modal), str(tamaño_viewport)])

	var boton_cerrar_modal: Button = nav._panel_actual.find_child("BotonCerrarModal", true, false) as Button
	assert(boton_cerrar_modal != null, "El modal debe tener su propio botón de cierre")
	boton_cerrar_modal.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "", "El botón '✕ Cerrar' del modal debe cerrarlo")

	boton_metricas.pressed.emit()
	await process_frame
	var fondo_modal: Button = nav._panel_actual.find_child("FondoModal", true, false) as Button
	assert(fondo_modal != null, "El modal debe tener un fondo oscurecido clickeable")
	fondo_modal.pressed.emit()
	await process_frame
	assert(nav.panel_abierto() == "", "Clickear el fondo oscurecido también debe cerrar el modal")

	boton_metricas.pressed.emit()
	await process_frame
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
