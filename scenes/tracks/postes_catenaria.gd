@tool
extends Node3D
class_name CatenariaGenerada
## Distribuye postes de catenaria a lo largo de un Path3D, alternando de lado.
## Colgalo como hijo del Path3D. Godot 4.x / 4.7

const POSTE: PackedScene = preload("res://assets/models/tracks/poste_catenaria.glb")

@export var traza: Path3D
@export var regenerar: bool = false:
	set(v):
		regenerar = false
		_construir()

@export var separacion: float = 55.0 ## en el Roca van cada 50-60 m
@export var alternar_lados: bool = true


func _ready() -> void:
	if traza == null and get_parent() is Path3D:
		traza = get_parent()
	_construir()


func _construir() -> void:
	for c in get_children():
		remove_child(c)
		c.free()

	if traza == null or traza.curve == null:
		return
	var curva: Curve3D = traza.curve
	var largo: float = curva.get_baked_length()
	var cantidad: int = int(largo / separacion)
	if cantidad <= 0:
		return

	for i: int in cantidad:
		var d: float = separacion * float(i)
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.1, largo), true) -
				curva.sample_baked(maxf(d - 0.1, 0.0), true)).normalized()
		if adelante.length_squared() < 0.5:
			continue
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()

		var poste: Node3D = POSTE.instantiate() as Node3D
		add_child(poste)
		var base: Basis = Basis(costado, arriba, adelante)
		if alternar_lados and i % 2 == 1:
			base = base.rotated(arriba, PI)
		poste.transform = Transform3D(base, origen)
		poste.name = "Poste_%03d" % i
