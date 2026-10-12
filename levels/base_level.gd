extends Node3D
class_name BaseLevel
## Controlador base para escenas de nivel / simulación en Train Simulator.
##
## Orquesta la vinculación de referencias entre la cámara, el tren principal
## y la traza ferroviaria al iniciar la escena.

@export_group("Referencias del Nivel")
@export var camara: Camera3D
@export var formacion_principal: Node3D
@export var traza: Path3D


func _ready() -> void:
	# Autoconexión de cámara con el tren para seguimiento (tecla F)
	if camara == null:
		camara = find_child("CamaraLibre", true, false) as Camera3D
		if camara == null:
			camara = find_child("Camara", true, false) as Camera3D

	if formacion_principal == null:
		formacion_principal = find_child("TrenCSR", true, false) as Node3D
		if formacion_principal == null:
			formacion_principal = find_child("Formacion", true, false) as Node3D

	if traza == null:
		traza = find_child("Traza", true, false) as Path3D

	if formacion_principal != null and "traza" in formacion_principal and formacion_principal.get("traza") == null:
		formacion_principal.set("traza", traza)

	# El tablero permanece vacío hasta una selección explícita. La cámara y el
	# HUD se vinculan juntos desde _on_tren_seleccionado().
	if camara != null and "formacion" in camara:
		camara.set("formacion", null)
	var velocimetro: Velocimetro = find_child("Velocimetro", true, false) as Velocimetro
	if velocimetro != null:
		velocimetro.soltar_tren()

	# Selección de tren por clic: con más de una formación en la escena, el
	# HUD y el seguimiento de cámara pueden apuntar a un tren distinto del
	# principal si el usuario hace clic sobre él.
	get_viewport().physics_object_picking = true
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			if not nodo.seleccionado.is_connected(_on_tren_seleccionado):
				nodo.seleccionado.connect(_on_tren_seleccionado.bind(nodo))
			if not nodo.eliminado.is_connected(_on_tren_eliminado):
				nodo.eliminado.connect(_on_tren_eliminado.bind(nodo))
	for nodo: Node in get_tree().get_nodes_in_group("estaciones"):
		if nodo is Estacion:
			if not nodo.seleccionada.is_connected(_on_estacion_seleccionada):
				nodo.seleccionada.connect(_on_estacion_seleccionada)


## Reapunta la cámara y el HUD al tren que el usuario clickeó en el viewport.
func _on_tren_seleccionado(tren: Tren) -> void:
	var informacion: InformacionEstacion = find_child("InformacionEstacion", true, false) as InformacionEstacion
	if informacion != null:
		informacion.cerrar()
	if camara is CamaraLibre:
		(camara as CamaraLibre).seguir_tren_cenital(tren)
	elif camara != null and "formacion" in camara:
		camara.set("formacion", tren)

	var velocimetro: Velocimetro = find_child("Velocimetro", true, false) as Velocimetro
	if velocimetro != null:
		velocimetro.tren = tren


func _on_estacion_seleccionada(estacion: Estacion) -> void:
	var informacion: InformacionEstacion = find_child("InformacionEstacion", true, false) as InformacionEstacion
	if informacion == null:
		return
	var velocimetro: Velocimetro = find_child("Velocimetro", true, false) as Velocimetro
	if velocimetro != null:
		velocimetro.soltar_tren()
	informacion.mostrar_estacion(estacion)


## Si la cámara estaba siguiendo al tren eliminado, la suelta (pasa a modo
## libre). El HUD se suelta solo: escucha esta misma señal directamente.
func _on_tren_eliminado(tren: Tren) -> void:
	if camara != null and "formacion" in camara and camara.get("formacion") == tren:
		camara.set("formacion", null)
