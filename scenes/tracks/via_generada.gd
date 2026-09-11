@tool
extends Node3D
class_name ViaGenerada
## Genera la via (balasto + rieles + durmientes) siguiendo un Path3D.
##
## El tramo modular via_roca_tramo.glb sirve para rectas, pero el Roca entre
## Bosques y Constitucion es casi todo curva suave. Esto barre el perfil del
## riel a lo largo de la curva, asi que no hay quiebres entre segmentos.
##
## Uso: colgalo de un Node3D hijo del Path3D (o asignale "traza" a mano) y
## tocá "Regenerar". Se reconstruye solo en el editor al mover los puntos.
##
## Godot 4.x / 4.7

@export var traza: Path3D
@export var regenerar: bool = false:
	set(v):
		regenerar = false
		_construir()

@export_group("Via")
@export var trocha_media: float = 0.838 ## centro de riel, coincide con el coche
@export var separacion_durmientes: float = 0.625
@export var paso_muestreo: float = 1.0 ## metros entre secciones; bajalo en curvas cerradas
@export var generar_balasto: bool = true

@export_group("Materiales")
@export var mat_riel: Material
@export var mat_balasto: Material
@export var mat_durmiente: Material

# Perfil de riel UIC 54, en metros, con la cara de rodadura en y = 0.
const PERFIL_RIEL: Array[Vector2] = [
	Vector2(-0.070, -0.159), Vector2(0.070, -0.159),
	Vector2(0.070, -0.135), Vector2(0.009, -0.115),
	Vector2(0.009, -0.048), Vector2(0.035, -0.035),
	Vector2(0.035, 0.000), Vector2(-0.035, 0.000),
	Vector2(-0.035, -0.035), Vector2(-0.009, -0.048),
	Vector2(-0.009, -0.115), Vector2(-0.070, -0.135),
]

const PERFIL_BALASTO: Array[Vector2] = [
	Vector2(-2.65, -0.66), Vector2(2.65, -0.66),
	Vector2(1.95, -0.30), Vector2(-1.95, -0.30),
]


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
	if largo < paso_muestreo * 2.0:
		return

	if generar_balasto:
		_agregar_malla(_barrer(curva, PERFIL_BALASTO, 0.0), "Balasto", mat_balasto)
	_agregar_malla(_barrer(curva, PERFIL_RIEL, -trocha_media), "Riel_izq", mat_riel)
	_agregar_malla(_barrer(curva, PERFIL_RIEL, trocha_media), "Riel_der", mat_riel)
	_agregar_durmientes(curva, largo)


## Barre un perfil cerrado (x,y) a lo largo de la curva, desplazado en x.
func _barrer(curva: Curve3D, perfil: Array[Vector2], desplazamiento: float) -> ArrayMesh:
	var largo: float = curva.get_baked_length()
	var pasos: int = int(ceil(largo / paso_muestreo))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# perimetro acumulado para la U de las UV
	var peri: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	for i: int in perfil.size():
		peri.append(acc)
		acc += perfil[i].distance_to(perfil[(i + 1) % perfil.size()])

	var anillos: Array[PackedVector3Array] = []
	var recorridos: PackedFloat32Array = PackedFloat32Array()
	for p: int in pasos + 1:
		var d: float = minf(float(p) * largo / float(pasos), largo)
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.05, largo), true) -
				curva.sample_baked(maxf(d - 0.05, 0.0), true)).normalized()
		if adelante.length_squared() < 0.5:
			adelante = Vector3.FORWARD
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()

		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(origen
				+ costado * (pt.x + desplazamiento)
				+ arriba * pt.y)
		anillos.append(anillo)
		recorridos.append(d)

	var n: int = perfil.size()
	for p: int in pasos:
		for i: int in n:
			var j: int = (i + 1) % n
			var a: Vector3 = anillos[p][i]
			var b: Vector3 = anillos[p][j]
			var c: Vector3 = anillos[p + 1][j]
			var e: Vector3 = anillos[p + 1][i]
			var v0: float = recorridos[p]
			var v1: float = recorridos[p + 1]
			_quad(st, a, b, c, e,
				Vector2(peri[i], v0), Vector2(peri[j], v0),
				Vector2(peri[j], v1), Vector2(peri[i], v1))

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)


func _agregar_durmientes(curva: Curve3D, largo: float) -> void:
	var cantidad: int = int(largo / separacion_durmientes)
	if cantidad <= 0:
		return

	var caja: BoxMesh = BoxMesh.new()
	caja.size = Vector3(2.60, 0.20, 0.26)
	if mat_durmiente:
		caja.material = mat_durmiente

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = caja
	mm.instance_count = cantidad

	for i: int in cantidad:
		var d: float = separacion_durmientes * (float(i) + 0.5)
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.05, largo), true) -
				curva.sample_baked(maxf(d - 0.05, 0.0), true)).normalized()
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()
		var base: Basis = Basis(costado, arriba, adelante)
		mm.set_instance_transform(i, Transform3D(base, origen - arriba * 0.275))

	var nodo: MultiMeshInstance3D = MultiMeshInstance3D.new()
	nodo.multimesh = mm
	nodo.name = "Durmientes"
	add_child(nodo)


func _agregar_malla(malla: ArrayMesh, nombre: String, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = malla
	mi.name = nombre
	if mat:
		mi.material_override = mat
	add_child(mi)
