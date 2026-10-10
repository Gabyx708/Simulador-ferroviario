extends BaseLevel
class_name RamalRocaMainLevel
## Nivel principal del Ramal General Roca (Constitución - Bosques)
## que utiliza la red ferroviaria topológica real (TrackNetwork)
## adaptada a los nuevos cambios de vía procedurales (Tipos A, B, C, D, E)
## con extremos flexibles adaptativos y curvatura continua C1.

@export_group("Componentes del Nivel")
@export var red_ferroviaria: TrackNetwork

var _tren_inicializado: bool = false


func _ready() -> void:
	super._ready()

	if red_ferroviaria == null:
		red_ferroviaria = find_child("TrackNetwork", true, false) as TrackNetwork
	if red_ferroviaria == null:
		red_ferroviaria = find_child("RedFerroviaria", true, false) as TrackNetwork

	if red_ferroviaria != null:
		if not red_ferroviaria.red_cargada.is_connected(_on_red_cargada):
			red_ferroviaria.red_cargada.connect(_on_red_cargada)
		if not red_ferroviaria.paths.is_empty():
			_inicializar_traza_y_tren()


func _on_red_cargada(_total_segmentos: int, _total_uniones: int) -> void:
	_inicializar_traza_y_tren()


func _inicializar_traza_y_tren() -> void:
	if red_ferroviaria == null or _tren_inicializado:
		return

	# La escena puede traer una traza y posición de inicio elegidas en el
	# Inspector. No se deben sobrescribir cuando la red se vuelve a cargar.
	if formacion_principal != null and "traza" in formacion_principal:
		var traza_configurada: Path3D = formacion_principal.get("traza") as Path3D
		if traza_configurada != null and is_instance_valid(traza_configurada) and traza_configurada.curve != null:
			traza = traza_configurada
			_tren_inicializado = true
			return

	# Buscar segmento troncal para posicionar la formación (ej. seg_470 o seg_471 en Constitución)
	var tramo_candidato: Path3D = null
	for id_candidato in ["seg_470", "seg_471", "seg_1", "seg_179"]:
		if red_ferroviaria.paths.has(id_candidato):
			tramo_candidato = red_ferroviaria.paths[id_candidato] as Path3D
			break

	if tramo_candidato == null and not red_ferroviaria.paths.is_empty():
		tramo_candidato = red_ferroviaria.paths.values()[0] as Path3D

	if tramo_candidato != null:
		traza = tramo_candidato
		if formacion_principal != null:
			if formacion_principal.has_method("set_traza"):
				formacion_principal.call("set_traza", traza)
			elif "traza" in formacion_principal:
				formacion_principal.set("traza", traza)
			formacion_principal.set("avance_inicial", 10.0)
			if formacion_principal.has_method("_ubicar"):
				formacion_principal.call("_ubicar", 0.0)
		_tren_inicializado = true

