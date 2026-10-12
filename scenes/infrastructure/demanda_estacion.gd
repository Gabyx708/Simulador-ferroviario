@tool
extends Resource
class_name DemandaEstacion
## Perfil de demanda de pasajeros por estacion.

@export_group("Ritmo de simulación")
## Intervalo de referencia para convertir pasajeros por formación a pasajeros/s.
@export_range(0.1, 86400.0, 0.1, "suffix:s") var intervalo_formaciones: float = 12.0
@export_range(0.0, 1.0, 0.01) var variacion: float = 0.15

@export_group("Promedios por formación: a Constitución")
@export_range(0, 100000, 1) var suben_a_constitucion: int = 0
@export_range(0, 100000, 1) var bajan_a_constitucion: int = 0

@export_group("Promedios por formación: a Bosques")
@export_range(0, 100000, 1) var suben_a_bosques: int = 0
@export_range(0, 100000, 1) var bajan_a_bosques: int = 0

func promedio_subida(hacia_constitucion: bool) -> int:
	return suben_a_constitucion if hacia_constitucion else suben_a_bosques


## Los promedios de subida regulan las llegadas a la estación, no el embarque.
func sortear_generacion(hacia_constitucion: bool) -> int:
	return _sortear_promedio(promedio_subida(hacia_constitucion))


func sortear_bajada(hacia_constitucion: bool) -> int:
	return _sortear_promedio(bajan_a_constitucion if hacia_constitucion else bajan_a_bosques)


func _sortear_promedio(promedio: int) -> int:
	var margen: float = clampf(variacion, 0.0, 1.0)
	var minimo: int = maxi(0, ceili(float(promedio) * (1.0 - margen)))
	var maximo: int = maxi(minimo, floori(float(promedio) * (1.0 + margen)))
	return randi_range(minimo, maximo)
