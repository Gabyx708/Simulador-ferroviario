@tool
class_name CarroPrueba
extends Node3D
## Vehículo / dresina de inspección ferroviaria para pruebas dinámicas de desvíos.
## Se desplaza a lo largo de una trayectoria Curve3D mediante PathFollow3D,
## demostrando físicamente el guiado de pestañas a través de las agujas y corazones.

signal recorrido_completado()

@export var velocidad: float = 10.0 # m/s (~36 km/h)
@export var en_movimiento: bool = false

var _path: Path3D = null
var _follow: PathFollow3D = null
var _cuerpo_visual: Node3D = null
var _luz_faro: OmniLight3D = null
var _longitud_curva: float = 0.0


func _ready() -> void:
	_construir_jerarquia()
	_construir_modelo_3d()


func _process(delta: float) -> void:
	if not en_movimiento or _follow == null or _longitud_curva <= 0.01:
		return

	_follow.progress += velocidad * delta

	if _follow.progress >= _longitud_curva - 0.1:
		_follow.progress = _longitud_curva
		en_movimiento = false
		recorrido_completado.emit()


## Asigna una curva de vía y lanza el carro desde el inicio hacia el final.
func asignar_curva_y_lanzar(curva: Curve3D, vel: float = 10.0) -> void:
	_asegurar_nodos()
	if curva == null or curva.point_count < 2:
		return

	velocidad = vel
	_path.curve = curva
	_longitud_curva = curva.get_baked_length()
	_follow.progress = 0.0
	en_movimiento = true


## Reinicia el carro a la posición inicial sin moverlo.
func reiniciar_posicion(curva: Curve3D) -> void:
	_asegurar_nodos()
	if curva == null or curva.point_count < 2:
		return

	_path.curve = curva
	_longitud_curva = curva.get_baked_length()
	_follow.progress = 0.0
	en_movimiento = false


func _asegurar_nodos() -> void:
	if _path == null:
		_construir_jerarquia()
	if _cuerpo_visual == null:
		_construir_modelo_3d()


func _construir_jerarquia() -> void:
	for c: Node in get_children():
		if c is Path3D:
			_path = c as Path3D
			break

	if _path == null:
		_path = Path3D.new()
		_path.name = "PathTrayectoria"
		add_child(_path)

	for c: Node in _path.get_children():
		if c is PathFollow3D:
			_follow = c as PathFollow3D
			break

	if _follow == null:
		_follow = PathFollow3D.new()
		_follow.name = "Seguidor"
		_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
		_follow.loop = false
		_path.add_child(_follow)


func _construir_modelo_3d() -> void:
	if _follow == null:
		return

	for c: Node in _follow.get_children():
		if c.name == "ModeloCarro":
			_cuerpo_visual = c as Node3D
			return

	_cuerpo_visual = Node3D.new()
	_cuerpo_visual.name = "ModeloCarro"
	_follow.add_child(_cuerpo_visual)

	# Materiales PBR
	var mat_chasis: StandardMaterial3D = StandardMaterial3D.new()
	mat_chasis.albedo_color = Color(0.92, 0.72, 0.08, 1.0) # Amarillo vial de obra
	mat_chasis.roughness = 0.4
	mat_chasis.metallic = 0.2

	var mat_acero: StandardMaterial3D = StandardMaterial3D.new()
	mat_acero.albedo_color = Color(0.20, 0.21, 0.22, 1.0) # Acero oscuro
	mat_acero.roughness = 0.3
	mat_acero.metallic = 0.9

	var mat_faro: StandardMaterial3D = StandardMaterial3D.new()
	mat_faro.albedo_color = Color(1.0, 0.95, 0.7, 1.0)
	mat_faro.emission_enabled = true
	mat_faro.emission = Color(1.0, 0.95, 0.7, 1.0)
	mat_faro.emission_energy_multiplier = 3.0

	# 1. Chasis principal de la dresina
	var chasis: MeshInstance3D = MeshInstance3D.new()
	chasis.name = "Chasis"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.90, 0.35, 3.20)
	chasis.mesh = box
	chasis.position = Vector3(0.0, 0.45, 0.0)
	chasis.material_override = mat_chasis
	_cuerpo_visual.add_child(chasis)

	# 2. Cabina superior / capot de maquinaria
	var cabina: MeshInstance3D = MeshInstance3D.new()
	cabina.name = "Cabina"
	var box_cab: BoxMesh = BoxMesh.new()
	box_cab.size = Vector3(1.50, 0.60, 1.60)
	cabina.mesh = box_cab
	cabina.position = Vector3(0.0, 0.85, -0.20)
	cabina.material_override = mat_acero
	_cuerpo_visual.add_child(cabina)

	# 3. Ejes y Ruedas con pestañas
	var trocha_media: float = 0.838 # Trocha ancha
	var pos_ejes: Array[float] = [-1.0, 1.0] # Eje trasero y delantero

	for z_eje: float in pos_ejes:
		# Eje transversal
		var eje: MeshInstance3D = MeshInstance3D.new()
		var cyl_eje: CylinderMesh = CylinderMesh.new()
		cyl_eje.top_radius = 0.05
		cyl_eje.bottom_radius = 0.05
		cyl_eje.height = 1.90
		eje.mesh = cyl_eje
		eje.rotation.z = deg_to_rad(90.0)
		eje.position = Vector3(0.0, 0.20, z_eje)
		eje.material_override = mat_acero
		_cuerpo_visual.add_child(eje)

		# 2 Ruedas (Izquierda y Derecha)
		for lado: float in [-1.0, 1.0]:
			var rueda: MeshInstance3D = MeshInstance3D.new()
			var cyl_rueda: CylinderMesh = CylinderMesh.new()
			cyl_rueda.top_radius = 0.22
			cyl_rueda.bottom_radius = 0.22
			cyl_rueda.height = 0.12
			rueda.mesh = cyl_rueda
			rueda.rotation.z = deg_to_rad(90.0)
			rueda.position = Vector3(trocha_media * lado, 0.20, z_eje)
			rueda.material_override = mat_acero
			_cuerpo_visual.add_child(rueda)

	# 4. Farol frontal con luz activa
	var faro_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl_faro: CylinderMesh = CylinderMesh.new()
	cyl_faro.top_radius = 0.12
	cyl_faro.bottom_radius = 0.12
	cyl_faro.height = 0.15
	faro_mesh.mesh = cyl_faro
	faro_mesh.rotation.x = deg_to_rad(90.0)
	faro_mesh.position = Vector3(0.0, 0.75, 1.62)
	faro_mesh.material_override = mat_faro
	_cuerpo_visual.add_child(faro_mesh)

	_luz_faro = OmniLight3D.new()
	_luz_faro.name = "LuzFaro"
	_luz_faro.light_color = Color(1.0, 0.95, 0.8)
	_luz_faro.light_energy = 2.5
	_luz_faro.omni_range = 15.0
	_luz_faro.position = Vector3(0.0, 0.75, 1.90)
	_cuerpo_visual.add_child(_luz_faro)
