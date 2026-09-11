@tool
extends Path3D
class_name TrazaOSM
## Path3D que se arma solo a partir de traza_osm.json (salida de osm_a_godot.py).
##
## Reemplaza al Path3D "Traza" de la escena cuando querés el trazado real
## en vez del circuito de prueba. Godot 4.2

@export_file("*.json") var archivo := "res://traza_osm.json"

@export var reconstruir: bool = false:
	set(v):
		reconstruir = false
		construir()

## 0.33 da una interpolación Catmull-Rom exacta. Bajalo si ves que la curva
## se "pasa de rosca" en los quiebres cerrados de la traza.
@export_range(0.0, 0.5, 0.01) var suavizado: float = 0.33

## Recorta la traza a los primeros N metros. 0 = usar toda.
@export var recorte_m: float = 0.0

## Cierra la traza sobre sí misma (útil para que el tren circule sin fin).
@export var circuito: bool = false

var largo_m: float = 0.0


func _ready() -> void:
	if curve == null or curve.point_count < 2:
		construir()


func construir() -> void:
	if not FileAccess.file_exists(archivo):
		push_error("TrazaOSM: no encuentro %s" % archivo)
		return

	var texto := FileAccess.get_file_as_string(archivo)
	var datos = JSON.parse_string(texto)
	if typeof(datos) != TYPE_DICTIONARY or not datos.has("puntos"):
		push_error("TrazaOSM: el JSON no tiene la clave 'puntos'")
		return

	var crudos: Array[Vector3] = []
	for p in datos["puntos"]:
		crudos.append(Vector3(p[0], p[1], p[2]))

	if crudos.size() < 2:
		push_error("TrazaOSM: la traza tiene menos de dos puntos")
		return

	if recorte_m > 0.0:
		var acum: float = 0.0
		var cortados: Array[Vector3] = [crudos[0]]
		for i in range(1, crudos.size()):
			acum += crudos[i].distance_to(crudos[i - 1])
			cortados.append(crudos[i])
			if acum >= recorte_m:
				break
		crudos = cortados

	if circuito and crudos[0].distance_to(crudos[-1]) > 0.01:
		crudos.append(crudos[0])

	var c: Curve3D = Curve3D.new()
	var n: int = crudos.size()
	for i: int in n:
		var pos: Vector3 = crudos[i]
		var anterior: Vector3 = crudos[i - 1] if i > 0 else crudos[i]
		var siguiente: Vector3 = crudos[i + 1] if i < n - 1 else crudos[i]

		# En un circuito los extremos se miran entre sí para no hacer un pico.
		if circuito:
			if i == 0:
				anterior = crudos[n - 2]
			elif i == n - 1:
				siguiente = crudos[1]

		var tangente: Vector3 = (siguiente - anterior)
		if tangente.length_squared() < 1e-6:
			tangente = Vector3.FORWARD
		tangente = tangente.normalized()

		var d_atras: float = pos.distance_to(anterior)
		var d_adelante: float = pos.distance_to(siguiente)
		c.add_point(pos,
				- tangente * d_atras * suavizado,
				tangente * d_adelante * suavizado)

	curve = c
	largo_m = c.get_baked_length()
	print("TrazaOSM: %d puntos, %.1f m" % [n, largo_m])

	# Los hijos con @tool (Via, Catenaria) se rehacen con la curva nueva.
	for hijo in get_children():
		if hijo.has_method("_construir"):
			hijo.call("_construir")


## Progreso en metros del punto de la traza más cercano a una posición.
## Sirve para calcular los valores de "paradas" de la formación: ubicá un
## Marker3D en el andén y pasale su global_position.
func progreso_mas_cercano(punto: Vector3, paso: float = 2.0) -> float:
	if curve == null:
		return 0.0
	var mejor: float = 0.0
	var mejor_d: float = INF
	var d: float = 0.0
	while d < curve.get_baked_length():
		var q: Vector3 = curve.sample_baked(d, true)
		var dist: float = q.distance_squared_to(punto)
		if dist < mejor_d:
			mejor_d = dist
			mejor = d
		d += paso
	return mejor
