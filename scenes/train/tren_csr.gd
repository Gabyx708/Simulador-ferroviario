@tool
extends Tren
class_name TrenCSR
## Formación eléctrica CSR Zhuzhou (Línea Roca).
## Especialización de la clase Tren con parámetros nominales y modelos 3D de la EMU CSR.

func _init() -> void:
	cantidad_coches = 7
	velocidad_max_kmh = 90.0
	aceleracion = 0.8
	desaceleracion = 1.0
	tiempo_parada = 20.0
	paso = 26.0
	semi_bogie = 8.90
	radio_rueda = 0.43
	if escena_coche_motriz == null:
		escena_coche_motriz = preload("res://assets/models/train/csr_roca_coche_motriz.glb")
	if escena_coche_remolcado == null:
		escena_coche_remolcado = preload("res://assets/models/train/csr_roca_coche_remolcado.glb")
