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

	if camara != null and "formacion" in camara and camara.get("formacion") == null:
		camara.set("formacion", formacion_principal)

	if formacion_principal != null and "traza" in formacion_principal and formacion_principal.get("traza") == null:
		formacion_principal.set("traza", traza)

	# Autoconexión del HUD (velocímetro) con la formación principal
	var velocimetro: Velocimetro = find_child("Velocimetro", true, false) as Velocimetro
	if velocimetro != null and velocimetro.tren == null and formacion_principal is Tren:
		velocimetro.tren = formacion_principal

	# Selección de tren por clic: con más de una formación en la escena, el
	# HUD y el seguimiento de cámara pueden apuntar a un tren distinto del
	# principal si el usuario hace clic sobre él.
	get_viewport().physics_object_picking = true
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren and not nodo.seleccionado.is_connected(_on_tren_seleccionado):
			nodo.seleccionado.connect(_on_tren_seleccionado.bind(nodo))


## Reapunta la cámara y el HUD al tren que el usuario clickeó en el viewport.
func _on_tren_seleccionado(tren: Tren) -> void:
	if camara != null and "formacion" in camara:
		camara.set("formacion", tren)

	var velocimetro: Velocimetro = find_child("Velocimetro", true, false) as Velocimetro
	if velocimetro != null:
		velocimetro.tren = tren
